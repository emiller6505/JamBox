---
id: 0013
title: Format/sample-rate/bit-depth badge in NowPlayingBar + UX pass
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
  - JamBox/NowPlayingBar.swift
  - JamBox/PlayerEngine.swift
  - JamBox/Track.swift
acceptance:
  - When a track is playing, the NowPlayingBar shows a small caption with the audio format (FLAC / ALAC / MP3 / AAC / WAV / AIFF), the sample rate (e.g. "96 kHz"), and the bit depth (e.g. "24 bit") for the current track. Format names follow the designer's spec.
  - The badge is fetched from the existing `AVPlayerItem.asset` (no new `AVURLAsset` construction), and only when the current item changes — not on every scrub tick.
  - Format info is published as a separate `@Published` on `PlayerEngine` (not on `PlaybackClock`), so the 4Hz clock observer does not cause re-renders or refetches. The `PlayerEngine` / `PlaybackClock` split documented at PlayerEngine.swift:20 must be preserved.
  - If any of {format, sample rate, bit depth} is unknown, missing, or zero, the badge is hidden entirely. Never show "0 kHz", "Unknown", or "—".
  - The badge has a VoiceOver label that reads the values in long form ("FLAC, 96 kilohertz, 24 bit"), distinct from the visual compact form.
  - **UX pass on the NowPlayingBar:** since this card adds new information to the metadata column, the designer must do a layout/legibility review of the entire NowPlayingBar and apply a slight font size increase across the bar so the bar is not crowded and remains easily legible. The font size increase must be specified by the designer (with values referenced from `Theme.swift` tokens where possible). The new badge and the existing title/artist/album lines must all coexist comfortably without pushing the transport controls.
  - The UX pass must verify legibility at the smallest reasonable window width (down to the existing minWidth: 500 from ContentView.swift:285), at all three themes, and with the album art thumbnail visible.
  - No regressions to existing NowPlayingBar behavior: scrub bar drag-decouple, clickable artwork thumbnail, transport controls, scroll-to-current-track callback, and the elapsed/total time display all still work.
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - §7.1 AVURLAsset preserved (no new asset construction; reuse `currentItem.asset`)
  - §7.2 Gapless playback preserved (no changes to queue management)
  - §7.3 Two-phase loading preserved (format fetch is per current item, not part of bulk scan)
---

## Context

User picked this from a designer brainstorm of new feature ideas (2026-04-08), as the second of two sibling cards (0012 + 0013). User quote (designer brainstorm): *"I spent money on this 24/96 FLAC rip. I want to see, at a glance, that the player is actually playing it and not something stepped down."*

This is the Audirvana lossless-badge feature — the single thing audiophiles point to as a reason to pay for that app. Daily reassurance feature, identity signaling for the Foobar2000/Audirvana audience. Engineer's selection memo: lowest-risk idea on the brainstorm list.

User added one acceptance bullet beyond the engineer's original scope: a UX pass on the NowPlayingBar with a slight font-size increase across the whole bar, since the new badge adds information to an already busy metadata column and we want the bar to stay uncluttered and legible.

This card is a sibling to card 0012 (resume on launch). Both touch `PlayerEngine.swift` so they cannot be in-progress simultaneously (§8). Manager has serialized: 0012 first, then 0013.

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
- 2026-04-08 — manager card created in ready/, sibling to 0012, will dispatch designer next

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
