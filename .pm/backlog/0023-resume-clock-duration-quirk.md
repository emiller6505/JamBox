---
id: 0023
title: PlayerEngine.resume — write real clock.duration even when re-seek is short-circuited
created: 2026-04-09
needs_designer: false
designer: null
design_review: null
engineer: null
qa: null
parent: 0006c
priority: P3
estimate: S
depends_on: []
touches:
  - JamBox/PlayerEngine.swift
acceptance:
  - In `PlayerEngine.resume(trackIndex:position:onFailure:)`, when the async asset.load(.duration) completes AND the clamped position is within epsilon of the sanitized position (so the existing re-seek branch is short-circuited), the code still writes `self.clock.duration = realDurationSeconds` unconditionally so the published clock state matches the loaded asset.
  - After resume completes (without the user pressing play), `engine.clock.duration` reflects the real asset duration, not 0.
  - The 0006c integration test `AppModelResumeIntegrationTests.testResumeRestoresTrackAndPositionPaused` can be simplified to read `engine.clock.duration` directly instead of using the `MaxBox` workaround. (Optional cleanup; not strictly required by the card.)
  - All existing tests still pass after the fix. Run `xcodebuild test` 3 times to confirm no new flakiness.
  - §7.1 / §7.2 / §7.3 / §7.4 / §7.6 preserved.
---

## Context

Filed as a child of card 0006c (integration tests) by manager-decision on 2026-04-09. The 0006c engineer discovered this while debugging flaky resume tests:

In failing test runs, the captured `clock.duration` value sequence was `[0.0, 0.0, 0.0, 1.0, 0.0]`. The async `asset.load(.duration)` step in `PlayerEngine.resume` correctly writes the real value (1.0), but `handleItemChange` (KVO-dispatched on currentItem changes) re-zeros it because it copies from `tracks[currentIndex].duration` which is 0 for cheap-init `Track(url:)` instances. The async clamp step then short-circuits its re-write because `abs(clamped - sanitized) <= 0.01` (the user's saved position was already inside the duration), so nothing ever writes the real duration back.

The final settled state for the in-range resume + still-paused path is genuinely `clock.duration == 0` until the user presses play. Pressing play kicks the periodic time observer which writes `currentItem.duration` and the user never sees the intermediate zero. **No real user has ever observed this bug** — but it's a quirk that exists, and it forced a workaround in the integration tests (the `MaxBox` capture-the-max pattern in `AppModelResumeIntegrationTests`).

The fix is one line in `PlayerEngine.resume`'s async block: unconditionally write `self.clock.duration = realDurationSeconds` even when the re-seek branch is short-circuited. The full async block already runs on MainActor so there's no concurrency surprise.

P3 because no user impact and the test workaround is in place. Worth fixing because the workaround is ugly and obscures the test's intent.

## Plan
*Filled in by the engineer during plan mode.*

## Log
- 2026-04-09 — manager filed as child card from 0006c approval

## Self-Audit

## QA Report

## Manager Decision
