---
id: 0011
title: Sort track list by column header (iTunes-style)
created: 2026-04-08
needs_design: false
designer: null
engineer: engineer-11
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

**Approach:**

Sort is a property of `ContentView`'s view state, driven by SwiftUI `Table`'s native `sortOrder: Binding<[KeyPathComparator<Track>]>`. But because this project requires multi-key sorts (artist → album → track; album → track) AND "queue follows sort," I will:

1. Introduce a small sort model in `ContentView.swift` (private types `SortColumn` and `SortDirection`) independent of `KeyPathComparator`. `SortColumn` has four cases: `.title`, `.artist`, `.album`, `.duration` — plus I'll encode "no sort" as `nil`. I will still use the Table's native `sortOrder` binding so the user gets free column-header click handling and direction indicators, but the `KeyPathComparator<Track>` instances will act as *tokens* whose identity I map back to my internal `SortColumn`. When `sortOrder` changes, I recompute the full sort.
2. A pure function `sortedTracks(_ tracks: [Track], by column: SortColumn, direction: SortDirection) -> [Track]` does the actual multi-key sort:
   - Title: `localizedCaseInsensitiveCompare` on `displayName`, direction applied.
   - Artist: primary key artist (case-insensitive), secondary album (case-insensitive, always ascending), tertiary trackNumber (nil last, ascending), quaternary filename (for stability). Direction flips only the artist axis.
   - Album: primary album (case-insensitive), secondary trackNumber (nil last, ascending), tertiary filename. Direction flips only the album axis.
   - Duration: numeric compare on `duration`, direction applied. Stable tiebreaker by filename.
   - Empty artist/album strings sort first in ascending (natural Swift string compare behavior — empty < non-empty). Documented in a comment.
3. **Sort drives the queue.** Add `PlayerEngine.applySort(_ sortFn: ([Track]) -> [Track])` — or simpler, `PlayerEngine.reorderTracks(to newOrder: [Track])` that takes a pre-sorted array whose members are the same set of tracks by id, reassigns `self.tracks`, re-derives `currentIndex` by URL match (mirrors `updateMetadata` at PlayerEngine.swift:123-130 and `applyTrackDiff` at 140-171), and calls `enqueueMoreIfNeeded()` if playback is active. Critically, I do NOT touch `queuePlayer` items that are already enqueued — the currently-playing item keeps playing untouched; only the tail of the lookahead needs to be reconciled. To reconcile gapless correctly: I'll remove any queued items AFTER the currently-playing item and then call `enqueueMoreIfNeeded()` to refill from the new `currentIndex + 1`. This is safe because AVQueuePlayer's `remove(_:)` on not-yet-playing items does not interrupt the currently-playing item.
4. **ContentView integration.** Add `@State private var sortOrder: [KeyPathComparator<Track>] = []`, `@State private var sortColumn: SortColumn? = nil`, `@State private var sortDirection: SortDirection = .ascending`. On init, restore from UserDefaults. The Table gets `Table(filteredAndSortedTracks, selection: $selection, sortOrder: $sortOrder)` and each sortable `TableColumn` uses the `(title, value:)` initializer with a `KeyPathComparator`. Use `.onChange(of: sortOrder)` to (a) translate the first comparator back to my `SortColumn`/`SortDirection`, (b) persist to UserDefaults, (c) call `player.reorderTracks(to: sortedTracks(player.tracks, by:...))`. `filteredTracks` becomes `filteredAndSortedTracks` — since `player.tracks` is already sorted by step 3, filtering on top is still correct and preserves sort order.
5. **Persistence.** Two UserDefaults keys: `jambox.sort.column` (string: "title"/"artist"/"album"/"duration" or absent) and `jambox.sort.direction` (string: "asc"/"desc"). Absent column = no sort (first-launch default). Restore in `ContentView.onAppear` and apply to `player.tracks` once on load. The initial `loadTracks` happens before ContentView appears, so the sort applied on appear will reorder file-order tracks — that's correct.
6. **Interaction with two-phase loading.** After FileScanner's fast scan, `player.loadTracks` is called and then `ContentView.onAppear` applies the saved sort (if any). When `updateMetadata` lands with enriched titles/artists/albums, it preserves positional order (see PlayerEngine.swift:123-130). That's stale for metadata-driven sorts. I'll add an `.onChange(of: player.tracks)` in ContentView that re-applies the current sort whenever `player.tracks` mutates — this catches the metadata-enrichment update and also any future folder-watcher diffs. Use `removeDuplicates` semantics via a simple `tracks.count + a hash` guard? No — simpler: re-sort on every `player.tracks` change. The re-sort is stable so no flicker if already sorted.

   Wait — `reorderTracks` writes to `player.tracks`, which triggers `.onChange`, which triggers `reorderTracks` again: infinite loop. Fix: re-sort path uses a local `sortedTracks` helper and only calls `reorderTracks` if the new order differs from current. Alternatively, `reorderTracks` checks if incoming array equals current by id-sequence and is a no-op in that case. I'll do the no-op check inside `reorderTracks` (cheap: zip ids).

