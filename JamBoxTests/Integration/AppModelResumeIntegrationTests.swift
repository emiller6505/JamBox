import Combine
import XCTest
@testable import JamBox

/// Layer 3a integration tests — resume mechanism regression for card 0012.
///
/// Card 0012 shipped a feature where the app persists the currently-playing
/// track + position and restores it on next launch, paused. The bug that
/// shipped to users was in the resume path — bad enough that this card
/// (0006c) requires explicit regression coverage.
///
/// We test the code path card 0012 fixed: `PlayerEngine.resume(...)`.
/// `AppModel.tryRestorePlayback` is a thin wrapper that decodes
/// `UserDefaults`, does three guards (decoded-ok, file-exists,
/// url-in-current-folder), and hands off to `player.resume`. The guards
/// are invariant Swift plumbing; the bug-prone behavior — "seed
/// currentTrack, seed clock.position, do NOT call play" — lives in
/// `PlayerEngine.resume`, which is what we exercise here.
///
/// Directly constructing `AppModel` in a test is impractical because its
/// init path runs `NSOpenPanel`-style security-scoped bookmark resolution
/// against real UserDefaults, and it calls `NSEvent.addLocalMonitorForEvents`.
/// Testing through AppModel would require mocking the security-scoped
/// subsystem and the NSApp event stack — scope creep well beyond this card.
@MainActor
final class AppModelResumeIntegrationTests: XCTestCase {

    /// Acceptance 8: card 0012 regression — after "save state → resume",
    /// the restored engine has the right track loaded at the right
    /// position and is PAUSED (not playing).
    func testResumeRestoresTrackAndPositionPaused() {
        guard let wavURL = FixtureLoader.url(named: "tone", extension: "wav") else {
            return
        }

        let engine = PlayerEngine()
        engine.loadTracks([Track(url: wavURL)])

        // Simulate the "next launch" path: call `resume` directly with a
        // saved position. This is exactly what `AppModel.tryRestorePlayback`
        // does after its three guards pass.
        let savedPosition: TimeInterval = 0.4
        var failureCalled = false
        engine.resume(trackIndex: 0, position: savedPosition) {
            failureCalled = true
        }

        // Synchronously after `resume` returns, `currentTrack` and
        // `clock.position` must be seeded. `isPlaying` stays false because
        // `resume` never calls `queuePlayer.play()`.
        XCTAssertEqual(engine.currentTrack?.url, wavURL, "resume should load the saved track")
        XCTAssertEqual(engine.clock.position, savedPosition, accuracy: 0.001,
                       "resume should seed clock.position synchronously from the saved value")
        XCTAssertFalse(engine.isPlaying, "resume must leave the engine paused (card 0012)")

        // The underlying `AVQueuePlayer.seek(to:)` inside `resume` lands
        // asynchronously. After it settles, the periodic time observer
        // will reconcile `clock.position` to the saved value. We don't
        // assert on the exact transient steady-state here — the async
        // duration-resolve check below covers "the engine settles correctly."

        // Wait for the async duration-load inside `resume` to populate
        // `clock.duration` with the real 1s value. The engine goes through
        // several transient duration states on this path — seed from
        // Track.duration (0), `handleItemChange` from the currentItem KVO
        // (also 0 for a cheap Track(url:)), then finally the async
        // `asset.load(.duration)` result (~1.0). Poll for the settled
        // non-zero state rather than sampling at a fixed delay.
        let exp = expectation(description: "clock.duration resolves to real value")
        var bag = Set<AnyCancellable>()
        engine.clock.$duration
            .filter { $0 > 0.5 }
            .first()
            .sink { _ in exp.fulfill() }
            .store(in: &bag)
        wait(for: [exp], timeout: 3.0)
        bag.removeAll()

        XCTAssertEqual(engine.clock.duration, 1.0, accuracy: 0.1,
                       "real duration should be loaded after async clamp step")
        XCTAssertEqual(engine.currentTrack?.url, wavURL, "resume should not switch tracks")
        XCTAssertFalse(engine.isPlaying, "engine must remain paused after async duration load")
        XCTAssertFalse(failureCalled, "onFailure must not fire for a valid resumable fixture")
    }

    /// The symmetric negative path: if the saved position overshoots the
    /// real duration, `resume` should clamp to the real duration rather
    /// than invoking onFailure. This pins the "clamp" branch that also
    /// lives in the card 0012 code path.
    func testResumeClampsOvershotPosition() {
        guard let wavURL = FixtureLoader.url(named: "tone", extension: "wav") else {
            return
        }

        let engine = PlayerEngine()
        engine.loadTracks([Track(url: wavURL)])

        var failureCalled = false
        // Fixture is 1 second; 999s is obviously past the end.
        engine.resume(trackIndex: 0, position: 999.0) {
            failureCalled = true
        }

        // Wait for clock.duration to populate with the real asset value —
        // that's the signal that the async clamp step has completed.
        let exp = expectation(description: "duration resolves during clamp")
        var bag = Set<AnyCancellable>()
        engine.clock.$duration
            .filter { $0 > 0.5 }
            .first()
            .sink { _ in exp.fulfill() }
            .store(in: &bag)
        wait(for: [exp], timeout: 3.0)
        bag.removeAll()

        XCTAssertFalse(failureCalled, "valid fixture shouldn't fire onFailure even if position overshoots")
        XCTAssertNotNil(engine.currentTrack, "track should still be loaded after clamp")
        XCTAssertGreaterThan(engine.clock.duration, 0.5,
                             "real duration should be loaded during clamp")
        XCTAssertLessThanOrEqual(engine.clock.position, engine.clock.duration + 0.01,
                                 "position must be clamped to real duration")
        XCTAssertFalse(engine.isPlaying, "still paused after clamp")
    }
}
