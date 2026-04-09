import Combine
import XCTest
@testable import JamBox

/// Layer 3a integration tests — `PlayerEngine` against real fixture audio.
///
/// These tests drive the real `AVFoundation` stack against the 1-second
/// audio fixtures committed by card 0006a. They are slower than unit
/// tests (typical run: ~5–15s for the whole suite) but are the only
/// tests that would catch a regression in the actual playback pipeline.
///
/// The two highest-stakes tests here are:
///   - `testFLACBitDepthFallback` — regression for card 0020 (24-bit
///     FLAC source depth requires the STREAMINFO fallback parser).
///   - `testFLACDurationMatchesActual` — regression for §7.1 (the
///     AVURLAsset precise-timing option).
///
/// Both cards shipped bugs to users in v1.3; without these tests we
/// would ship them again.
@MainActor
final class PlayerEngineIntegrationTests: XCTestCase {

    // MARK: - Helpers

    /// Build a `Track` array from fixture (name, ext) pairs. Uses the
    /// cheap `Track(url:)` init — the same one `FileScanner.scanFolder`
    /// uses in production before metadata enrichment runs.
    private func tracks(_ items: [(String, String)]) -> [Track] {
        items.compactMap { name, ext in
            FixtureLoader.url(named: name, extension: ext).map { Track(url: $0) }
        }
    }

    /// Wait up to `timeout` seconds for `condition` to become true, polling
    /// the main run loop in short ticks. Used when a Combine sink is overkill
    /// (e.g. we're waiting on `clock.position` which is not directly
    /// `@Published` on `PlayerEngine`).
    private func waitFor(
        _ description: String,
        timeout: TimeInterval = 3.0,
        _ condition: @escaping () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTFail("Timed out waiting for: \(description)", file: file, line: line)
    }

    /// Wait for a published value to satisfy `predicate`. Preferred over
    /// `waitFor` for anything that IS `@Published` because it wakes up on
    /// the real upstream signal rather than polling.
    private func waitForPublished<P: Publisher>(
        _ publisher: P,
        description: String,
        timeout: TimeInterval = 3.0,
        predicate: @escaping (P.Output) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where P.Failure == Never {
        let exp = expectation(description: description)
        exp.assertForOverFulfill = false
        var bag = Set<AnyCancellable>()
        publisher.sink { value in
            if predicate(value) { exp.fulfill() }
        }.store(in: &bag)
        let result = XCTWaiter().wait(for: [exp], timeout: timeout)
        if result != .completed {
            XCTFail("Timed out waiting for: \(description)", file: file, line: line)
        }
        bag.removeAll()
    }

    // MARK: - Tests

    /// Acceptance 1: play(startingAt:) starts playback within a reasonable
    /// timeout; `isPlaying` flips true, `currentTrack` is set, and
    /// `clock.duration` becomes > 0.
    func testPlayStartsPlaybackWithinTimeout() {
        let engine = PlayerEngine()
        engine.loadTracks(tracks([("tone", "wav")]))
        XCTAssertEqual(engine.tracks.count, 1)

        engine.play(startingAt: 0)

        waitForPublished(
            engine.$isPlaying,
            description: "isPlaying becomes true",
            timeout: 2.0,
            predicate: { $0 == true }
        )
        XCTAssertNotNil(engine.currentTrack)
        waitFor("clock.duration > 0", timeout: 2.0) { engine.clock.duration > 0 }

        engine.togglePlayPause() // pause so the tone doesn't bleed into the next test
    }

    /// Acceptance 2: §7.2 gapless lookahead — with 5 tracks loaded,
    /// `queuedItemCount` should be exactly 3 (the lookahead).
    func testGaplessLookaheadEqualsThree() {
        let engine = PlayerEngine()
        engine.loadTracks(tracks([
            ("tone", "wav"),
            ("tone", "aiff"),
            ("tone", "mp3"),
            ("tone", "m4a"),
            ("tone-16", "flac"),
        ]))
        XCTAssertEqual(engine.tracks.count, 5)

        engine.play(startingAt: 0)

        // Lookahead fill is synchronous inside `play(startingAt:)`, but we
        // still wait a beat for AVQueuePlayer to register — it should be
        // immediate in practice.
        waitFor("queuedItemCount == 3", timeout: 2.0) { engine.queuedItemCount == 3 }
        XCTAssertEqual(engine.queuedItemCount, 3)

        engine.togglePlayPause()
    }

    /// Acceptance 3: natural advance from one track to the next. Play the
    /// 1-second WAV, wait, and verify `currentTrack` flips to the next.
    func testNaturalAdvanceAcrossTracks() {
        let engine = PlayerEngine()
        let t = tracks([("tone", "wav"), ("tone", "aiff")])
        engine.loadTracks(t)
        let firstURL = t[0].url
        let secondURL = t[1].url

        engine.play(startingAt: 0)

        // Wait for the currentTrack to become the second fixture. Fixtures
        // are 1s, so give it 5s of headroom for startup + natural advance.
        waitForPublished(
            engine.$currentTrack,
            description: "currentTrack advances to second fixture",
            timeout: 5.0,
            predicate: { $0?.url == secondURL }
        )
        XCTAssertEqual(engine.currentTrack?.url, secondURL)
        XCTAssertNotEqual(engine.currentTrack?.url, firstURL)

        engine.togglePlayPause()
    }

    /// Acceptance 4: pause/resume preserves position within 0.1s.
    func testPauseResumePreservesPosition() {
        let engine = PlayerEngine()
        engine.loadTracks(tracks([("tone", "wav")]))
        engine.play(startingAt: 0)

        waitForPublished(engine.$isPlaying, description: "playing", timeout: 2.0, predicate: { $0 })
        waitFor("position advances past 0.1s", timeout: 2.0) { engine.clock.position > 0.1 }

        engine.togglePlayPause()
        waitForPublished(engine.$isPlaying, description: "paused", timeout: 1.0, predicate: { $0 == false })
        let captured = engine.clock.position

        // Wait real-world time; position should NOT drift while paused.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(engine.clock.position, captured, accuracy: 0.05,
                       "position drifted while paused")

        engine.togglePlayPause()
        waitForPublished(engine.$isPlaying, description: "playing again", timeout: 1.0, predicate: { $0 })
        // Immediately after resume, position should be within 0.1s of the
        // captured value. We sample once to avoid racing the periodic time
        // observer.
        XCTAssertLessThan(abs(engine.clock.position - captured), 0.1,
                          "position jumped across pause/resume")

        engine.togglePlayPause()
    }