7. **Edge case: empty tracks or no-sort state.** When `sortColumn == nil`, no reordering happens — `player.tracks` stays in FileScanner order. The Table's `sortOrder` is `[]`. Clicking a header will populate `sortOrder` with the default comparator for that column (ascending), triggering the onChange path.

**Files:**
- `JamBox/ContentView.swift` — add sort state, `SortColumn`/`SortDirection`, `sortedTracks` helper, wire sort binding to Table columns, persistence, onAppear + onChange handling.
- `JamBox/PlayerEngine.swift` — add `reorderTracks(to:)` method that mutates `tracks`, recomputes `currentIndex` by URL, prunes lookahead tail, refills via `enqueueMoreIfNeeded`.
- `JamBox/Track.swift` — no changes expected. (Will remove from `touches:` if still true at self-audit.)

**Risks:**
- **Gapless (§7.2).** The reorder must not yank the currently-playing item. `AVQueuePlayer.remove(_:)` on items strictly after `currentItem` is documented safe. I will iterate `queuePlayer.items()`, skip index 0 (the current item), and remove the rest, then call `enqueueMoreIfNeeded()`. Test by ear per the acceptance bullet.
- **AVURLAsset rule (§7.1).** `enqueueMoreIfNeeded` already uses `Self.assetOptions` which sets `AVURLAssetPreferPreciseDurationAndTimingKey`. I will not add any new `AVURLAsset` creation.
- **Re-sort loop on `player.tracks` onChange.** Addressed via no-op guard in `reorderTracks` that compares id sequences.
- **Sort comparator identity.** SwiftUI's `KeyPathComparator` equality is keypath-based. I'll identify my column by matching on `comparator.keyPath` against known keypaths; or simpler, keep a parallel `[KeyPathComparator<Track>]` table of known comparators and compare by `Any`-cast. Actually the cleanest path: use the `TableColumn.init(_:value:)` that takes a `KeyPath<Track, Comparable>`, giving each column its own keypath, then in onChange inspect `sortOrder.first?.keyPath` via string description or ObjectIdentifier. That's fragile. Better: put a hidden tag by using `SortDescriptor` or my own `struct TrackComparator: SortComparator`. I'll implement `TrackComparator: SortComparator` that carries my `SortColumn` as a stored property; then `sortOrder: [TrackComparator]`. This keeps the Table's native header-click + indicator working AND lets me identify the column cleanly. The comparator's `compare(_:_:)` method just calls into my `sortedTracks`-style pairwise logic (or delegates: since the Table uses `sortOrder` to sort automatically, I need my comparator to actually perform the multi-key comparison per pair). I'll define `compare(lhs, rhs) -> ComparisonResult` that does the full multi-key logic for that column. The Table will then sort correctly on its own AND my `reorderTracks` is driven by the same sortOrder value. This removes the need for a separate `sortedTracks` function — the Table does the sort, I just read `filteredTracks` which is already in sorted order when I call `player.reorderTracks`.

  Refinement: the Table sorts whatever I pass in, so if I pass `player.tracks` and also own `sortOrder`, Table displays a sorted view but does NOT mutate `player.tracks`. I still need to apply the sort to `player.tracks` for the queue. Simplest: compute `let sorted = player.tracks.sorted(using: sortOrder)` once per body, use that for the Table AND hand it to `player.reorderTracks` in the onChange. Then filteredTracks filters the sorted array. Let me lock in this approach:
    - `sortOrder: [TrackComparator]` state, `TrackComparator: SortComparator` knows its column and direction.
    - `sortedBase: [Track]` = `player.tracks` sorted with `sortOrder` (or unchanged if empty).
    - `visibleTracks` = `sortedBase` filtered by search query.
    - Table fed `visibleTracks` with `sortOrder: $sortOrder` so headers get the indicator.
    - `onChange(of: sortOrder)` → persist + call `player.reorderTracks(to: sortedBase)`.
    - `onChange(of: player.tracks)` → if sortOrder non-empty, call `player.reorderTracks(to: player.tracks.sorted(using: sortOrder))`.
    - `reorderTracks` no-ops if the id sequence already matches.

