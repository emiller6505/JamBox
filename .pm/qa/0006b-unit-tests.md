---
id: 0006b
title: Layer 2 unit tests — Track, FileScanner, ThemeManager, formatters
created: 2026-04-08
needs_designer: false
designer: null
design_review: null
engineer: opus-4.6
qa: null
parent: 0006
priority: P1
estimate: M
depends_on: [0006a]
touches:
  - JamBoxTests/Unit/
  - JamBox.xcodeproj/project.pbxproj
acceptance:
  - `Track.init(url:)` produces correct `displayName` from filename without extension. Tested with at least one file with multiple dots, one Unicode filename, one filename with no extension.
  - `Track.loadMetadata` parses ID3 tags correctly from the mp3 fixture (0006a). Verifies title, artist, album, track number against known values.
  - `Track.loadMetadata` parses Vorbis comments correctly from the 16-bit FLAC fixture (0006a). REGRESSION TEST for the AVFoundation-commonMetadata-empty-for-FLAC bug — verifies title/artist/album come from `vorb/TITLE` etc., not from `commonMetadata`.
  - `Track.loadMetadata` parses iTunes-style tags from the m4a fixture (0006a).
  - `Track.loadMetadata` returns sensible defaults when metadata is missing (verify with a fixture that has no tags, or mock).
  - `FileScanner.scanFolder` returns only files with supported extensions (mp3, m4a, flac, aiff, aif, wav, alac, aac), filters out non-audio (use a temp directory with mixed file types).
  - `FileScanner.scanFolder` returns files in a stable order (run twice, assert equal).
  - `ThemeManager` persistence: set theme, recreate manager, verify theme restored.
  - Duration formatting helpers (mm:ss, h:mm:ss boundaries) — test 0s, 59s, 60s, 3599s, 3600s.
  - `Track.trackNumberString` formatting — test nil, 0, 1, 99, 100.
  - All tests pass via `xcodebuild test`. No fixture regeneration needed (uses what 0006a committed).
  - Build green, no new warnings.
  - §7 invariants preserved.
---

## Context

Second of four cards split from 0006. Depends on 0006a's test target and fixtures. Pure unit tests against model code — no AVFoundation against the real playback pipeline. Should run in milliseconds total.

Engineer should NOT touch production code in this card unless an `internal` accessor is needed for testability. Scope check is critical: this card is about exercising existing behavior, not changing it.

## Plan

### Approach

Pure unit tests. No production code changes. All tests go into `JamBoxTests/Unit/` to parallel the existing `JamBoxTests/StaticChecks/` directory. Use `@testable import JamBox` for access to `FileScanner`, `Track`, `Theme`, `ThemeManager`.

**Fixture loading.** Fixtures are already in the JamBoxTests bundle resources phase (verified in `JamBox.xcodeproj/project.pbxproj`). Use `Bundle(for: type(of: self)).url(forResource:withExtension:)`. A dedicated `FixtureLoader` helper and a first smoke test will verify bundle presence before the rest of the file suite runs.

**Fixture tag values** (from `Fixtures/generate.sh`):
- TITLE = "JamBox Test Tone"
- ARTIST = "JamBox Test Suite"
- ALBUM = "Fixture Album"
- TRACK = 3

**Test files:**

1. `Unit/FixtureLoaderTests.swift` — smoke test: every fixture url resolves and file exists. This is the "verify bundle works before writing everything else" step.
2. `Unit/TrackDisplayNameTests.swift` — synchronous init(url:) coverage:
   - `song.mp3` → `song`
   - `a.b.c.flac` → `a.b.c` (multi-dot)
   - `café – 歌.m4a` → `café – 歌` (Unicode)
   - `README` (no extension) → `README`
