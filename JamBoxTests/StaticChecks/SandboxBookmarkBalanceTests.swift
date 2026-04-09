import XCTest

/// Layer 1 static check — sandbox bookmark balance.
///
/// Counts occurrences of `startAccessingSecurityScopedResource(` and
/// `stopAccessingSecurityScopedResource(` across `JamBox/*.swift` and
/// asserts the counts are equal. This is a v1 approximation: count-equality
/// does NOT prove per-flow pairing, only that we haven't shipped an obvious
/// imbalance. A future card can tighten this to AST-level pairing.
///
/// Defends: §7.4 (security-scoped bookmark lifecycle). Unbalanced start/stop
/// calls can leak scoped-resource grants, which in extreme cases prevents
/// the sandbox from releasing file handles and can cause mysterious
/// permission denials in long-running sessions.
final class SandboxBookmarkBalanceTests: XCTestCase {

    func testStartAndStopCallsAreBalanced() throws {
        guard let files = RepoRoot.allJamBoxSwiftFiles() else { return }

        var startCount = 0
        var stopCount = 0
        var startLocations: [String] = []
        var stopLocations: [String] = []

        for fileURL in files {
            let src = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = src.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                // Match only the call form (trailing open paren), not the identifier.
                if line.contains("startAccessingSecurityScopedResource(") {
                    startCount += 1
                    startLocations.append("\(fileURL.lastPathComponent):\(idx + 1)")
                }
                if line.contains("stopAccessingSecurityScopedResource(") {
                    stopCount += 1
                    stopLocations.append("\(fileURL.lastPathComponent):\(idx + 1)")
                }
            }
        }

        XCTAssertEqual(
            startCount, stopCount,
            "Unbalanced security-scoped resource calls: " +
            "\(startCount) start vs \(stopCount) stop.\n" +
            "  starts: \(startLocations.joined(separator: ", "))\n" +
            "  stops:  \(stopLocations.joined(separator: ", "))\n" +
            "Defends §7.4. Every startAccessingSecurityScopedResource() needs " +
            "a matching stopAccessingSecurityScopedResource()."
        )
    }
}
