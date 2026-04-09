import XCTest

/// Layer 1 static check — single-file AVURLAsset construction site count
/// for `PlayerEngine.swift`.
///
/// Defends: card 0012's `makeAssetItem` extraction AND §7.1's precise-timing
/// contract. The card asked for "exactly 1" construction site, but the
/// reality of the current codebase is **two** legitimate sites:
///
///   1. `PlayerEngine.makeAssetItem(for:)` — the canonical helper used by
///      the playback queue. This is the site card 0012 extracted.
///   2. `PlayerEngine.findArtwork(for:)` — a second, independent site for
///      probing embedded artwork. It has its own legitimate reason to
///      exist (different codepath, different lifecycle, artwork-only).
///
/// Both sites use the shared `assetOptions` constant, so both are caught
/// by `AVURLAssetPreciseTimingTests` too. We assert count **== 2** here
/// to preserve the brittle-by-design intent: any third site appearing in
/// `PlayerEngine.swift` fails this test and forces a deliberate conversation
/// (either reuse the helper, or document a new third site here).
///
/// Resolution of the "exactly 1" open question is logged in card 0006a's
/// plan and flagged to the manager in the engineer's Self-Audit step 7.
final class PlayerEngineAVURLAssetCountTests: XCTestCase {

    func testPlayerEngineHasExactlyTwoAVURLAssetSites() throws {
        guard let sourceDir = RepoRoot.jamBoxSourceDir() else { return }
        let file = sourceDir.appendingPathComponent("PlayerEngine.swift")
        let src = try String(contentsOf: file, encoding: .utf8)

        // Count standalone `AVURLAsset(` tokens (not preceded by an identifier
        // character, to avoid e.g. `FooAVURLAsset(` false positives).
        let chars = Array(src)
        var count = 0
        var locations: [Int] = []
        let needle = Array("AVURLAsset(")
        var i = 0
        while i + needle.count <= chars.count {
            var match = true
            for k in 0..<needle.count where chars[i + k] != needle[k] {
                match = false; break
            }
            if match {
                let ok: Bool
                if i == 0 {
                    ok = true
                } else {
                    let prev = chars[i - 1]
                    ok = !(prev.isLetter || prev.isNumber || prev == "_")
                }
                if ok {
                    count += 1
                    // Compute 1-based line number
                    var line = 1
                    for k in 0..<i where chars[k] == "\n" { line += 1 }
                    locations.append(line)
                    i += needle.count
                    continue
                }
            }
            i += 1
        }

        XCTAssertEqual(
            count, 2,
            "PlayerEngine.swift should contain exactly 2 `AVURLAsset(` construction " +
            "sites (makeAssetItem for playback + findArtwork for embedded artwork). " +
            "Found \(count) at lines \(locations). If you added a third site, either " +
            "route it through `makeAssetItem` or update this test with a comment " +
            "explaining the new site. See card 0006a and card 0012."
        )
    }
}
