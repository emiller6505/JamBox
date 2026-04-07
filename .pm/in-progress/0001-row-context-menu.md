---
id: 0001
title: Right-click context menu on song rows (Play, Show in Finder)
created: 2026-04-06
engineer: engineer-01
qa: null
parent: null
priority: P2
estimate: S
depends_on: []
touches:
  - JamBox/ContentView.swift
acceptance:
  - Right-clicking any row in the song table opens a native macOS context menu
  - Menu contains a "Play" item that begins playback of that specific track, behaving identically to a double-click on the row
  - Menu contains a "Show in Finder" item that reveals the track's underlying file in Finder, with the file selected inside its parent folder (use NSWorkspace.shared.activateFileViewerSelecting)
  - Existing double-click-to-play behavior on rows is unchanged
  - Right-clicking does not steal or alter the current row selection in a surprising way (follow whatever AppKit's NSTableView does by default for right-click — usually select-on-right-click if no current selection includes that row)
  - Multi-row selection behavior is OUT OF SCOPE for v1 — if the user has multiple rows selected and right-clicks, it is acceptable for the menu to operate on a single row only (the right-clicked row). Document this in the Plan.
  - No keyboard shortcuts added in this card (out of scope)
  - Build passes cleanly with no new warnings: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - No AVURLAsset construction is touched; if any audio code is incidentally modified, the AVURLAssetPreferPreciseDurationAndTimingKey invariant must still hold
  - Gapless playback behavior is unchanged (no PlayerEngine queue logic touched)
---

## Context

User-facing request from the human owner:

> "I want to be able to right-click a song in the song list and have a context menu pop up with the following options: play song, show in finder. show in finder should open the folder containing the file, and the file's properties can be edited through finder (not through our simple app)."

The intent is to give users a way to act on a track without leaving the keyboard-and-mouse flow they already use, and to expose the underlying file for any editing (tags, renaming, deletion) that JamBox itself does not support. This is explicitly a *minimal* feature — no inline editing, no extra menu items, no multi-select.

**Implementation orientation** (for the engineer — confirm or revise during plan mode):
- The song list lives in `ContentView.swift` around line 34: `Table(player.tracks, selection: $selection)`.
- Double-click is wired via the existing `.onTableDoubleClick { row in … }` modifier (line 82) which goes through `TableDoubleClick.swift`. The "Play" menu item should call the same play handler that double-click uses, not duplicate the logic.
- `Track` (`Track.swift`) exposes `url: URL` — that's what you pass to `NSWorkspace.shared.activateFileViewerSelecting([url])` for the Finder reveal.
- SwiftUI's `Table` supports `.contextMenu(forSelectionType:)` on macOS 14+, which gives you a closure receiving the set of selected ids for the right-clicked row(s). Prefer this over an AppKit bridge if it cleanly supports the single-row case.
- If `.contextMenu(forSelectionType:)` doesn't behave well (e.g. doesn't fire for unselected rows on right-click), fall back to attaching `.contextMenu { … }` to each cell view inside the `TableColumn` builders. Decide during plan mode and explain the tradeoff.

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

## Log
- 2026-04-06 — manager created card in ready/
- 2026-04-06 — engineer-01 claimed card, moved to in-progress/

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