3. `Unit/TrackMetadataTests.swift` — async `Track.loadMetadata` against fixtures:
   - mp3 (ID3): title/artist/album/track=3
   - tone-16.flac (Vorbis) — **regression test**. Asserts title/artist/album are populated, i.e. the vorbis fallback path runs. Adds an explicit comment linking to the commonMetadata bug.
   - m4a (iTunes): title/artist/album/track=3
   - "missing tags" case: copy `tone.wav` (PCM, no tags) to a temp url and load — expect title defaults to filename (derived from url), artist/album empty, trackNumber nil. `tone.wav`'s generator uses `-map_metadata -1` so it has no tags.
4. `Unit/FileScannerTests.swift`:
   - Filtering: create temp dir with `a.mp3`, `b.flac`, `c.m4a`, `d.aiff`, `e.wav`, `f.aif`, `g.aac`, `h.alac` (all empty files; scanner only inspects extensions) + `readme.txt`, `cover.jpg`, `.hidden.mp3`. Assert only the 8 supported extensions appear.
   - Stable order: scan twice, assertEqual.
   - Teardown removes the temp dir.
5. `Unit/ThemeManagerTests.swift`:
   - `ThemeManager` uses `@AppStorage("theme")` against `UserDefaults.standard`. Strategy: save the pre-test value of `UserDefaults.standard.object(forKey: "theme")`, run the test (set `.dark`, recreate manager, assert `.dark`; set `.candy`, recreate, assert `.candy`; set `.light`, recreate, assert `.light`), restore original value in tearDown. The spec notes `UserDefaults(suiteName:)` to avoid polluting the user's prefs — but `@AppStorage` without an explicit `.standard` override always hits `.standard`. Alternative: wrap pre-test snapshot + tearDown restore. This is safe and gives true round-trip coverage of the actual production class. Go with snapshot+restore.
6. `Unit/FormattersTests.swift`:
   - `Track.durationString` at 0s → "0:00", 59s → "0:59", 60s → "1:00", 3599s → "59:59", 3600s → "60:00". NOTE: the current `durationString` is mm:ss only (no h:mm:ss). The acceptance bullet says "mm:ss, h:mm:ss boundaries" — assert actual behavior (which produces "60:00" at 3600s since implementation uses `total/60` without hour break). Flag in self-audit that this is by-design-of-current-code; if hour formatting is desired, it's out of scope for 0006b.
   - `Track.trackNumberString` for nil → "", 0 → "0", 1 → "1", 99 → "99", 100 → "100".

### Files (new, all under `JamBoxTests/Unit/`)
- `FixtureLoader.swift`
- `FixtureLoaderTests.swift`
- `TrackDisplayNameTests.swift`
- `TrackMetadataTests.swift`
- `FileScannerTests.swift`
- `ThemeManagerTests.swift`
- `FormattersTests.swift`

Also: `xcodegen generate` to regenerate project (new source files under JamBoxTests/).

### Risks
- **`@AppStorage` and UserDefaults pollution.** Mitigated by snapshot+restore in setUp/tearDown. If tests are interrupted mid-run, user's theme pref could be momentarily set to something else — the scope is "theme" key only, cost is trivially low.
- **Track.loadMetadata against m4a track number.** The m4a fixture was written with `-metadata track="3"` via ffmpeg, which typically writes the iTunes `trkn` atom. The current loader reads via `.iTunesMetadataTrackNumber`. Should work; if it doesn't, assert a loose check (trackNumber != nil) and file a follow-up. Plan: assert exact == 3, fall back to documenting if it fails.
- **FLAC fixture has NO common title.** AVFoundation returns empty commonMetadata for FLAC. The vorb/TITLE fallback is the regression test — assert title == "JamBox Test Tone".
- **The "missing tags" fixture.** `tone.wav` was generated with `-map_metadata -1`. Track.loadMetadata should return displayName = filename fallback, artist/album empty. Verify.

### Open questions
- None blocking. Will document any runtime surprises in self-audit.

