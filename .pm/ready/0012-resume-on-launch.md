---
id: 0012
title: Resume playback position on launch
created: 2026-04-08
needs_designer: true
designer: null
design_review: null
engineer: null
qa: null
parent: null
priority: P2
estimate: S
depends_on: []
touches:
  - JamBox/PlayerEngine.swift
  - JamBox/AppModel.swift
  - JamBox/ContentView.swift
acceptance:
  - On app quit, JamBox saves the currently-playing track's URL and the live playback position. If nothing is playing, it saves nothing (or clears any prior saved state).
  - During playback, the saved position is updated on a throttled timer (~5s cadence) so a hard crash doesn't lose more than a few seconds of progress.
  - On next launch, after the folder bookmark is restored and tracks are loaded, JamBox locates the saved track by URL inside the restored folder, builds an `AVPlayerItem` via the existing `assetOptions` (preserving §7.1), seeks to the saved position, and presents the now-playing bar populated — but playback stays PAUSED.
  - One press of space (or click of the play button) resumes from the saved position. The first transition into the next track after resume is gapless (the lookahead must be filled before the user presses play).
  - Saved track no longer exists at relaunch (file deleted, folder bookmark stale, file outside the restored folder, etc.) → silent clear of the saved state. No error modal, no log spam. App opens in its normal first-launch state.
  - Saved position exceeds the asset's actual duration (file was re-encoded shorter between sessions) → clamp to `[0, duration]`. Trust the asset's async-loaded duration over the saved value.
  - The restored track's metadata is the cheap `init(url:)` form initially; when `updateMetadata` lands the enriched metadata, the swap happens in-place without disrupting the already-queued `AVPlayerItem` (verify §7.3 still holds for this code path).
  - No new `AVURLAsset` construction site introduced. The resume code path goes through `Self.assetOptions` (extract a private helper if tempted to duplicate).
  - All `startAccessingSecurityScopedResource` calls remain balanced with `stopAccessingSecurityScopedResource` (§7.4). The resume path uses the existing folder bookmark — no new per-track bookmark.
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - §7.1 AVURLAsset preserved
  - §7.2 Gapless playback preserved (verify by ear: resume, press play, listen for the first track→next transition)
  - §7.3 Two-phase loading preserved
  - §7.4 Sandbox bookmarks balanced
---

## Context

User picked this from a designer brainstorm of new feature ideas (2026-04-08). The two-card slate (0012 + 0013) is "this app respects my time and tells me what I need to know" — quiet, considerate UX that signals JamBox is for users who care.

User quote (designer brainstorm): *"I was 45 minutes into a 70-minute mix, closed my laptop, opened it three days later — I want it to remember."*

The engineer's selection memo flagged this as the lowest-risk way to get high-leverage user value: every seam already exists. `PlayerEngine.play(startingAt:)` is the single asset-construction site (uses `assetOptions` with `AVURLAssetPreferPreciseDurationAndTimingKey`). `Track.id` is the URL. The folder bookmark already lives in `AppModel`. `PlaybackClock` already publishes position. The resume path is a tiny variation: build the item, insert into queue, `seek(to:)`, but do NOT call `play()` so `timeControlStatus` stays `.paused` and the existing KVO sink reflects that.

This card is a sibling to card 0013 (format badge + NowPlayingBar UX pass). Both touch `PlayerEngine.swift` so they cannot be in-progress simultaneously (§8). Manager has serialized: 0012 first, then 0013.

## Design
*Filled in by the designer BEFORE engineering starts. See .pm/README.md §4b.*

## User Risks & Edge Cases
*Filled in by the designer BEFORE engineering starts. See .pm/README.md §4b step 5.*

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

## Log
- 2026-04-08 — manager card created in ready/, sibling to 0013, will dispatch designer next

## Self-Audit
*Filled in by the engineer before handing off to QA. See .pm/README.md §6.*

1. Re-read modified files:
2. Acceptance walkthrough:
3. Build result:
4. Invariants verified:
5. Hostile diff review:
6. Touched-files reconciliation:
7. Scope check:

## QA Report
*Filled in by the QA agent. See .pm/README.md §6b.*

### Acceptance

### Invariants

### Findings

### Recommendation

## Design Review
*Filled in by the designer AFTER QA approves. See .pm/README.md §6c.*

### Original risks revisited

### Newly surfaced concerns

### Recommendation

## Manager Decision
*Filled in by the manager when closing or kicking back.*
