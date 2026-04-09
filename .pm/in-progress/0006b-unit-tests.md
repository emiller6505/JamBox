---
id: 0006b
title: Layer 2 unit tests — Track, FileScanner, ThemeManager, formatters
created: 2026-04-08
needs_designer: false
designer: null
design_review: null
engineer: null
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
*Filled in by the engineer during plan mode.*

## Log
- 2026-04-08 — manager created card in backlog/, depends on 0006a

## Self-Audit

## QA Report

## Manager Decision
