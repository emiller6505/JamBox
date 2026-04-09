import Foundation
import XCTest

/// Shared helper for loading the audio fixtures committed alongside the
/// test target. Fixtures are copied into the test bundle via XcodeGen's
/// implicit resource phase on non-source files under `JamBoxTests/`.
///
/// Use `FixtureLoader.url(named:extension:)` rather than `Bundle(for:)`
/// directly so every test uses a consistent XCTFail-with-diagnostic path.
enum FixtureLoader {
    /// Returns the on-disk URL for a fixture baked into the test bundle.
    /// Fails the current test with a clear diagnostic if the resource is
    /// missing — the most common cause is a forgotten `xcodegen generate`
    /// after adding a new fixture file.
    static func url(
        named name: String,
        extension ext: String,
        file: StaticString = #file,
        line: UInt = #line
    ) -> URL? {
        // Any XCTestCase subclass lives in the test bundle; use one to anchor.
        let bundle = Bundle(for: FixtureLoaderAnchor.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            XCTFail(
                "Fixture '\(name).\(ext)' not found in test bundle at \(bundle.bundlePath). " +
                "Did you run `xcodegen generate` after adding it?",
                file: file, line: line
            )
            return nil
        }
        return url
    }
}

/// Private anchor class used solely to resolve the test bundle via
/// `Bundle(for:)`. Kept internal to this file so no production code is
/// touched.
private final class FixtureLoaderAnchor: NSObject {}