## Log
- 2026-04-08 — manager created card in backlog/, depends on 0006a
- 2026-04-08 — engineer claimed, → in-progress
- 2026-04-08 — plan written
- 2026-04-08 — impl complete, 34 tests pass in 0.192s, build green, → qa

## Self-Audit

### Step 1 — Re-read all modified files top to bottom
Re-read every new file under `JamBoxTests/Unit/`. No dead code, no debug prints, no commented-out blocks, no TODO/FIXME. Every helper is used. Every test body has a clear assertion.

### Step 2 — Walk every acceptance bullet

- **`Track.init(url:)` displayName multi-dot / Unicode / no-extension** — PASS. `TrackDisplayNameTests.swift:13` (plain), `:18` (`a.b.c.flac` → `a.b.c`), `:23` (`café – 歌.m4a`), `:29` (`README` no-ext), `:35` (empty defaults).
- **`Track.loadMetadata` ID3 from mp3** — PASS. `TrackMetadataTests.swift:22` asserts title/artist/album/trackNumber=3 against `tone.mp3`.
- **`Track.loadMetadata` Vorbis from 16-bit FLAC (REGRESSION)** — PASS. `TrackMetadataTests.swift:38` explicitly asserts the `vorb/TITLE`-fallback-path produces `"JamBox Test Tone"` against `tone-16.flac`, with a comment tying it to the commonMetadata-empty-for-FLAC bug.
- **`Track.loadMetadata` iTunes from m4a** — PASS (partial, documented). `TrackMetadataTests.swift:58` asserts title/artist/album against `tone.m4a`. trackNumber is NOT asserted here because ffmpeg's m4a muxer writes an empty `trkn` atom even when given `-metadata track="3"` — AVFoundation surfaces `itsk/trkn` with both `stringValue` and `numberValue` nil. Documented inline in the test. The ID3 path already covers trackNumber extraction, so production code has coverage. Non-blocking — if this is a concern, follow-up card should switch `generate.sh` to AtomicParsley / MP4Box for the m4a fixture.
- **`Track.loadMetadata` defaults when missing** — PASS. `TrackMetadataTests.swift:74` copies `tone.wav` (generated with `-map_metadata -1`) to a temp dir with a known filename and asserts displayName falls back to filename, artist/album empty, trackNumber nil, duration still extracted.
- **`FileScanner.scanFolder` filtering** — PASS. `FileScannerTests.swift:37` creates a temp dir with all 8 supported extensions plus txt/jpg/md/zip/no-suffix distractors, asserts the returned set equals exactly the 8 audio files. `FileScannerTests.swift:63` also exercises case-insensitivity.
- **`FileScanner.scanFolder` stable order** — PASS. `FileScannerTests.swift:71` scans twice and asserts equal.
- **`ThemeManager` round-trip** — PASS. `ThemeManagerTests.swift:35` dark, `:42` candy, `:48` all themes via `Theme.allCases`. `:57` also covers fallback from invalid stored value. setUp/tearDown snapshot and restore `UserDefaults.standard["theme"]` so the user's pref isn't polluted.
- **Duration formatting (0/59/60/3599/3600)** — PASS. `FormattersTests.swift:19-42`. NOTE: current `Track.durationString` is mm:ss only; 3600s formats as `"60:00"` not `"1:00:00"`. Tests lock in current behavior with a comment flagging that a proper h:mm:ss break is a future card.
- **`trackNumberString` (nil/0/1/99/100)** — PASS. `FormattersTests.swift:61-77`.
- **All tests pass via xcodebuild test** — PASS. Final run: 34 tests total, 0 failures, **0.192s** execution. Paste below.
- **Build green, no new warnings** — PASS. `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` → `** BUILD SUCCEEDED **`, no compiler warnings (only standard `xcodebuild: WARNING: Using the first of multiple matching destinations`, which is infrastructural and pre-existing).
- **§7 invariants preserved** — PASS. See step 4.

### Step 3 — Build / test status

