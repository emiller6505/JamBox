import XCTest

/// Smoke test for fixture bundling. Runs first (alphabetically) and verifies
/// every fixture the rest of the suite relies on is present in the test
/// bundle. If this fails, every other fixture-driven test will also fail —
/// but with a clear single diagnostic point here first.
final class FixtureLoaderTests: XCTestCase {

    func testAllFixturesArePresentInBundle() {
        let expected: [(String, String)] = [
            ("tone", "mp3"),
            ("tone", "m4a"),
            ("tone-16", "flac"),
            ("tone-24", "flac"),
            ("tone", "wav"),
            ("tone", "aiff"),
        ]
        for (name, ext) in expected {
            guard let url = FixtureLoader.url(named: name, extension: ext) else {
                continue // FixtureLoader already XCTFailed
            }
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "Fixture \(name).\(ext) resolved to \(url.path) but file does not exist"
            )
            // Sanity: fixtures must be non-empty.
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 0, "Fixture \(name).\(ext) is zero bytes")
        }
    }
}
