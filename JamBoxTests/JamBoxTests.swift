import XCTest

/// Sanity baseline for the test target itself. If this fails, the test target
/// is misconfigured before any real test has a chance to run.
final class JamBoxTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true, "Test infrastructure is alive.")
    }
}
