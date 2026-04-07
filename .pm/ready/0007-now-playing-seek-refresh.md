---
id: 0007
title: Refresh Now Playing widget elapsed time after in-app seek
created: 2026-04-06
engineer: null
qa: null
parent: 0005
priority: P3
estimate: S
depends_on: [0005]
touches:
  - JamBox/PlayerEngine.swift
  - JamBox/MediaKeyController.swift
acceptance:
  - After dragging the JamBox in-app scrub bar to a new position, the macOS Control Center Now Playing widget's elapsed time updates within ~1 second to reflect the new position
  - No new high-frequency publishers are introduced — the fix must be edge-driven (one update per seek), not periodic
  - Gapless playback is unchanged — no edits to enqueueMoreIfNeeded, lookAhead, or queue management
  - All AVURLAsset construction continues to use AVURLAssetPreferPreciseDurationAndTimingKey: true
  - Build passes cleanly with no new warnings: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
---

## Context

Filed by qa-03 during the audit of card 0005. Card 0005 removed `MediaKeyController`'s 4 Hz `clock.$position` Combine subscription to stop the per-tick republishing of the Now Playing dict (which was shipping a fresh full-resolution `MPMediaItemArtwork` across XPC and causing the ~500 MB sawtooth in idle memory). The fix relies on `MPNowPlayingInfoCenter` interpolating the displayed elapsed time from `MPNowPlayingInfoPropertyElapsedPlaybackTime` + `MPNowPlayingInfoPropertyPlaybackRate`, both of which are still set on every edge update.

The known minor regression: an edge update only fires on `currentTrack` / `isPlaying` / `clock.duration` / `currentArtwork` changes (the four CombineLatest4 inputs in `MediaKeyController.observePlayer`). When the user drags the JamBox in-app scrub bar to a new position, NONE of those four publishers fire — `clock.position` changes, but it isn't observed anymore. Result: the system widget's displayed elapsed time stays stale until the next play/pause toggle or track advance.

This is small but user-visible: glance at Control Center while listening, drag the JamBox slider, the widget keeps showing the old time.

## Suggested approach

Two reasonable shapes:

1. **One-shot from `seek`:** add a single `MediaKeyController.refresh()` (or equivalent) call from `PlayerEngine.seek(to:)` after the underlying `queuePlayer.seek` completes. Cleanest is to expose a `seekDidComplete` notification or a `@Published var seekTick: Int` on `PlayerEngine` that `MediaKeyController` includes in its `CombineLatest`. The "tick" pattern keeps the architecture edge-driven.
2. **Throttled position observer:** re-add a `clock.$position` subscription but `.throttle(for: 1.0)` it. Cheaper than 4 Hz but still steady-state, and re-introduces some of the per-tick allocation. Less preferred.

Option 1 is the right call. It is one update per seek (truly edge-driven), preserves the 4 Hz / 1 Hz / 0 Hz axis at 0 Hz idle, and matches the pattern the rest of the controller already uses.

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits.*

## Log

## Self-Audit

## QA Report

## Manager Decision
