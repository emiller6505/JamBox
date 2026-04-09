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
  - JamBoxTests/
  - JamBox/Track.swift
  - JamBox/FileScanner.swift
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

## Self-Audit

## QA Report

## Manager Decision
