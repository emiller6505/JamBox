---
id: 0008
title: Add search filter input to filter visible tracks by title/artist/album
created: 2026-04-07
engineer: null
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
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

## Log
- 2026-04-07 — manager created card from user request

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