- **Search compose.** `visibleTracks` is sorted-then-filtered. Double-click handler still translates by id via `player.tracks.firstIndex(where:)`, which now finds the id in the sorted-in-place `player.tracks`. Correct.
- **Persistence format.** Two string keys as described. I'll encode `SortColumn` as `rawValue: String`.
- **Empty metadata fields.** `localizedCaseInsensitiveCompare` on empty strings vs. non-empty: empty sorts first in ascending (standard Swift behavior). Adequate for acceptance.
- **Two-phase loading.** The `onChange(of: player.tracks)` path catches metadata enrichment. If the user had "sort by title" saved and `player.tracks` lands with filenames, they'll see filename-order sort; when metadata arrives, `updateMetadata` triggers onChange, re-sort happens, user sees title-order. Card explicitly says this is acceptable.
- **ContentView view identity with `.onChange(of: player.tracks)`.** `Track` doesn't conform to `Equatable`, so `onChange(of: [Track])` won't compile. I'll either add `Equatable` conformance to `Track` (cheap: URL-based), or observe `player.tracks.count` plus a revision counter. Simpler: add `Equatable` synth to `Track`. All fields are `Equatable`. This is the only Track.swift change — keep it in `touches:`.

**Open questions:**
- None blocking. Default sort direction on first click of a header is ascending (SwiftUI Table default) — matches expectation.
- **Queue follows sort means `player.tracks` itself must be reordered.** This is the load-bearing decision. The simpler alternative — keep `player.tracks` in file order and only sort the display — was rejected because it would require translating every queue index through a sort permutation. Instead, on a sort change, mutate `player.tracks` in place and then recompute `currentIndex` by URL match (mirrors `updateMetadata` at PlayerEngine.swift:147-169). The 3-item lookahead in `enqueueMoreIfNeeded` then naturally rebuilds around the new position.
- **Gapless invariant (§7.2).** Reordering `player.tracks` mid-playback is exactly the kind of change that can break gapless. Test by ear: start a track, let it get within ~10 seconds of the end, change the sort, and confirm the next track in the new sort order plays without a gap or restart. If the lookahead tail needs to be torn down and rebuilt, do it carefully — don't yank items the queue player is currently fading into.
- **Search filter interaction.** `filteredTracks` in ContentView.swift currently filters `player.tracks`. After this card, `player.tracks` is sorted, so `filteredTracks` is automatically sorted too. The double-click index-translation pattern (ContentView.swift:128-138) still works because it looks up by `Track.ID`, not by index. Verify nothing else depends on a "natural" file order of `player.tracks`.
- **SwiftUI Table sort affordance.** SwiftUI's `Table` supports `sortOrder: Binding<[KeyPathComparator<Track>]>` for native column-header click + indicator. Prefer that over hand-rolling header buttons. But `KeyPathComparator` only does single-key sorts — the "preserve album order when sorting by artist" requirement needs a custom `SortComparator` or a manual sort step driven off the `sortOrder` binding. Engineer should pick one approach during plan mode and document it here.
- **Persistence format.** Store the column id (string) and direction (ascending/descending) as two UserDefaults keys, or a single encoded struct. Pick one and document.
- **Empty/missing metadata.** Tracks with empty artist or album strings should sort to a stable position (suggest: empty strings sort first in ascending). Don't crash, don't flicker.

**Open questions:**

## Log
- 2026-04-08 — manager card created in ready/ after clarifying queue/persistence/default-sort with user
- 2026-04-08 — engineer-11 claimed, moved to in-progress/

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
