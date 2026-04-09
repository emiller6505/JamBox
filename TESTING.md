# Testing

JamBox's automated test suite lives in `JamBoxTests/` and runs via `xcodebuild test`. This document explains how to run the suite, what's currently in it, and how to add more.

## How to run

From the repo root:

```bash
xcodebuild -project JamBox.xcodeproj -scheme JamBox -destination 'platform=macOS' test
```

No extra setup. A clean checkout plus a working Xcode install is enough. If the project file is stale, run `xcodegen generate` first.

## Framework choice — XCTest

This project uses **XCTest**, not Swift Testing.

Rationale: the Layer 1 static checks (see below) are the highest-value tests in the suite, and they are text-scanning assertions with narrative error messages ("found `AVURLAsset(...)` in `Foo.swift:42` without precise-timing-key"). XCTest gives those failures richer, more locatable output than Swift Testing's `#expect` macro, which tends to render as a boolean. XCTest also has the lowest cognitive-overhead baseline: every future engineer on this repo has already seen it. Swift Testing's strengths (parameterized data-driven tests, trait composition) aren't needed for the current suite.

If Layer 3 integration tests ever grow a lot of parameterized data rows, revisit.

## Layout

```
JamBoxTests/
├── JamBoxTests.swift                  placeholder sanity baseline
├── Fixtures/                          audio fixtures used by Layer 2+3 tests
│   ├── generate.sh                    reproducible regeneration script
│   ├── tone.mp3                       ID3-tagged 1-2s tone
│   ├── tone.m4a                       iTunes-tagged 1-2s AAC tone
│   ├── tone-16.flac                   16-bit FLAC w/ vorb/TITLE etc.
│   ├── tone-24.flac                   24-bit FLAC (card 0020 regression fixture)
│   ├── tone.wav                       LPCM 1-2s tone
│   └── tone.aiff                      LPCM 1-2s tone
└── StaticChecks/
    ├── RepoRoot.swift                 path-resolver helper
    ├── AVURLAssetPreciseTimingTests.swift
    ├── SandboxBookmarkBalanceTests.swift
    ├── PlayerEnginePublishedAllowlistTests.swift
    └── PlayerEngineAVURLAssetCountTests.swift
```

## Fixtures

Every fixture is small (<100 KB) and deterministic. They all encode a 1-2 second low-amplitude sine tone with known title/artist/album/track metadata.

To regenerate from scratch:

```bash
cd JamBoxTests/Fixtures
./generate.sh
```

The script uses `ffmpeg`, `flac`, and `afconvert`. Install `ffmpeg` and `flac` via Homebrew if you don't have them (`afconvert` ships with macOS). The script overwrites existing fixtures; commit the results. If you need to add a new fixture, edit `generate.sh` first — the script is the source of truth, not the committed binaries.

## Layer 1 — static checks

Layer 1 tests don't run production code. They read `JamBox/*.swift` as plain text and assert structural invariants. They're the cheapest, most mechanical regression defenses we ship.

### `AVURLAssetPreciseTimingTests`

Scans every `.swift` file under `JamBox/` for `AVURLAsset(` constructor calls and fails if any construction omits `AVURLAssetPreferPreciseDurationAndTimingKey` (either inline or via the `assetOptions` constant). **Defends the README §7.1 / `CLAUDE.md` "Critical: AVURLAsset Options" contract.** Without this option, FLAC files with inaccurate STREAMINFO headers play 2-5 seconds past their stated end and emit `FigFilePlayer err=-12864`. We shipped this bug once; the test makes sure we can't ship it again. Traces back to the original FLAC precise-duration incident.

### `SandboxBookmarkBalanceTests`

Counts occurrences of `startAccessingSecurityScopedResource(` and `stopAccessingSecurityScopedResource(` across `JamBox/*.swift` and asserts the counts are equal. This is a v1 approximation — it does not prove per-flow pairing, only that we haven't shipped an obvious imbalance. **Defends §7.4** (security-scoped bookmark lifecycle). Unbalanced calls can leak scoped grants and cause mysterious permission denials in long-running sessions.

### `PlayerEnginePublishedAllowlistTests`

Greps `JamBox/PlayerEngine.swift` for `@Published var <name>` declarations inside the `PlayerEngine` class (skipping the `PlaybackClock` helper) and asserts the set of names equals a hand-maintained allowlist. Any addition or rename forces the allowlist to be updated in the same PR. **Defends card 0002's click-race bug**, which was caused by `objectWillChange` firing for every `@Published` write. Brittle by design: the brittleness is the point.

If you add a new `@Published` to `PlayerEngine`, update `PlayerEnginePublishedAllowlistTests.allowlist` and explain the addition in the commit message.

### `PlayerEngineAVURLAssetCountTests`

Counts `AVURLAsset(` construction sites in `JamBox/PlayerEngine.swift` and asserts the count is **exactly 2**: `makeAssetItem(for:)` (the playback queue helper from card 0012) and `findArtwork(for:)` (the embedded-artwork probe). **Defends card 0012's `makeAssetItem` extraction** and, by proxy, §7.1. Any third site appearing in `PlayerEngine.swift` fails this test and forces a deliberate conversation: either reuse the helper, or update this test with a comment explaining the new site. (Card 0006a originally called for "exactly 1"; the card's assumption was wrong about `findArtwork` living in a different file. The count is 2 in reality; the intent — brittle-by-design alarm on new sites — is preserved.)

## Adding a new fixture

1. Edit `JamBoxTests/Fixtures/generate.sh` to produce the new file. Keep it under 100 KB. Use explicit `-metadata` flags and `-map_metadata -1` for determinism.
2. Run `./generate.sh` locally.
3. Verify the new file is deterministic by running the script twice and diffing.
4. Commit both the script update and the binary.

## Runtime budget

Individual tests should finish in well under 1 second. If a single test takes > 5 seconds, add a comment explaining why. The Layer 1 suite today runs in well under 100 ms total; the long pole is the per-run build cost, not the tests themselves.
