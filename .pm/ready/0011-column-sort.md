---
id: 0011
title: Sort track list by column header (iTunes-style)
created: 2026-04-08
needs_design: false
designer: null
engineer: null
qa: null
parent: null
priority: P2
estimate: M
depends_on: []
touches:
  - JamBox/ContentView.swift
  - JamBox/PlayerEngine.swift
  - JamBox/Track.swift
acceptance:
  - Clicking a sortable column header sorts the visible track list by that column.
  - Clicking the same header again toggles between ascending and descending. The active column shows a sort-direction indicator (SwiftUI Table provides this natively when using `sortOrder`).
  - Sortable columns are Title, Artist, Album, and Duration. The leading speaker-icon column and the "#" track-number column are NOT user-sortable.
  - **Title sort:** plain case-insensitive alphabetical on `displayName`.
  - **Artist sort:** primary key artist (case-insensitive). Within an artist, tracks are grouped by album in case-insensitive album order, and within an album they appear in track-number order. Direction toggle only flips the *artist* axis; album/track order inside each group is always ascending. (This is the iTunes "preserve album order when sorting by artist" behavior.)
  - **Album sort:** primary key album (case-insensitive). Within an album, tracks appear in track-number order. Direction toggle only flips the *album* axis; intra-album track order is always ascending.
  - **Duration sort:** numeric ascending or descending on `duration` (TimeInterval).
  - **Sort drives the playback queue.** When the user sorts and then double-clicks a row, playback proceeds in the visible sorted order, and gapless next-track honors that order. (Decision recorded in Plan: do this by reordering `player.tracks` itself when sort changes, so the existing queue-management code is unchanged.)
  - **Sort + search compose correctly.** Search filtering applies on top of the current sort: the visible rows are the sorted-then-filtered set. Clearing search restores the full sorted list.
  - **Active playback survives a sort change.** If a track is currently playing and the user clicks a column header, the same track keeps playing (no audible glitch, no restart) and the lookahead queue is rebuilt around its new position in `player.tracks`. The existing `updateMetadata` flow (PlayerEngine.swift:147-169) demonstrates the pattern: recompute `currentIndex` by URL match, then `enqueueMoreIfNeeded()`.
  - **Persistence.** The current sort column + direction is persisted to UserDefaults and restored on next launch. Default on first launch (no saved state) is no sort — file order from FileScanner, matching today's behavior.
  - **Empty state and loading state are unchanged.** No sort UI is visible when `player.tracks` is empty.
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - §7.1 AVURLAsset rule preserved (this card touches PlayerEngine but not asset creation).
  - §7.2 Gapless playback preserved — verify by ear: change sort mid-playback near the end of a track and confirm the next track (per the new sort order) plays seamlessly.
  - §7.3 Two-phase loading preserved — sorting must work both before and after metadata enrichment completes. (Tracks initially have placeholder artist/album/title; sort by those fields will reorder again when metadata lands. That is acceptable; do not block sort on metadata.)
---

## Context

User request (2026-04-08): "feature request: sorting by column. much like itunes, I want to be able to sort all the tracks in my library by column (song title, artist name (preserving album order when doing so), album name (preserving album order), and duration. kick off the process for this."

Clarifications confirmed by user before card was written:
- Queue follows sort (iTunes behavior).
- Sort state persists across launches.
- Default on first launch is file order (no sort).

This sits next to card 0008 (search filter), which is the most recent UX change in `ContentView.swift`. Sort + search must compose: filtered view = sort applied, then filter applied. Read card 0008 (in `.pm/done/`) for the index-translation pattern used by double-click and context menu — the same pattern applies here, but with an extra wrinkle (see Risks below).

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits.*

**Approach:**

**Files:**

**Risks:**
- **Queue follows sort means `player.tracks` itself must be reordered.** This is the load-bearing decision. The simpler alternative — keep `player.tracks` in file order and only sort the display — was rejected because it would require translating every queue index through a sort permutation. Instead, on a sort change, mutate `player.tracks` in place and then recompute `currentIndex` by URL match (mirrors `updateMetadata` at PlayerEngine.swift:147-169). The 3-item lookahead in `enqueueMoreIfNeeded` then naturally rebuilds around the new position.
- **Gapless invariant (§7.2).** Reordering `player.tracks` mid-playback is exactly the kind of change that can break gapless. Test by ear: start a track, let it get within ~10 seconds of the end, change the sort, and confirm the next track in the new sort order plays without a gap or restart. If the lookahead tail needs to be torn down and rebuilt, do it carefully — don't yank items the queue player is currently fading into.
- **Search filter interaction.** `filteredTracks` in ContentView.swift currently filters `player.tracks`. After this card, `player.tracks` is sorted, so `filteredTracks` is automatically sorted too. The double-click index-translation pattern (ContentView.swift:128-138) still works because it looks up by `Track.ID`, not by index. Verify nothing else depends on a "natural" file order of `player.tracks`.
- **SwiftUI Table sort affordance.** SwiftUI's `Table` supports `sortOrder: Binding<[KeyPathComparator<Track>]>` for native column-header click + indicator. Prefer that over hand-rolling header buttons. But `KeyPathComparator` only does single-key sorts — the "preserve album order when sorting by artist" requirement needs a custom `SortComparator` or a manual sort step driven off the `sortOrder` binding. Engineer should pick one approach during plan mode and document it here.
- **Persistence format.** Store the column id (string) and direction (ascending/descending) as two UserDefaults keys, or a single encoded struct. Pick one and document.
- **Empty/missing metadata.** Tracks with empty artist or album strings should sort to a stable position (suggest: empty strings sort first in ascending). Don't crash, don't flicker.

**Open questions:**

## Log
- 2026-04-08 — manager card created in ready/ after clarifying queue/persistence/default-sort with user

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

## Manager Decision
*Filled in by the manager when closing or kicking back.*
