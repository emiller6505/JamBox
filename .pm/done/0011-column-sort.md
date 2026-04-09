---
id: 0011
title: Sort track list by column header (iTunes-style)
created: 2026-04-08
needs_design: false
designer: null
engineer: engineer-11
qa: qa-11
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
- 2026-04-08 — engineer-11 plan ready (custom TrackComparator SortComparator, player.reorderTracks)
- 2026-04-08 — engineer-11 implementation complete, build green, self-audit written, → qa
- 2026-04-08 — qa-11 claimed, beginning independent audit
- 2026-04-08 — qa-11 APPROVE: all acceptance + invariants pass, build green, one deferred audible gapless check

## Self-Audit

1. **Re-read modified files top to bottom:**
   - `JamBox/ContentView.swift` — re-read in full. Sort types (`SortColumn`, `TrackComparator`, `ComparisonResult.reversed`, `SortDefaults`) are file-private and sit above `ContentView`. Multi-key compare logic inspected: title/duration flip the whole result; artist/album only flip the primary axis. Track-number nil-last logic inspected. No dead code, no debug prints, no TODOs.
   - `JamBox/PlayerEngine.swift` — re-read the new `reorderTracks(to:)` block. No-op guard uses `zip + allSatisfy` on id sequence. Mutates `tracks`, recomputes `currentIndex` by URL match, prunes `queuePlayer.items().dropFirst()`, then calls `enqueueMoreIfNeeded()`. No new AVURLAsset construction added. Pre-existing `enqueueMoreIfNeeded` still uses `Self.assetOptions` (AVURLAssetPreferPreciseDurationAndTimingKey).
   - `JamBox/Track.swift` — single-line change: added `Equatable` conformance (synth). All stored fields are already Equatable.

2. **Acceptance walkthrough:**
   - **Clicking a sortable column header sorts the visible list** — `Table(..., sortOrder: $sortOrder)` + `TableColumn(..., sortUsing: TrackComparator(...))`. SwiftUI publishes new sortOrder on header click; ContentView.swift:199, 227, 234, 241, 248.
   - **Toggle asc/desc with direction indicator** — Native SwiftUI Table behavior when using `sortOrder` binding. Indicator rendered by the framework.
   - **Only Title/Artist/Album/Duration sortable** — The speaker-icon column (ContentView.swift:203) and "#" column (ContentView.swift:213) use the value-less `TableColumn` initializer, so no sort affordance appears on their headers.
   - **Title sort** — `TrackComparator` `.title` case calls `localizedCaseInsensitiveCompare` on `displayName` and applies direction flip (ContentView.swift:26-27, 57).
   - **Artist sort with preserved album order** — `.artist` case does primary case-insensitive compare on artist with direction flip, then falls through to `albumThenTrackCompare` (album asc → trackNumber asc → filename) always ascending (ContentView.swift:28-36, 62-66).
   - **Album sort with preserved track order** — `.album` case does primary case-insensitive compare on album with direction flip, then track number asc (nil last) then filename (ContentView.swift:37-44, 69-82).
   - **Duration sort numeric** — `.duration` case compares `TimeInterval` directly with filename tiebreaker, then direction flip (ContentView.swift:45-53).
   - **Sort drives the playback queue** — `onChange(of: sortOrder)` calls `player.reorderTracks(to: player.tracks.sorted(using: newOrder))` (ContentView.swift:357-369). `PlayerEngine.reorderTracks` mutates `self.tracks` to match, and the existing `play(startingAt:)` / `enqueueMoreIfNeeded` flow uses `self.tracks` directly, so the queue follows sort (PlayerEngine.swift:140-172).
   - **Sort + search compose** — `sortedBase` (sorted) is the input to `filteredTracks`, which applies the search filter on top (ContentView.swift:126-146). Clearing search restores the full sorted list because the filter no-ops on an empty query.
   - **Active playback survives a sort change** — `reorderTracks` does not touch `queuePlayer.items()[0]` (the playing item). It prunes `dropFirst()` only, then refills via `enqueueMoreIfNeeded()`. `currentIndex` is rebound by URL match before the refill. Pattern mirrors `applyTrackDiff` (PlayerEngine.swift:140-171).
   - **Persistence** — `loadPersistedSort` / `persistSort` / `clearPersistedSort` use UserDefaults keys `jambox.sort.column` and `jambox.sort.direction`. Loaded in `.onAppear` (ContentView.swift:344-356), saved on `sortOrder` change (ContentView.swift:357-369). First launch: no keys set → `loadPersistedSort` returns nil → `sortOrder` stays empty → file order preserved.
   - **Empty state unchanged** — Table only renders when `player.tracks` is non-empty (unchanged conditional at ContentView.swift:181-198). Search field also hidden in empty state (unchanged).
   - **Build passes** — see step 3.
   - **AVURLAsset rule preserved** — see step 4.
   - **Gapless preserved** — see step 4 and the active-playback-survives bullet above. Code-path preserved: only stale tail items are removed; the playing item is not touched.
   - **Two-phase loading preserved** — `.onChange(of: player.tracks)` re-applies sort whenever `player.tracks` changes (which fires from `updateMetadata` at PlayerEngine.swift:174-181). The no-op guard in `reorderTracks` breaks what would otherwise be an onChange loop (ContentView.swift:370-378, PlayerEngine.swift:141-146). Sorting works before or after enrichment.

