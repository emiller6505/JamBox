---
id: 0006c
title: Layer 3a integration tests — PlayerEngine against real fixture audio
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
  - JamBox/PlayerEngine.swift
acceptance:
  - `PlayerEngine.play(startingAt:)` on a freshly-loaded fixture track starts playback within a reasonable timeout (e.g. 2 seconds). Verifies `isPlaying` flips to true, `currentTrack` is set, `clock.duration > 0`.
  - **REGRESSION TEST for §7.2 gapless lookahead.** Load 5 fixture tracks. Call `play(startingAt: 0)`. Inspect `queuePlayer.items().count` — must be exactly the lookahead count (3) or fewer if the queue end is near. Assert.
  - `PlayerEngine` advances from one track to the next on natural end-of-track. Use a 1-2 second fixture, play, wait for the natural advance, assert `currentTrack` updated.
  - `PlayerEngine` pause/resume preserves position. Play, wait 0.5s, pause, capture position, wait 0.5s, resume, verify position resumed within 0.1s of saved.
  - `PlayerEngine.seek(to:)` to a known offset works and updates `clock.position` correctly.
  - **REGRESSION TEST for §7.1 — FLAC duration.** Load the 24-bit FLAC fixture (0006a) and verify `clock.duration` matches the fixture's actual duration within 0.1 seconds. This is the regression coverage for the original FLAC duration bug — without `AVURLAssetPreferPreciseDurationAndTimingKey`, this assertion would fail.
  - **REGRESSION TEST for card 0020 — FLAC bit-depth fallback.** Load the 24-bit FLAC fixture, wait for `currentFormat` to populate, assert `currentFormat?.bitDepth == 24`. Without the STREAMINFO parser fallback shipped in card 0020, this would fail.
  - **REGRESSION TEST for card 0012 — resume mechanism.** Save state to UserDefaults manually, recreate AppModel, verify resume restores the track loaded but paused, with the right scrub position.
  - All tests pass via `xcodebuild test`.
  - Test runtime documented; integration tests are slower than unit tests but should still total under 30 seconds.
  - Build green, no new warnings.
  - §7 invariants preserved.
---

## Context

Third of four cards split from 0006. Depends on 0006a's test target and fixtures. Tests use real `AVFoundation` against the fixture audio files committed by 0006a. Slower than unit tests but the only way to catch regressions in the playback pipeline.

The two new regression tests for cards 0012 and 0020 are explicitly required because both of those cards shipped bugs to users that real-file integration testing would have caught.

## Plan
*Filled in by the engineer during plan mode.*

## Log
- 2026-04-08 — manager created card in backlog/, depends on 0006a

## Self-Audit

## QA Report

## Manager Decision