```
xcodebuild -project JamBox.xcodeproj -scheme JamBox -destination 'platform=macOS' test
…
Test Suite 'All tests' passed at 2026-04-09 10:10:01.033.
     Executed 34 tests, with 0 failures (0 unexpected) in 0.192 (0.239) seconds
** TEST SUCCEEDED **
```

```
xcodebuild -project JamBox.xcodeproj -scheme JamBox build
…
** BUILD SUCCEEDED **
```

### Step 4 — §7 invariants

1. **AVURLAsset precise timing** — N/A to new code. `Track.loadMetadata` (unchanged) is the only AVURLAsset construction exercised, and its call site already uses `assetOptions` dictionary. Layer 1 static check (`AVURLAssetPreciseTimingTests`) still passes on the full `JamBox/` tree after this card.
2. **Gapless playback** — N/A. No `PlayerEngine.swift` touched. Verified: `git diff main -- JamBox/PlayerEngine.swift` is empty.
3. **Two-phase loading** — N/A to new code. Tests exercise both phases independently: `TrackDisplayNameTests` hits the fast synchronous path, `TrackMetadataTests` hits the async enrichment path.
4. **Sandbox bookmarks** — N/A. No `startAccessingSecurityScopedResource` usage in new code. Layer 1 static balance check still passes.
5. **Xcodegen regeneration** — PASS. Ran `xcodegen generate`, committed the regenerated `project.pbxproj` alongside the new test files. Diff verified purely additive (7 new file refs + 7 build file entries + one new `Unit` group).
6. **Build green** — PASS. See step 3.

### Step 5 — Hostile diff review

- `TrackMetadataTests.testITunesFromM4A` does NOT assert trackNumber. A reviewer will flag this. The inline doc-comment pre-empts that — it's a fixture limitation, not a loader gap, and the ID3 path already exercises trackNumber extraction in `testID3FromMP3`. Acceptable but flagging explicitly.
- `FormattersTests.testDurationExactlyOneHour` asserts `"60:00"` not `"1:00:00"`. Reviewer might expect h:mm:ss. This is current implementation behavior (see `Track.swift:14-18`); the acceptance bullet says "mm:ss, h:mm:ss boundaries" but the impl doesn't do h:mm:ss break. Test locks in current behavior with a comment flagging future work — matches "exercising existing behavior, not changing it" from the card's context section.
- `ThemeManagerTests` touches `UserDefaults.standard`. setUp/tearDown snapshot/restore makes this safe for normal runs; if a run is killed mid-test (ctrl-C between setUp and tearDown) the user's theme pref could momentarily be cleared. The scope is a single key and the risk window is <10ms; acceptable trade-off versus the complexity of abstracting `@AppStorage` storage.
- `FileScannerTests` uses `Data().write(to:)` for empty files. Scanner only looks at extensions, so this is correct and intentional.
- `FixtureLoader` uses a private anchor class `FixtureLoaderAnchor: NSObject` purely as an NSObject subclass anchor for `Bundle(for:)`. Slightly unusual but self-documenting.

### Step 6 — Touched-files reconciliation

Frontmatter originally listed `JamBoxTests/`, `JamBox/Track.swift`, `JamBox/FileScanner.swift`. Actual touches: `JamBoxTests/Unit/` (7 new files) + `JamBox.xcodeproj/project.pbxproj` (regeneration). **No production Swift files touched** — frontmatter updated to reflect reality. This is actually better than the original plan: the card context said "Engineer should NOT touch production code" and I succeeded.

### Step 7 — Scope check

No out-of-scope changes. All edits are inside `JamBoxTests/Unit/` plus the inevitable xcodeproj regeneration. Did not touch `PlayerEngine.swift` (0006c scope). Did not add XCUITests (0006d scope). Did not refactor `Track.swift` / `FileScanner.swift` / `Theme.swift` despite noting behaviors that could be improved — flagged in comments as future work instead.

## QA Report

## Manager Decision
