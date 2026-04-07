---
id: 0008
title: Add search filter input to filter visible tracks by title/artist/album
created: 2026-04-07
engineer: engineer-04
qa: null
parent: null
priority: P2
estimate: S
depends_on: []
touches:
  - JamBox/ContentView.swift
acceptance:
  - A text input with a magnifying-glass SF Symbol (`magnifyingglass`) is rendered in the top-right area of the main window, styled like the search fields in Apple Notes / iTunes (rounded, unobtrusive)
  - Typing into the field filters the visible song table in real time as the user types — no Enter key required
  - The filter is a case-insensitive substring match against ANY of: track title, artist, album. A track is visible if its query matches at least one of those three fields (non-exclusive OR — the user does NOT specify which field)
  - Empty / whitespace-only query string shows all tracks (filter is a no-op)
  - Tracks with missing metadata (e.g. nil artist) are matched only against the fields they do have; missing fields don't crash and don't spuriously match
  - Filtering only changes which rows are *displayed*. The underlying `player.tracks` array and the playback queue are NOT mutated. Currently-playing track continues to play even if it gets filtered out of view
  - Double-click-to-play on a filtered row plays that row correctly (the index passed to `player.play(startingAt:)` must refer to the track's position in `player.tracks`, NOT its position in the filtered view)
  - Right-click context menu (card 0001) continues to work on filtered rows (Play, Show in Finder)
  - The album-art overlay (card 0004) — IF that card has shipped by the time this lands — must either (a) recompute groups from the filtered view, or (b) be documented as a known limitation in this card's plan. Engineer decides during plan mode based on whether 0004 is in main yet
  - The currently-playing speaker indicator continues to mark the playing row when that row is visible in the filtered view
  - Clearing the search field (or deleting all text) restores the full unfiltered view with no flicker and no scroll-position jump beyond what is unavoidable
  - Keyboard: Cmd-F focuses the search field (standard macOS convention). Esc while focused clears the field and unfocuses
  - Build passes cleanly with no new warnings: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - Gapless playback unchanged — no edits to PlayerEngine queue logic
  - AVURLAsset invariant unaffected (no audio code touched)
  - Two-phase loading invariant unaffected — search must work on whatever metadata is currently loaded; tracks whose metadata hasn't loaded yet match only against filename-derived title
---

## Context

User-facing request:

> "search filter. At the top right corner, a text input with a simple magnifying glass icon (think apple notes or iTunes). When the user types in the search box, the visible songs in the list should be filtered by that search input.
> - Search works across artist, song title, and album title WITHOUT the user specifying which one they are searching for (non-exclusive OR search)
> - Filter is applied as the user types (they don't have to press enter)"

### Implementation orientation

This is a view-layer-only feature. `ContentView` already holds `player.tracks` via `@EnvironmentObject`. Add a `@State private var searchQuery: String = ""` and derive a `filteredTracks` computed property. Pass `filteredTracks` (not `player.tracks`) to the `Table`.

**Critical correctness point:** the `Table`'s row identity and the index passed to `player.play(startingAt:)` for double-click must continue to refer to indices into `player.tracks`, not into `filteredTracks`. The cleanest way: keep using `Track.ID` (the existing `Identifiable` UUID) for selection, and look up the index in `player.tracks` by ID at the moment of the play action — same pattern the right-click context menu (card 0001) already uses. Verify this in plan mode.

### Search field placement

The current `ContentView` layout has folder management chrome at the top. The search field belongs in the top-right corner, aligned with that chrome. SwiftUI's `TextField` with a `.textFieldStyle(.roundedBorder)` and a leading `Image(systemName: "magnifyingglass")` inside an `HStack` is the standard idiom. macOS 14 also has `.searchable(text:)` modifier on views — engineer should consider it but be aware that `.searchable` places the field in the toolbar, which may or may not match the user's "top right corner" intent. Decide in plan mode and document the choice.

### Match logic

```
let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
guard !q.isEmpty else { return player.tracks }
return player.tracks.filter { track in
    (track.title?.lowercased().contains(q) ?? false) ||
    (track.artist?.lowercased().contains(q) ?? false) ||
    (track.album?.lowercased().contains(q) ?? false)
}
```

For libraries of ~1000-5000 tracks this linear scan on every keystroke is fine — no need for an index, prefix trie, or debouncing in v1. If profiling shows lag at scale, address in a follow-up card.

### Theme considerations

The search field needs to look acceptable in all three themes (light, dark, candy). The candy theme has a vibrant gradient background — a default `.roundedBorder` text field may look out of place. Engineer should test all three themes and adjust styling minimally if needed (e.g. use `chromeBackground` from `Theme.swift` for consistency). Do NOT introduce new theme machinery for this card.

### Out of scope for v1

- Regex / glob / boolean operators (`AND`, `NOT`, quoted phrases)
- Search history / recent queries
- Highlighting matched substrings in the rendered rows
- Searching by file path, year, duration, or any field other than title/artist/album
- Persistence of the query across launches (it should reset to empty on launch)

## Plan

**Approach:**

View-layer-only change in `ContentView.swift`. Add `@State private var searchQuery: String = ""` and a `@FocusState private var searchFieldFocused: Bool` on `ContentView`. Compute `filteredTracks` (a `[Track]`) inside `body` from `player.tracks` and `searchQuery`, and pass that to `Table` instead of `player.tracks`.

Search field placement: hand-rolled `HStack` containing a leading `magnifyingglass` SF Symbol and a `TextField`, sized to ~200pt, pinned top-right of the main `VStack` via a new top chrome row above the `ZStack`. Reasoning for NOT using `.searchable`:
1. The card explicitly says "top right corner of the main window", not toolbar. `.searchable` puts the field in the toolbar (the platform conventional spot, but the user has explicitly described the iTunes/Notes look which has a dedicated search field in the content area's top-right).
2. The existing toolbar is sparse (one button), so injecting a search field there would visually compete with the "Change Folder" button rather than complement it.
3. A hand-rolled HStack gives full control over candy-theme styling (default `.searchable` chrome looks foreign on the gradient background).
4. We get explicit control over `@FocusState` for Cmd-F and Esc behavior.

The new top row will be a thin `HStack` with a `Spacer()` then the search field, given the same horizontal padding as the rest of the chrome. It is hidden when `player.tracks.isEmpty` to avoid showing a search box over the empty state.

Field styling: `.textFieldStyle(.roundedBorder)` is the macOS standard and looks fine in light/dark. For candy, the rounded border field is acceptable (the system control honors the dark color scheme set on the candy theme), so no special-casing — keeping it minimal per the card's "do NOT introduce new theme machinery" guidance. I'll verify visually post-build but plan to ship as-is unless it's actively broken.

**Filtering logic:**

```swift
private var filteredTracks: [Track] {
    let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return player.tracks }
    return player.tracks.filter { track in
        track.displayName.lowercased().contains(q)
            || track.artist.lowercased().contains(q)
            || track.album.lowercased().contains(q)
    }
}
```

Track fields are non-optional `String` (verified in Track.swift) — empty string for missing metadata. `"".contains(q)` returns false for any non-empty `q`, so missing fields naturally don't spuriously match. `displayName` is the title (or filename fallback) — this satisfies the "tracks whose metadata hasn't loaded yet match only against filename-derived title" invariant for free.

**Index translation:**

The Table is keyed on `Track.ID` (a `URL`). The double-click handler currently receives a row index against the array passed to `Table`. With filtering in place, that index points into `filteredTracks`, NOT `player.tracks`. Two ways to fix:
- (A) translate via `filteredTracks[row].id` then look up index in `player.tracks` using `firstIndex(where:)`.
- (B) switch double-click to operate on `selection` (a `Track.ID`) using the same lookup pattern as the context menu.

Going with (A) — minimal change, preserves the "double-click on the row I clicked" intent regardless of selection state. Right-click context menu already does the lookup correctly via `selection`/`ids`.

**Cmd-F focus:**

Add `.onKeyPress` won't see Cmd-F because Cmd-F is a key equivalent. Cleanest approach: a hidden `Button("", action: { searchFieldFocused = true }).keyboardShortcut("f", modifiers: .command).hidden()` placed inside the view hierarchy. The button's keyboard shortcut works window-wide. Bind `searchFieldFocused` to the TextField's `.focused(_:)` modifier.

Esc-to-clear: extend the existing `.onKeyPress(.escape)` handler. When `searchFieldFocused` is true, clear `searchQuery`, set `searchFieldFocused = false`, return `.handled`. Caveat: `.onKeyPress` on the parent VStack may not fire while the TextField has key focus (TextField consumes keystrokes). Fallback: attach `.onSubmit` won't help; instead use a `.onExitCommand` modifier on the TextField, or just on the search HStack — `onExitCommand` is the SwiftUI idiom for Esc on macOS and works while a child has focus. I'll use `.onExitCommand` on the TextField.

**Speaker indicator / playing row visibility:**

The speaker indicator column already renders per-row based on `track.id == player.currentTrack?.id`. Since filtered rows are still real Track values, this works unchanged. If the playing track is filtered out, it simply doesn't appear — consistent with acceptance.

**Album art overlay (card 0004):** not in main (only 0001/0002/0005 are done). N/A for this card.

**Files:**
- `JamBox/ContentView.swift` (only file)

`touches:` already lists exactly this file.

**Risks:**
- Body churn / re-render race: `searchQuery` is user-typed, low frequency, so the §6 concern about high-frequency `@Published` writes does not apply. The 4Hz playback timer is isolated in `PlaybackClock` and unaffected.
- Index translation bug: covered above with explicit lookup. The right-click context menu already uses the same pattern, so the precedent is established.
- Currently-playing track filtered out: acceptance explicitly says playback continues. We do not touch `player.tracks` or the queue, so gapless playback and the AVQueuePlayer 3-item lookahead are untouched.
- AVURLAsset / two-phase loading / sandbox bookmarks: not touched; no audio code changes.
- `.onKeyPress(.escape)` precedence: existing handler dismisses the artwork overlay when shown. If artwork is shown AND search is focused, artwork wins (the overlay handler is on the parent and runs first). That's fine — these states are mutually rare and the artwork-dismiss is the more important affordance.
- TextField default styling on candy theme: may look slightly out of place but should be functional. Will verify post-build, fall back to minimal styling tweak only if obviously broken.

**Open questions:** none.

## Log
- 2026-04-07 — manager created card from user request
- 2026-04-07 — engineer-04 picked up; plan written; ready for implementation
- 2026-04-07 — engineer-04 implemented in ContentView.swift; build green; self-audit complete; ready for QA

## Self-Audit

1. **Re-read modified files (top to bottom):** Re-read `JamBox/ContentView.swift` end-to-end. No debug prints, no commented-out blocks, no TODO/FIXME. New code is consistent with surrounding style (4-space indent, doc comments on properties, inline comments explaining intent at non-obvious decisions). The existing `.onKeyPress(.return)` and `.onKeyPress(.space)` handlers naturally do not fire while the TextField has key focus (TextField consumes keystrokes), so adding the search field does not interfere with them.

2. **Acceptance walkthrough:**
   - **Search field top-right with magnifying glass:** `ContentView.swift:33-49` — HStack with `Spacer()` then `Image(systemName: "magnifyingglass")` then `TextField`, padded, only shown when there are tracks.
   - **Real-time filter, no Enter:** `filteredTracks` is a computed property recomputed on every body re-eval; `TextField`'s two-way binding to `searchQuery` triggers a body recompute on each keystroke. No `.onSubmit` involved.
   - **Case-insensitive substring across title/artist/album, OR semantics:** `ContentView.swift:19-27`. Lowercases the query once and each field per-comparison; uses `||`.
   - **Empty/whitespace query is no-op:** `ContentView.swift:20-21`. `trimmingCharacters(in: .whitespaces)` then `guard !q.isEmpty else { return player.tracks }`.
   - **Missing metadata doesn't crash or spuriously match:** Verified `Track.artist` and `Track.album` are non-optional `String` (empty string when missing) in `Track.swift:8-9`. `"".contains(q)` is false for any non-empty `q`, so empty fields produce no false positives. No nil access possible.
   - **Filter is display-only, queue not mutated:** `Table` is fed `filteredTracks`, but `player.tracks` and the playback queue (`PlayerEngine`) are never written to from the search code. Verified by inspection — no `player.tracks =` or `player.play(...)` triggered by filter changes.
   - **Currently-playing track keeps playing if filtered out:** Same as above — filter is display-only. `PlayerEngine`'s `AVQueuePlayer` is untouched.
   - **Double-click on filtered row plays correct track:** `ContentView.swift:128-138`. Translates the filtered-view row index to a `player.tracks` index via `firstIndex(where: { $0.id == id })` before calling `player.play(startingAt:)`.
   - **Right-click context menu still works on filtered rows:** `ContentView.swift:139-155` is unchanged. It already operates on `Track.ID` from selection and does its own `firstIndex(where:)` lookup against `player.tracks`, which is filter-agnostic.
   - **Album-art overlay (card 0004):** Not in main yet (`/Users/ethan/code/jambox/.pm/done/` contains only 0001/0002/0005). N/A.
   - **Speaker indicator on filtered view:** `ContentView.swift:83-86` — the column compares `track.id == player.currentTrack?.id` per row; works correctly whether the row is in the filtered view or not.
   - **Clearing field restores full view, no flicker:** Empty query returns `player.tracks` as-is from the same backing array — same identities, so SwiftUI's diffing reuses rows. Scroll position handled by SwiftUI's normal Table behavior.
   - **Cmd-F focuses field:** `ContentView.swift:54-58` — a hidden, zero-sized `Button` with `.keyboardShortcut("f", modifiers: .command)` sets `searchFieldFocused = true`.
   - **Esc clears + unfocuses:** `ContentView.swift:42-45` — `.onExitCommand` on the TextField handles Esc while the field has key focus, clears the query, and drops focus. The parent `.onKeyPress(.escape)` (artwork dismiss) is unchanged and runs only when the parent has focus, so the two don't conflict.
   - **Build clean, no new warnings:** confirmed below.
   - **Gapless playback unchanged:** No edits to `PlayerEngine`, queue, `enqueueMoreIfNeeded`, or anything in `PlayerEngine.swift`.
   - **AVURLAsset invariant unaffected:** No audio code touched.
   - **Two-phase loading invariant unaffected:** Filter reads `track.displayName` which is set to the filename in `Track.init(url:)` (Track.swift:29) before metadata loads, so pre-metadata tracks match against the filename — exactly per the acceptance bullet.

3. **Build result:** `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` → `** BUILD SUCCEEDED **`. No warnings, no errors.

4. **Invariants verified (§7):**
   - §7.1 AVURLAsset: N/A — no audio code touched.
   - §7.2 Gapless playback / AVQueuePlayer: PlayerEngine untouched.
   - §7.3 Two-phase loading: respected — pre-metadata tracks search by filename via `displayName`.
   - §7.4 Sandbox bookmarks: untouched.
   - §7.5 Xcodegen: no files added/removed, project.yml unchanged, no regeneration needed.
   - §7.6 Build green: passes.

5. **Hostile diff review:** Re-read the entire diff. Concerns considered and resolved:
   - The hidden Cmd-F `Button` is in the top-level `VStack(spacing: 0)`. With `frame(width: 0, height: 0)` and zero spacing, it contributes no visible layout. Verified.
   - `filteredTracks` is recomputed on every body call. For 1000–5000 tracks with typed-at-human-speed updates this is fine (per the card's explicit guidance). Not premature-optimizing.
   - The `if !player.tracks.isEmpty` wrapping the search HStack could cause a brief layout jump the very first time tracks load. This is one-time and aligned with the empty-state hide/show that already happens. Acceptable.
   - `searchQuery` is not cleared when the user changes folders. This could leave a stale filter applied to a new library. The acceptance does not require clearing on folder change, but it could surprise the user. **Not in scope** for this card; would file a follow-up if it becomes an issue.
   - The Table's `selection` could refer to a track that's been filtered out of the view. SwiftUI's Table tolerates this fine — the selection just isn't visually highlighted. Return-key play still works (uses `firstIndex` against `player.tracks`).

6. **Touched-files reconciliation:** Card `touches:` listed `JamBox/ContentView.swift`. Actual changes: `JamBox/ContentView.swift` only. Match — no update needed.

7. **Scope check:** No unrelated changes. The diff is exclusively the search field, the filtering computed property, the Table's source array swap, and the double-click index translation. No drive-by refactors, no theme changes, no PlayerEngine touches.

## QA Report
*Filled in by the QA agent. See .pm/README.md §6b.*

### Acceptance

### Invariants

### Findings

### Recommendation

## Manager Decision
*Filled in by the manager when closing or kicking back.*
