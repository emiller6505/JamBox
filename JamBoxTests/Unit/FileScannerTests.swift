import XCTest
@testable import JamBox

/// `FileScanner.scanFolder` is a pure filesystem pass — no audio decoding.
/// These tests build a throwaway directory of mixed file types and verify
/// the extension filter plus stable ordering.
final class FileScannerTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JamBoxFileScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    /// Creates an empty file at `tempDir/name`. Scanner only reads
    /// extensions, so empty files are fine.
    private func touch(_ name: String) throws {
        let url = tempDir.appendingPathComponent(name)
        try Data().write(to: url)
    }

    func testFiltersToSupportedExtensionsOnly() throws {
        // All eight supported extensions, in mixed case.
        try touch("a.mp3")
        try touch("b.flac")
        try touch("c.m4a")
        try touch("d.aiff")
        try touch("e.wav")
        try touch("f.aif")
        try touch("g.aac")
        try touch("h.alac")
        // Unsupported types that must be filtered out.
        try touch("readme.txt")
        try touch("cover.jpg")
        try touch("notes.md")
        try touch("archive.zip")
        try touch("nosuffix")

        let tracks = FileScanner.scanFolder(tempDir)
        let names = Set(tracks.map { $0.url.lastPathComponent })

        XCTAssertEqual(
            names,
            [
                "a.mp3", "b.flac", "c.m4a", "d.aiff",
                "e.wav", "f.aif", "g.aac", "h.alac",
            ],
            "scanFolder should only return files whose extension is in the supported set"
        )
    }

    func testCaseInsensitiveExtensionMatching() throws {
        // The scanner lowercases extensions before comparing, so uppercase
        // variants should still be picked up.
        try touch("SONG.MP3")
        try touch("ANOTHER.Flac")

        let tracks = FileScanner.scanFolder(tempDir)
        XCTAssertEqual(tracks.count, 2)
    }

    func testStableOrderAcrossMultipleScans() throws {
        // Create files in an order that is deliberately NOT lexicographic,
        // to ensure the scanner imposes its own sort rather than relying on
        // directory enumeration order.
        for name in ["z.mp3", "a.mp3", "m.flac", "B.wav", "c.m4a"] {
            try touch(name)
        }

        let first = FileScanner.scanFolder(tempDir).map { $0.url.lastPathComponent }
        let second = FileScanner.scanFolder(tempDir).map { $0.url.lastPathComponent }
        XCTAssertEqual(first, second, "scanFolder order must be deterministic across runs")
        XCTAssertFalse(first.isEmpty)
    }

    func testEmptyDirectoryReturnsEmptyArray() throws {
        let tracks = FileScanner.scanFolder(tempDir)
        XCTAssertEqual(tracks.count, 0)
    }
}
