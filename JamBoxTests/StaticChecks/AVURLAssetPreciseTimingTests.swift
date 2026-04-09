import XCTest

/// Layer 1 static check — the single highest-value test in the suite.
///
/// Every `AVURLAsset(` constructor call in `JamBox/*.swift` must include
/// `AVURLAssetPreferPreciseDurationAndTimingKey` in the options dictionary,
/// either inline in the same argument expression or via a symbol literally
/// named `assetOptions` (the project's established convention — see
/// `JamBox/PlayerEngine.swift` and `JamBox/Track.swift`).
///
/// Defends: the FLAC inaccurate-duration regression (README §7.1 and
/// `CLAUDE.md`'s "Critical: AVURLAsset Options" section). Without this
/// option, FLACs with inaccurate STREAMINFO headers play 2-5 seconds past
/// their stated end and emit `FigFilePlayer err=-12864`. We already caught
/// this bug in production once; never again.
final class AVURLAssetPreciseTimingTests: XCTestCase {

    func testEveryAVURLAssetUsesPreciseTimingKey() throws {
        guard let files = RepoRoot.allJamBoxSwiftFiles() else {
            return // RepoRoot already failed the test
        }
        XCTAssertFalse(files.isEmpty, "Expected at least one .swift file under JamBox/")

        var offenses: [String] = []

        for fileURL in files {
            let src = try String(contentsOf: fileURL, encoding: .utf8)
            let occurrences = findAVURLAssetCalls(in: src)
            for occ in occurrences {
                let window = occ.callText
                let hasKey = window.contains("AVURLAssetPreferPreciseDurationAndTimingKey")
                let hasOptionsRef = window.contains("assetOptions")
                if !hasKey && !hasOptionsRef {
                    let relPath = fileURL.lastPathComponent
                    offenses.append(
                        "\(relPath):\(occ.line): AVURLAsset(...) constructed without " +
                        "AVURLAssetPreferPreciseDurationAndTimingKey and without a reference " +
                        "to `assetOptions`. Window: \(window.replacingOccurrences(of: "\n", with: " ⏎ "))"
                    )
                }
            }
        }

        if !offenses.isEmpty {
            XCTFail(
                "Found \(offenses.count) AVURLAsset construction(s) missing precise-timing-key:\n" +
                offenses.joined(separator: "\n") +
                "\n\nFix: use the `assetOptions` constant (see PlayerEngine.swift line ~150) " +
                "or include [AVURLAssetPreferPreciseDurationAndTimingKey: true] inline. " +
                "See CLAUDE.md > 'Critical: AVURLAsset Options'."
            )
        }
    }

    // MARK: - Parser

    private struct Call {
        let line: Int
        let callText: String // from `AVURLAsset(` through the matched closing `)`
    }

    /// Finds every `AVURLAsset(` call in `src` and returns a window of text
    /// spanning from the opening paren through the matched closing paren
    /// (balanced, respecting nested parens and string literals crudely).
    private func findAVURLAssetCalls(in src: String) -> [Call] {
        var results: [Call] = []
        let pattern = "AVURLAsset("
        let chars = Array(src)
        var i = 0
        while i < chars.count {
            if matches(chars: chars, at: i, needle: pattern) {
                let startIdx = i
                // Advance to the opening paren (already at it: i + pattern.count - 1)
                var j = i + pattern.count // just after `(`
                var depth = 1
                var inString = false
                var escape = false
                while j < chars.count && depth > 0 {
                    let c = chars[j]
                    if escape {
                        escape = false
                    } else if inString {
                        if c == "\\" {
                            escape = true
                        } else if c == "\"" {
                            inString = false
                        }
                    } else {
                        if c == "\"" {
                            inString = true
                        } else if c == "(" {
                            depth += 1
                        } else if c == ")" {
                            depth -= 1
                            if depth == 0 { j += 1; break }
                        }
                    }
                    j += 1
                }
                let endIdx = min(j, chars.count)
                let window = String(chars[startIdx..<endIdx])
                // Compute line number of the opening `A` of AVURLAsset(
                let line = lineNumber(of: startIdx, in: chars)
                results.append(Call(line: line, callText: window))
                i = endIdx
            } else {
                i += 1
            }
        }
        return results
    }

    private func matches(chars: [Character], at index: Int, needle: String) -> Bool {
        let n = Array(needle)
        guard index + n.count <= chars.count else { return false }
        for k in 0..<n.count where chars[index + k] != n[k] { return false }
        // Reject if preceded by an identifier character (avoid false matches on FooAVURLAsset)
        if index > 0 {
            let prev = chars[index - 1]
            if prev.isLetter || prev.isNumber || prev == "_" { return false }
        }
        return true
    }

    private func lineNumber(of index: Int, in chars: [Character]) -> Int {
        var line = 1
        var i = 0
        while i < index && i < chars.count {
            if chars[i] == "\n" { line += 1 }
            i += 1
        }
        return line
    }
}
