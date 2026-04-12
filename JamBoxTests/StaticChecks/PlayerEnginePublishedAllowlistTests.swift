import XCTest

/// Layer 1 static check — `PlayerEngine` `@Published` allowlist.
///
/// Greps `JamBox/PlayerEngine.swift` for `@Published var <name>` declarations
/// within the `PlayerEngine` class (excluding the `PlaybackClock` helper
/// class in the same file) and asserts the set of names equals a
/// hand-maintained allowlist. Any addition or rename forces the allowlist
/// to be updated — which forces a code-review conversation, which is the
/// entire point.
///
/// Defends: card 0002's click-race bug. Adding a new `@Published` on
/// `PlayerEngine` causes `objectWillChange` to fire for every write, which
/// can resurrect the race. The test is brittle by design.
final class PlayerEnginePublishedAllowlistTests: XCTestCase {

    /// Keep this list in sync with the `@Published` properties declared
    /// directly on the `PlayerEngine` class. Do NOT include `@Published`
    /// properties on helper classes (e.g. `PlaybackClock`). If you add a
    /// new `@Published`, update this allowlist in the same PR and explain
    /// why in the commit message.
    static let allowlist: Set<String> = [
        "isPlaying",
        "currentTrack",
        "currentArtwork",
        "tracks",
        "currentFormat",
        "volume",
    ]

    func testPlayerEnginePublishedPropertiesMatchAllowlist() throws {
        guard let sourceDir = RepoRoot.jamBoxSourceDir() else { return }
        let file = sourceDir.appendingPathComponent("PlayerEngine.swift")
        let src = try String(contentsOf: file, encoding: .utf8)

        let lines = src.components(separatedBy: "\n")

        // Find the line range of `class PlayerEngine` (not PlaybackClock).
        // We locate the class declaration, then find the matching closing
        // brace by tracking brace depth from that point.
        var startLine: Int?
        for (idx, line) in lines.enumerated() {
            // Match e.g. "final class PlayerEngine: ObservableObject {"
            if line.contains("class PlayerEngine") && !line.contains("PlaybackClock") {
                startLine = idx
                break
            }
        }
        guard let classStart = startLine else {
            XCTFail("Could not locate `class PlayerEngine` in PlayerEngine.swift")
            return
        }

        var depth = 0
        var seenOpenBrace = false
        var classEnd = lines.count - 1
        for idx in classStart..<lines.count {
            for c in lines[idx] {
                if c == "{" { depth += 1; seenOpenBrace = true }
                else if c == "}" { depth -= 1 }
            }
            if seenOpenBrace && depth == 0 {
                classEnd = idx
                break
            }
        }

        // Now scan just the class body for `@Published var <name>`.
        // Pattern: `@Published` on a line, then extract the identifier after `var `.
        var found: Set<String> = []
        let pattern = #"@Published\s+(?:private(?:\(set\))?\s+|fileprivate\s+|public\s+|internal\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        for idx in classStart...classEnd {
            let line = lines[idx]
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            regex.enumerateMatches(in: line, range: range) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 2,
                      let nameRange = Range(match.range(at: 1), in: line) else { return }
                found.insert(String(line[nameRange]))
            }
        }

        let expected = Self.allowlist
        if found != expected {
            let added = found.subtracting(expected).sorted()
            let removed = expected.subtracting(found).sorted()
            var msg = "PlayerEngine @Published set drift detected.\n"
            msg += "  expected: \(expected.sorted())\n"
            msg += "  found:    \(found.sorted())\n"
            if !added.isEmpty { msg += "  ADDED (update allowlist + card 0002 review): \(added)\n" }
            if !removed.isEmpty { msg += "  REMOVED (update allowlist): \(removed)\n" }
            msg += "Defends card 0002. Every new @Published on PlayerEngine needs deliberate review."
            XCTFail(msg)
        }
    }
}
