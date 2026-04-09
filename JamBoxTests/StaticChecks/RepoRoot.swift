import Foundation
import XCTest

/// Locates the repository source root from a test file's on-disk path.
///
/// Layer 1 static checks scan the production source tree as plain text.
/// Tests don't run from the repo cwd — they run from `xcodebuild`'s build
/// products dir — so we can't rely on `FileManager.currentDirectoryPath`.
/// Instead we climb upward from the test's `#file` path (which `xcodebuild`
/// bakes in as an absolute path at compile time) until we find a directory
/// that contains both `JamBox.xcodeproj` and a `JamBox` source directory.
///
/// If the climb fails (e.g. tests ever run from a pre-archived bundle with
/// no source tree nearby), callers get a clear `XCTFail` diagnostic instead
/// of a cryptic "file not found".
enum RepoRoot {
    /// Walks up from `startingAt` until it finds the repo root, or fails.
    /// - Parameter startingAt: typically `URL(fileURLWithPath: #file)`.
    /// - Returns: the repo root URL, or `nil` if not found (test should fail).
    static func find(startingAt startFile: String = #file) -> URL? {
        var dir = URL(fileURLWithPath: startFile).deletingLastPathComponent()
        let fm = FileManager.default
        // Climb at most 16 levels — more than enough for any sane layout.
        for _ in 0..<16 {
            let xcodeproj = dir.appendingPathComponent("JamBox.xcodeproj")
            let sourceDir = dir.appendingPathComponent("JamBox")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: xcodeproj.path, isDirectory: &isDir), isDir.boolValue,
               fm.fileExists(atPath: sourceDir.path, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break } // reached filesystem root
            dir = parent
        }
        return nil
    }

    /// Convenience: returns the `JamBox/` production source directory, or
    /// fails the current test with a clear diagnostic.
    static func jamBoxSourceDir(file: StaticString = #file, line: UInt = #line) -> URL? {
        guard let root = find() else {
            XCTFail(
                "RepoRoot.find() failed: could not locate a parent directory " +
                "containing both JamBox.xcodeproj and JamBox/. Layer 1 static " +
                "checks require the repository source tree to be present on " +
                "disk relative to the compiled test file.",
                file: file, line: line
            )
            return nil
        }
        return root.appendingPathComponent("JamBox")
    }

    /// Returns all `.swift` files under `JamBox/`, sorted for deterministic
    /// iteration. Returns `nil` (after failing the test) if the source dir
    /// can't be found.
    static func allJamBoxSwiftFiles(file: StaticString = #file, line: UInt = #line) -> [URL]? {
        guard let sourceDir = jamBoxSourceDir(file: file, line: line) else { return nil }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Could not enumerate \(sourceDir.path)", file: file, line: line)
            return nil
        }
        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            out.append(url)
        }
        return out.sorted { $0.path < $1.path }
    }
}