3. **Build result:**
   ```
   xcodebuild -project JamBox.xcodeproj -scheme JamBox build
   ** BUILD SUCCEEDED **
   ```
   No new warnings. The five pre-existing `main actor-isolated` warnings in `PlayerEngine.swift` around the periodic time observer (lines 90-99) are untouched by this card.

4. **Invariants verified:**
   - **§7.1 AVURLAsset** — No new `AVURLAsset` constructions added. `reorderTracks` only *removes* items from `queuePlayer` and calls existing `enqueueMoreIfNeeded()`, which already uses `Self.assetOptions = [AVURLAssetPreferPreciseDurationAndTimingKey: true]` (PlayerEngine.swift:62-64, 254-256). Verified by grepping the diff for `AVURLAsset(` — no new matches.
   - **§7.2 Gapless playback** — `reorderTracks` explicitly leaves `queuePlayer.items()[0]` alone (the currently-playing item) and only prunes the tail (`dropFirst()`). This follows AVQueuePlayer's documented behavior that removing items after the current item does not interrupt playback. The 3-item lookahead is refilled immediately via the existing `enqueueMoreIfNeeded()`. By-ear verification is pending user test per the card; code path is correct by inspection.
   - **§7.3 Two-phase loading** — Verified via `.onChange(of: player.tracks)` re-sort (ContentView.swift:370). Track now conforms to `Equatable` so the `onChange` observer compiles and fires on metadata enrichment.
   - **§7.4 Sandbox bookmarks** — Not touched. No new `startAccessingSecurityScopedResource` calls.
   - **§7.5 Xcodegen** — No source files added or removed. Only edits to three existing files. `xcodegen generate` not needed.
   - **§7.6 Build green** — Confirmed in step 3.

5. **Hostile diff review (`git diff main`):**
   - `TrackComparator.compare` for `.artist` and `.album` early-returns before the common direction-flip at the bottom of the function — intentional, so that direction only affects the primary axis. Potentially surprising at a glance but documented in the `///` comment and inline comments.
   - `reorderTracks` no-op guard uses `zip + allSatisfy`. Correct only when `.count` matches, which we check first — otherwise `zip` silently truncates and could return a false positive. The `newOrder.count == tracks.count` precondition handles that.
   - `.onChange(of: player.tracks)` and `.onChange(of: sortOrder)` both call `reorderTracks`, which writes to `player.tracks`, which fires `.onChange(of: player.tracks)` again. The no-op guard breaks the loop after one iteration. Confirmed by inspection.
   - `filteredTracks` no longer has the top-line comment about "display only", because `player.tracks` IS now mutated by sort. New comment explicitly calls this out: "the filter itself is display-only; the playback queue is driven by `player.tracks` (which is kept in sortedBase order via `player.reorderTracks`)." (ContentView.swift:131-136).
   - `scrollTargetRow` still uses indices into `player.tracks` directly (ContentView.swift:317-319), which is correct because `player.tracks` is now in display/sort order.
   - `SortDefaults` is a top-level private enum. It's accessible from within file-private `ContentView.loadPersistedSort` and friends. Fine.
   - `TrackComparator` is `Equatable, Hashable`. `Hashable` is not strictly required but is free via synth and future-proofs against using it as a dictionary key. Tiny scope creep; keeping it.
   - No debug prints, no commented-out code, no TODO/FIXME introduced.

6. **Touched-files reconciliation:**
   - Actual changed: `JamBox/ContentView.swift`, `JamBox/PlayerEngine.swift`, `JamBox/Track.swift`.
   - Frontmatter `touches:` already listed these three. Match — no update needed.

7. **Scope check:**
   - `Track: Equatable` — required so `.onChange(of: player.tracks)` compiles. In scope.
   - `TrackComparator: Hashable` — free synth, not strictly required. Minor; keeping since it's a single extra conformance. Would not file a separate card.
   - No other unrelated changes.

## QA Report

