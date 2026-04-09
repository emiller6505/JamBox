import XCTest
@testable import JamBox

/// Synchronous `Track.init(url:)` covers the "first pass" path that the UI
/// shows before metadata enrichment. Only the filename-without-extension is
/// exercised here — duration/artist/album are explicitly empty by design.
final class TrackDisplayNameTests: XCTestCase {

    func testPlainFilename() {
        let url = URL(fileURLWithPath: "/tmp/song.mp3")
        XCTAssertEqual(Track(url: url).displayName, "song")
    }

    func testMultipleDots() {
        // "a.b.c.flac" must strip only the final extension.
        let url = URL(fileURLWithPath: "/tmp/a.b.c.flac")
        XCTAssertEqual(Track(url: url).displayName, "a.b.c")
    }

    func testUnicodeFilename() {
        // Accented latin + CJK + em-dash. displayName is raw Unicode.
        let url = URL(fileURLWithPath: "/tmp/café – 歌.m4a")
        XCTAssertEqual(Track(url: url).displayName, "café – 歌")
    }

    func testNoExtension() {
        // `deletingPathExtension().lastPathComponent` on a file with no
        // extension is just the filename itself.
        let url = URL(fileURLWithPath: "/tmp/README")
        XCTAssertEqual(Track(url: url).displayName, "README")
    }

    func testEmptyDefaults() {
        let url = URL(fileURLWithPath: "/tmp/song.mp3")
        let t = Track(url: url)
        XCTAssertEqual(t.artist, "")
        XCTAssertEqual(t.album, "")
        XCTAssertNil(t.trackNumber)
        XCTAssertEqual(t.duration, 0)
    }
}