    /// Acceptance 5: seek(to:) updates clock.position. Fraction 0.5 of a
    /// 1s tone should land the clock near 0.5s.
    func testSeekUpdatesClockPosition() {
        let engine = PlayerEngine()
        engine.loadTracks(tracks([("tone", "wav")]))
        engine.play(startingAt: 0)

        waitFor("duration populated", timeout: 2.0) { engine.clock.duration > 0.5 }

        engine.togglePlayPause() // pause so the tone doesn't finish before we assert
        waitForPublished(engine.$isPlaying, description: "paused", timeout: 1.0, predicate: { $0 == false })

        engine.seek(to: 0.5)

        // Seek is async under the hood; wait for the periodic time observer
        // to pick up the new position.
        waitFor("clock.position lands near 0.5 * duration", timeout: 2.0) {
            abs(engine.clock.position - (engine.clock.duration * 0.5)) < 0.1
        }
    }

    /// Acceptance 6: §7.1 regression — 24-bit FLAC duration matches the
    /// actual 1-second fixture within 0.1s. Without
    /// `AVURLAssetPreferPreciseDurationAndTimingKey` this would fail on
    /// FLAC files whose STREAMINFO header is inaccurate.
    func testFLACDurationMatchesActual() {
        let engine = PlayerEngine()
        engine.loadTracks(tracks([("tone-24", "flac")]))
        engine.play(startingAt: 0)

        // clock.duration starts seeded from Track.duration (0 on a cheap
        // init(url:)) and is overwritten by the periodic time observer
        // once the AVPlayerItem's duration has resolved.
        waitFor("clock.duration resolves", timeout: 3.0) { engine.clock.duration > 0.5 }
        XCTAssertEqual(engine.clock.duration, 1.0, accuracy: 0.1,
                       "24-bit FLAC duration should be ~1.0s — " +
                       "check that AVURLAssetPreferPreciseDurationAndTimingKey is set (§7.1)")

        engine.togglePlayPause()
    }

    /// Acceptance 7: card 0020 regression — 24-bit FLAC must expose
    /// `currentFormat?.bitDepth == 24`. AVFoundation's ASBD reports 0 for
    /// the source bit depth of compressed lossless formats; PlayerEngine
    /// falls back to parsing the STREAMINFO block. Without that fallback,
    /// `currentFormat` would either be nil or have bitDepth != 24.
    func testFLACBitDepthFallback() {
        let engine = PlayerEngine()
        engine.loadTracks(tracks([("tone-24", "flac")]))
        engine.play(startingAt: 0)

        waitForPublished(
            engine.$currentFormat,
            description: "currentFormat populated for 24-bit FLAC",
            timeout: 5.0,
            predicate: { $0 != nil }
        )
        XCTAssertEqual(engine.currentFormat?.name, "FLAC")
        XCTAssertEqual(engine.currentFormat?.bitDepth, 24,
                       "24-bit FLAC should report bitDepth == 24 via STREAMINFO fallback " +
                       "(card 0020 regression)")

        engine.togglePlayPause()
    }
}