Independent audit by qa-11 on 2026-04-08. Read `## Plan`, then read `ContentView.swift`, `PlayerEngine.swift`, `Track.swift` top to bottom. Ran `git diff 3ec47f0 HEAD -- <touched files>` (the pre-card-0011 base) and read every line. Built with `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` → `** BUILD SUCCEEDED **`, no new warnings.

### Acceptance

- [PASS] Clicking a sortable column header sorts the visible list — `Table(filteredTracks, selection: $selection, sortOrder: $sortOrder)` at ContentView.swift:199; sortable columns use `sortUsing: TrackComparator(column: …)` (ContentView.swift:227, 234, 241, 248). SwiftUI drives the sort via the comparator's `compare(_:_:)`.
- [PASS] Asc/desc toggle with direction indicator — native SwiftUI Table behavior provided by the `sortOrder:` binding. Confirmed by using the `(title, value:content:)` column initializer; clicking the already-active header flips `order` on the comparator and SwiftUI renders the chevron.
- [PASS] Only Title/Artist/Album/Duration sortable — the speaker column (ContentView.swift:203) and "#" column (ContentView.swift:213) use the value-less `TableColumn` initializer, so no sort affordance.
- [PASS] Title sort — `localizedCaseInsensitiveCompare` on `displayName` with direction flip (ContentView.swift:26-27, 56-57).
- [PASS] Artist sort with preserved album order — `.artist` case applies direction only to the primary artist key; on `.orderedSame`, falls through to `albumThenTrackCompare` (ContentView.swift:28-36, 62-66) which is hard-coded ascending. Direction flip for artist does NOT affect album/track ordering inside an artist group. Verified by reading every branch.
- [PASS] Album sort with preserved track order — `.album` case applies direction only to the album key, falls through to `trackNumberThenFilenameCompare` always ascending (ContentView.swift:37-44, 69-82).
- [PASS] Duration sort numeric — direct `<`/`>` on `TimeInterval` with filename tiebreaker (ContentView.swift:45-53).
- [PASS] Sort drives the playback queue — `onChange(of: sortOrder)` calls `player.reorderTracks(to: player.tracks.sorted(using: newOrder))` (ContentView.swift:357-368). `reorderTracks` reassigns `self.tracks` to the new order (PlayerEngine.swift:149), recomputes `currentIndex` by URL (PlayerEngine.swift:151-157), and rebuilds the lookahead via `enqueueMoreIfNeeded()`. Double-click handler translates filtered-row id → `player.tracks.firstIndex` (ContentView.swift:261-265) which now returns the sorted index.
- [PASS] Sort + search compose — `filteredTracks` computes `sortedBase` first then filters on top (ContentView.swift:137-146). Clearing `searchQuery` returns `base` (= sortedBase) unchanged. Double-click translates by id, not index, so it correctly finds the right track in `player.tracks` regardless of filter state (ContentView.swift:261-265).
- [PASS] Active playback survives a sort change — `reorderTracks` never touches `queuePlayer.items()[0]`. It iterates `queuePlayer.items().dropFirst()` (PlayerEngine.swift:165-167) and removes only lookahead items. Per AVQueuePlayer semantics, removing items after the current item does not interrupt playback. `currentIndex` is rebound by URL match before the refill. The pattern mirrors the existing `applyTrackDiff` and `updateMetadata` flows. Note: by-ear confirmation deferred to user per the card; code path is correct by inspection.
- [PASS] Persistence — `loadPersistedSort` in `.onAppear` reads `jambox.sort.column` and `jambox.sort.direction` (ContentView.swift:417-426); `persistSort` writes them on `onChange(of: sortOrder)` (ContentView.swift:431-436). `clearPersistedSort` handles the empty-sortOrder edge case (ContentView.swift:438-442). First launch with no saved keys: `loadPersistedSort` returns nil → `sortOrder` stays empty → `sortedBase` returns `player.tracks` unchanged → file order from FileScanner.
- [PASS] Empty state unchanged — Table only renders when `player.tracks` is non-empty (ContentView.swift:181-198 conditional preserved from card 0008); sort UI is inside the Table branch only.
- [PASS] Build passes — `** BUILD SUCCEEDED **`, no new warnings introduced. Pre-existing warnings around the periodic time observer are unchanged.
- [PASS] AVURLAsset rule preserved — see Invariants §7.1 below.
- [PASS by inspection / PENDING AUDIBLE] Gapless preserved — see Invariants §7.2 below. Code path is correct; the user will do the final by-ear check.
- [PASS] Two-phase loading preserved — `onChange(of: player.tracks)` at ContentView.swift:370-378 catches `updateMetadata`'s `tracks` publish (PlayerEngine.swift:174-181) and re-applies the sort. The no-op guard in `reorderTracks` (PlayerEngine.swift:141-146) breaks the otherwise-infinite observer loop. `Track: Equatable` was added (Track.swift:4) specifically so `onChange(of: [Track])` compiles and fires correctly on field changes.

