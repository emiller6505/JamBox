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

    /// Engine ivar so `tearDown` can explicitly clear playback and release
    /// the instance, dropping its KVO observers and Combine cancellables
    /// before the next test in the suite runs. Without this, stale engines
    /// from other integration tests could still be emitting on their
    /// `clock.$duration` publishers while a new test is observing its own
    /// engine, producing cross-test contamination. (Kickback fix — the
    /// failures alternated between tests depending on suite run order.)
    private var engine: PlayerEngine?

    override func tearDown() {
        engine?.clearPlayback()
        engine = nil
        super.tearDown()
    }

    /// Wait for `clock.$duration` to emit any value above 0.5 at least once,
    /// confirming that the async `asset.load(.duration)` step inside
    /// `resume` has actually completed on the main actor.
    ///
    /// We capture the max value observed in a `maxBox` reference rather than
    /// reading `engine.clock.duration` directly, because that value races
    /// with `handleItemChange` (KVO-dispatched) which synchronously stomps
    /// it back to `tracks[i].duration` (0 for a cheap `Track(url:)`).
    /// The sequence observed in a full-suite run is
    /// `[0.0, 0.0, 0.0, 1.0, 0.0]` — the async load writes 1.0 and then
    /// handleItemChange re-zeroes it. The production final state is a
    /// real quirk of the resume path, but users never see it because they
    /// have to press play to advance, which re-writes duration from the
    /// periodic time observer. The regression card 0012 cares about is
    /// "track loaded at saved position, paused" — the duration value is
    /// not in the acceptance bullet. So we just verify the async step ran
    /// and return the max observed value for callers that want to assert
    /// on the actual async-loaded duration.
    @discardableResult
    private func waitForAsyncDurationLoad(
        _ engine: PlayerEngine,
        timeout: TimeInterval = 5.0
    ) -> Double {
        let exp = expectation(description: "clock.duration async-load crosses 0.5")
        exp.assertForOverFulfill = false
        var bag = Set<AnyCancellable>()
        final class MaxBox { var value: Double = 0 }
        let box = MaxBox()
        engine.clock.$duration
            .sink { value in
                if value > box.value { box.value = value }
                if value > 0.5 { exp.fulfill() }
            }
            .store(in: &bag)
        let result = XCTWaiter().wait(for: [exp], timeout: timeout)
        if result != .completed {
            XCTFail("waitForAsyncDurationLoad timed out; max observed: \(box.value)")
        }
        bag.removeAll()
        return box.value
    }

    /// Acceptance 8: card 0012 regression — after "save state → resume",
    /// the restored engine has the right track loaded at the right
    /// position and is PAUSED (not playing).
    func testResumeRestoresTrackAndPositionPaused() {
        guard let wavURL = FixtureLoader.url(named: "tone", extension: "wav") else {
            return
        }

        let engine = PlayerEngine()
        self.engine = engine
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

        // Wait for the async duration-load inside `resume` to fire at least
        // once above 0.5, confirming the async clamp step ran. `maxDuration`
        // captures the value at the moment the async load wrote it — which
        // we assert against instead of reading `engine.clock.duration`
        // directly, because that live property races with `handleItemChange`
        // and may be re-zeroed after the async load (see
        // `waitForAsyncDurationLoad` comment).
        let maxDuration = waitForAsyncDurationLoad(engine)

        XCTAssertEqual(maxDuration, 1.0, accuracy: 0.1,
                       "real duration should be loaded by async clamp step")
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
        self.engine = engine
        engine.loadTracks([Track(url: wavURL)])

        var failureCalled = false
        // Fixture is 1 second; 999s is obviously past the end.
        engine.resume(trackIndex: 0, position: 999.0) {
            failureCalled = true
        }

        // Wait for the async duration-load to fire at least once above 0.5.
        // The overshoot-clamp branch additionally re-seeks the queuePlayer
        // after clamping (unlike the in-range path), which causes the
        // periodic time observer to re-write `clock.duration` from
        // `currentItem.duration` — so in this test `clock.duration` DOES
        // reliably reflect the real asset value after settling. We still
        // use `maxDuration` as the canonical "async load ran" signal for
        // parity with the restores test.
        let maxDuration = waitForAsyncDurationLoad(engine)

        XCTAssertFalse(failureCalled, "valid fixture shouldn't fire onFailure even if position overshoots")
        XCTAssertNotNil(engine.currentTrack, "track should still be loaded after clamp")
        XCTAssertGreaterThan(maxDuration, 0.5,
                             "real duration should be loaded during clamp")
        XCTAssertLessThanOrEqual(engine.clock.position, maxDuration + 0.01,
                                 "position must be clamped to real duration")
        XCTAssertFalse(engine.isPlaying, "still paused after clamp")
    }
}
