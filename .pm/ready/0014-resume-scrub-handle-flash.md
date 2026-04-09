---
id: 0014
title: Eliminate scrub-handle flash during resume duration-load window
created: 2026-04-08
needs_designer: true
designer: null
design_review: null
engineer: null
qa: null
parent: 0012
priority: P3
estimate: S
depends_on: []
touches:
  - JamBox/AppModel.swift
  - JamBox/PlayerEngine.swift
acceptance:
  - On launch with a saved resume state, the scrub bar handle renders at the correct fractional position on the very first frame the now-playing bar appears. No visible "handle at left edge" period while the asset's real duration loads asynchronously.
  - `PlaybackState` schema is bumped to version 2 and includes a `duration: TimeInterval` field alongside `trackURL` and `position`. Version 1 payloads are treated as "no saved state" (silent clear) per the existing version-mismatch behavior.
  - `PlayerEngine.resume(...)` seeds `clock.duration` synchronously from the caller-supplied saved duration before returning. The async duration-load Task continues to overwrite with the precise value once the asset is parsed, and clamps `position` against it.
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - §7.1 AVURLAsset preserved (no new construction sites)
  - §7.3 Two-phase loading preserved
---

## Context

Spawned by the §6c design review of card 0012 (resume playback position on launch). Parent card's designer guardrail was explicit: *"Do NOT start the scrub bar at 0 and then jump to the saved position after the seek completes. Seed `clock.position` synchronously to the saved value at the same moment the item is inserted."* The implementation obeys this for `clock.position` but not for `clock.duration` — the cheap `init(url:)` Track has `duration = 0`, so `resume` seeds `clock.duration = 0` until the async `asset.load(.duration)` Task lands. `NowPlayingBar.swift:166` reads `guard clock.duration > 0 else { return 0 }`, so the **scrub handle bead renders at the left edge** while the left time label correctly reads e.g. "45:01" and the right reads "0:00". Visually inconsistent for the duration-load window (typically <10ms for a local FLAC, but potentially hundreds of ms on a slow disk or iCloud placeholder).

The fix is to persist `duration` in `PlaybackState` so the engine can seed it synchronously. The async Task keeps running — it's still the source of truth — but the UI never shows a half-loaded state.

## Design
*Fill in: no visual change in steady state. The only user-visible delta is the absence of a transient visual glitch on resume. The change is to UX correctness during a narrow window that is usually imperceptible but occasionally visible on slow storage.*

## User Risks & Edge Cases
*Fill in. Key categories: what happens if the persisted duration doesn't match the real one (re-encoded file)? What happens if the persisted duration is NaN/infinite/negative (schema tampering)? What about a v1 payload on a user upgrading across this card?*

## Plan
*Fill in during engineer plan mode.*

## Log
- 2026-04-08 — filed by designer-12-review as a child card of 0012 during post-QA design review

## Self-Audit

## QA Report

## Design Review

## Manager Decision