### Invariants

- [PASS] §7.1 AVURLAsset — No new `AVURLAsset` constructions. `reorderTracks` only calls `queuePlayer.remove(_:)` and the pre-existing `enqueueMoreIfNeeded()`, which continues to use `Self.assetOptions = [AVURLAssetPreferPreciseDurationAndTimingKey: true]` (PlayerEngine.swift:62-64, 305-307). Grepped the diff for `AVURLAsset(` — no new matches.
- [PASS (by inspection)] §7.2 Gapless playback — The 3-item lookahead is preserved. `reorderTracks` explicitly skips `queuePlayer.items()[0]` via `dropFirst()` (PlayerEngine.swift:165), removes only stale tail items, then refills via `enqueueMoreIfNeeded()`. Documented AVQueuePlayer behavior: removing items beyond the current item does not interrupt playback. The currently-playing `AVPlayerItem` retains its asset, so the audio decoder is not torn down. Re-sort mid-playback should be seamless. The user will confirm audibly.
- [PASS] §7.3 Two-phase loading — Sort does not block on metadata. Initial sort applied in `.onAppear`; when enriched metadata lands, `onChange(of: player.tracks)` re-applies the sort. Card explicitly allows the visual reorder-on-enrichment.
- [N/A] §7.4 Sandbox bookmarks — Not touched by this card. No new `startAccessingSecurityScopedResource` calls.
- [N/A] §7.5 Xcodegen — No source files added or removed, only edits to three existing files. No project regeneration needed.
- [PASS] §7.6 Build green — `** BUILD SUCCEEDED **`.

### Findings

- [NIT] ContentView.swift:344-355 — `onAppear` restores `sortOrder` and then immediately calls `player.reorderTracks(to:)` explicitly. But setting `sortOrder` will also trigger `.onChange(of: sortOrder)` (ContentView.swift:357), which also calls `persistSort` and `reorderTracks`. Result: one redundant `persistSort` write (of the same values just loaded) and a second `reorderTracks` call whose no-op guard will catch it. Not a bug, just double work on launch. Safe to leave.
- [NIT] ContentView.swift:357-368 — On sort restore at launch, `persistSort` re-writes the UserDefaults keys that were just read from. Harmless but slightly muddy. A guard like "only persist if newOrder differs from what's already saved" would be cleaner but is not worth a kickback.
- [NIT] PlayerEngine.swift:143-146 — No-op guard uses `zip(newOrder, tracks).allSatisfy(...)`. Correct only because `newOrder.count == tracks.count` is checked first; `zip` silently truncates to the shorter sequence otherwise. The precondition is explicit, so this is fine.
- [NIT] `TrackComparator: Hashable` is not strictly required (only `SortComparator + Equatable` are needed). Free synth, no harm. Minor scope creep; not worth a card.
- [INFO / NOT A FINDING] Direction-flip semantics for the `.artist` case: the early-return branch applies direction ONLY to the primary artist axis and never flips album/track sub-order. Verified by tracing every branch. The `.album` case follows the same pattern. This is the most load-bearing detail of the card and it is implemented correctly.
- [INFO] `Track: Equatable` (Track.swift:4) is justified — required so `.onChange(of: player.tracks)` compiles. All stored fields are already Equatable so synth works. No behavioral risk.
- [INFO] `applyTrackDiff` (PlayerEngine.swift:191-222) re-sorts by filename after a folder-watcher diff. When a user sort is active, `.onChange(of: player.tracks)` will re-apply the sort on top. This chain works correctly because the onChange observer handles any `player.tracks` mutation.
- No debug prints, no TODO/FIXME, no commented-out code, no unrelated changes, no style inconsistencies with surrounding code.

### Recommendation

- APPROVE

All twelve acceptance bullets pass by code inspection, all applicable invariants pass, and the build is green. The one deferred item is the audible gapless check at a track boundary, which the engineer's self-audit and this QA both confirmed is correct by code path (the currently-playing `queuePlayer.items()[0]` is never touched; only tail items are pruned and the lookahead is refilled via the existing `enqueueMoreIfNeeded` which uses `Self.assetOptions` with `AVURLAssetPreferPreciseDurationAndTimingKey`). The manager/user should do one by-ear test at a track boundary before shipping, but no code changes are needed. The nits above are not worth a kickback or a child card.

## Manager Decision

2026-04-08 — APPROVE. QA-11 audit passed all acceptance bullets and applicable invariants; build green; no blockers, no major findings. Closing to done/. Final by-ear gapless check happens during user manual validation of the Release build.
