import XCTest
@testable import JamBox

/// Tiny formatters on `Track` — pure value transformations, no I/O.
final class FormattersTests: XCTestCase {

    // MARK: - durationString

    private func track(duration: TimeInterval) -> Track {
        Track(
            url: URL(fileURLWithPath: "/tmp/x.mp3"),
            displayName: "x",
            artist: "",
            album: "",
            trackNumber: nil,
            duration: duration
        )
    }

    func testDurationZero() {
        XCTAssertEqual(track(duration: 0).durationString, "0:00")
    }

    func testDurationSubMinute() {
        XCTAssertEqual(track(duration: 59).durationString, "0:59")
    }

    func testDurationExactlyOneMinute() {
        XCTAssertEqual(track(duration: 60).durationString, "1:00")
    }

    /// Current implementation is mm:ss across the board (no h:mm:ss break),
    /// so 3599s formats as "59:59" and 3600s formats as "60:00". These
    /// assertions lock in current behavior; if a future card adds a proper
    /// h:mm:ss break these assertions will need updating along with the
    /// implementation.
    func testDurationJustUnderOneHour() {
        XCTAssertEqual(track(duration: 3599).durationString, "59:59")
    }

    func testDurationExactlyOneHour() {
        XCTAssertEqual(track(duration: 3600).durationString, "60:00")
    }

    // MARK: - trackNumberString

    private func track(trackNumber: Int?) -> Track {
        Track(
            url: URL(fileURLWithPath: "/tmp/x.mp3"),
            displayName: "x",
            artist: "",
            album: "",
            trackNumber: trackNumber,
            duration: 0
        )
    }

    func testTrackNumberNilIsEmpty() {
        XCTAssertEqual(track(trackNumber: nil).trackNumberString, "")
    }

    func testTrackNumberZero() {
        XCTAssertEqual(track(trackNumber: 0).trackNumberString, "0")
    }

    func testTrackNumberOne() {
        XCTAssertEqual(track(trackNumber: 1).trackNumberString, "1")
    }

    func testTrackNumberNinetyNine() {
        XCTAssertEqual(track(trackNumber: 99).trackNumberString, "99")
    }

    func testTrackNumberHundred() {
        XCTAssertEqual(track(trackNumber: 100).trackNumberString, "100")
    }
}
