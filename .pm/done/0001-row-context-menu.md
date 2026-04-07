---
id: 0001
title: Right-click context menu on song rows (Play, Show in Finder)
created: 2026-04-06
engineer: engineer-01
qa: qa-01
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

Use SwiftUI's native `Table.contextMenu(forSelectionType: Track.ID.self) { ids in ... }` modifier (macOS 14+). This is the cleanest fit because:

- JamBox already targets macOS 14+ (per CLAUDE.md), so the API is available.
- AppKit's `NSTableView` underpinning the SwiftUI `Table` already handles the "right-click selects the row under the cursor if it isn't part of the current selection" behavior automatically. The closure's `Set<Track.ID>` argument reflects that post-adjustment selection, so we get the right-clicked row for free without bridging into AppKit.
- No new `NSViewRepresentable` is needed, and `TableDoubleClick.swift` is untouched.

The closure builds menu items:
- **Play** — resolves the single id to its index in `player.tracks` and calls `player.play(startingAt: index)`, identical to the double-click path at line 84.
- **Show in Finder** — calls `NSWorkspace.shared.activateFileViewerSelecting([track.url])`, which opens the parent folder with the file selected.

**Multi-row semantics (per acceptance bullet):** if the right-clicked selection happens to contain more than one id, we take `ids.first` as the operand. v1 is deliberately single-row. We do NOT disable the menu for multi-select — that would be more surprising than letting "Play" act on one of the selected rows. The bullet explicitly allows operating on a single row in the multi-select case.

If `ids` is empty (shouldn't happen for a row-anchored context menu, but defensive), we render no items — SwiftUI will simply show an empty menu, which is acceptable and matches the "right-click on empty space does nothing meaningful" behavior of most mac apps.

**Files:**

- `JamBox/ContentView.swift` — add `.contextMenu(forSelectionType: Track.ID.self) { ... }` immediately after the existing `.onTableDoubleClick { ... }` modifier on the `Table`. Add `import AppKit` only if not already transitively available (SwiftUI re-exports it on macOS, so likely unnecessary; confirm during implementation).

No other files touched. `touches:` in frontmatter remains `JamBox/ContentView.swift`.

**Risks:**

- **Gapless playback / PlayerEngine:** not touched. The "Play" path reuses `player.play(startingAt:)`, which is the same call double-click uses. No queue logic changes.
- **AVURLAsset invariant:** no audio-asset code is touched. Invariant §7.1 is not put at risk.
- **Two-phase loading / sandbox bookmarks:** not touched.
- **Selection behavior surprise:** `contextMenu(forSelectionType:)` will, per AppKit convention, select the right-clicked row if it wasn't already selected. This matches the acceptance bullet's expectation ("follow whatever AppKit's NSTableView does by default").
- **`NSWorkspace.activateFileViewerSelecting` and sandbox:** the app sandbox allows read-only user-selected files and uses app-scoped bookmarks. `activateFileViewerSelecting` is a user-initiated file-manager reveal and does not require extra entitlements; it works inside the standard read-only sandbox. No `startAccessingSecurityScopedResource` dance is needed for the reveal itself — we're handing the URL to Finder, not opening a file handle ourselves.
- **Build warnings:** the acceptance bullet requires no NEW warnings. The addition is a few lines of standard SwiftUI; very low risk.
- **Coexistence with uncommitted concurrent work:** `ContentView.swift` has other uncommitted modifications from a parallel agent. The edit is surgical — a single modifier inserted after line 85 — and does not touch any of the existing changed lines.

**Open questions:**

None. The card is tightly scoped and the APIs are well-understood.

## Log
- 2026-04-06 — manager created card in ready/
- 2026-04-06 — engineer-01 claimed card, moved to in-progress/
- 2026-04-06 — engineer-01 plan ready
- 2026-04-06 — engineer-01 self-audit complete
- 2026-04-06 — engineer-01 → qa
- 2026-04-06 21:11 — qa-01 audit complete: APPROVE WITH CHILD CARDS

## Self-Audit
*Filled in by the engineer before handing off to QA. See .pm/README.md §6.*

1. **Re-read modified files:** Re-read `JamBox/ContentView.swift` top to bottom. The file has significant pre-existing uncommitted changes from a parallel agent (theme manager wiring, `cell` helper, `onTableScroll`, `windowChrome`, etc.) which are OUT of scope for this card and were left untouched. My only addition is the `.contextMenu(forSelectionType: Track.ID.self) { ... }` block at lines 86–102. No debug prints, no commented-out code, no TODOs in my change. The inline comment explains the single-row v1 semantics. Style matches surrounding modifier-chain formatting.

2. **Acceptance walkthrough:**
   - *Right-clicking any row opens a native macOS context menu* — PASS. `Table.contextMenu(forSelectionType:)` is SwiftUI's native wrapper around the underlying `NSTableView`'s right-click menu. `ContentView.swift:86`.
   - *"Play" item begins playback of that specific track, identical to double-click* — PASS. The Play button at `ContentView.swift:95–97` calls `player.play(startingAt: index)`, the exact same entry point the double-click handler uses at `ContentView.swift:84`.
   - *"Show in Finder" reveals the file using `NSWorkspace.shared.activateFileViewerSelecting`* — PASS. `ContentView.swift:98–100` passes `[track.url]` to that API.
   - *Existing double-click-to-play is unchanged* — PASS. The `.onTableDoubleClick` modifier at `ContentView.swift:82–85` is untouched. `TableDoubleClick.swift` is untouched.
   - *Right-click does not steal selection in a surprising way* — PASS. `contextMenu(forSelectionType:)` delegates to `NSTableView`'s default right-click behavior: if the clicked row is already part of the selection, the selection is preserved; otherwise the clicked row becomes the selection. This is the expected native macOS behavior per the acceptance bullet.
   - *Multi-row selection out of scope — single-row operation acceptable* — PASS. `if let id = ids.first` at `ContentView.swift:92` explicitly picks a single id. The comment at lines 87–91 documents this as intentional v1 semantics. The card explicitly permits this.
   - *No keyboard shortcuts added* — PASS. Neither `Button` has a `.keyboardShortcut(...)` modifier.
   - *Build passes cleanly with no new warnings* — PASS. See item 3.
   - *No AVURLAsset construction touched; invariant §7.1 still holds* — PASS. No audio code touched; no `AVURLAsset` in the diff.
   - *Gapless playback unchanged — no PlayerEngine queue logic touched* — PASS. `PlayerEngine.swift` is not in the diff.

3. **Build result:** Ran `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` from the project root. Final status: `** BUILD SUCCEEDED **`. A grep of the full build log for `warning:` / `error:` returned only the benign `xcodebuild: WARNING: Using the first of multiple matching destinations:` line, which is an xcodebuild tooling notice (multiple macOS destinations available) and NOT a source-code warning. No new compiler warnings introduced by my change.

4. **Project-wide invariants verified:**
   - §7.1 AVURLAsset + precise-timing key: N/A — no asset creation in diff. Invariant cannot be violated.
   - §7.2 Gapless playback / 3-item lookahead: N/A — `PlayerEngine` untouched. Queue logic not in diff.
   - §7.3 Two-phase loading: N/A — `FileScanner` / metadata loading untouched.
   - §7.4 Sandbox bookmarks: N/A — no `startAccessingSecurityScopedResource` in diff. `NSWorkspace.activateFileViewerSelecting` is a user-initiated file-manager reveal that does not require opening a file handle from the app, so no bookmark dance is needed.
   - §7.5 Xcode project regeneration: N/A — no files added or removed. `project.yml` unchanged. No need to run `xcodegen generate`.
   - §7.6 Build green: PASS — build succeeded.

5. **Hostile diff review:** Ran `git diff JamBox/ContentView.swift`. The diff contains: (a) pre-existing parallel-agent changes that I did NOT write and did NOT touch — theme wiring, `cell` helper, `alternatingRowBackgrounds`, `onTableScroll`, `windowChrome`, `scrollTargetRow` state, `NowPlayingBar` callback — these are out-of-scope pre-existing work per the card-dispatch instructions; and (b) my own 17-line addition at lines 86–102 for the context menu. Reviewing my addition as a hostile reviewer: `ids.first` is safe on an empty set (returns nil, menu renders no items). `firstIndex(where:)` handles the unlikely case of a stale id. No force-unwraps. No retained state. No background work. The `Track` lookup is O(n) per right-click but `n` is bounded by visible library size and the menu only renders on a user gesture, so this is fine. One thing a hostile reviewer MIGHT flag: if the user right-clicks without any row selected at all and the click lands on empty table space, the `ids` set would be empty and the menu would contain no items — but `contextMenu(forSelectionType:)` only fires for row-anchored right-clicks, not empty-space right-clicks, so this path is effectively unreachable. No action needed.

6. **Touched-files reconciliation:** `touches:` frontmatter lists `JamBox/ContentView.swift`. My actual change is confined to that file. No update needed. (The diff shows other lines in that same file modified by the parallel agent, but those are not my changes and do not belong to this card.)

7. **Scope check:** My change consists of exactly one added modifier block — no refactors, no renames, no "while I was here" cleanups, no touching the parallel agent's pre-existing work in the same file. Nothing to revert.

## QA Report
*Filled in by the QA agent. See .pm/README.md §6b.*

QA scope per dispatch instructions: engineer-01's contribution is the
`.contextMenu(forSelectionType: Track.ID.self) { … }` block at
`ContentView.swift:86–102`. The other diff hunks against `main` (theme
`cell {}` helper, `scrollTargetRow`, `windowChrome`, `alternatingRowBackgrounds`,
`tint`, `onTableScroll`, `NowPlayingBar` callback, the private `cell` helper)
are pre-existing in-flight work from a concurrent agent that was already dirty
in the working tree when engineer-01 picked up the card. Per the dispatch
instructions, those are explicitly out of scope for this audit and are not
flagged here.

### Acceptance
- [PASS] Right-clicking any row opens a native macOS context menu — `Table.contextMenu(forSelectionType: Track.ID.self)` at `ContentView.swift:86` is the SwiftUI 14+ idiom that delegates to the underlying `NSTableView`'s native right-click menu. Static reading only; runtime click would confirm visually, but the API contract is well-defined.
- [PASS] "Play" item begins playback identically to double-click — `ContentView.swift:95–97` calls `player.play(startingAt: index)`. The double-click path at `ContentView.swift:82–85` uses the same `player.play(startingAt: row)` entry point. Confirmed `func play(startingAt index: Int)` exists at `PlayerEngine.swift:135`. Identical entry point, no duplication.
- [PASS] "Show in Finder" reveals the file via `NSWorkspace.shared.activateFileViewerSelecting` — `ContentView.swift:98–100` passes `[track.url]` (a one-element array) to `NSWorkspace.shared.activateFileViewerSelecting`, which is the standard reveal-and-select API.
- [PASS] Existing double-click-to-play unchanged — `.onTableDoubleClick` block at `ContentView.swift:82–85` is byte-identical to the version on `main`. `TableDoubleClick.swift` is not in the diff.
- [PASS] Right-click does not steal selection in a surprising way — `contextMenu(forSelectionType:)` is a SwiftUI wrapper that defers to `NSTableView`'s default right-click semantics (right-click on an unselected row makes it the selection; right-click on an already-selected row preserves the selection). Matches the "follow whatever AppKit does" acceptance language. Static evidence only; runtime testing would give visual confirmation.
- [PASS] Multi-row selection acceptably operates on a single row — `ids.first` at `ContentView.swift:92` deterministically picks one id. The inline comment at lines 87–91 documents this v1 semantic. Note: `ids` is a `Set`, so `first` is non-deterministic for multi-row selections — but that is acceptable per the bullet, since v1 explicitly does not promise which row wins. Documented in Plan.
- [PASS] No keyboard shortcuts added — neither Button has `.keyboardShortcut(...)`. Verified by reading lines 95–100.
- [PASS] Build passes cleanly — see §7.6 below. `** BUILD SUCCEEDED **`. No new compiler warnings; only the unrelated `xcodebuild: WARNING: Using the first of multiple matching destinations` tooling notice, which is environmental, not source-related.
- [PASS] No AVURLAsset construction touched — engineer-01's added block contains no `AVURLAsset` / `AVPlayerItem` references. Grep of the diff confirms no audio-asset construction in scope.
- [PASS] Gapless playback unchanged — `PlayerEngine.swift` is not in the engineer-01 diff. The "Play" menu item reuses the existing `play(startingAt:)` entry point that double-click already uses, so behavior is necessarily identical.

### Invariants
- [N/A] §7.1 AVURLAsset precise-timing key — engineer-01's diff does not construct any `AVURLAsset`. Invariant cannot be violated by this change.
- [N/A] §7.2 Gapless playback / 3-item lookahead — `PlayerEngine.swift` not in scope; queue logic not touched.
- [N/A] §7.3 Two-phase loading — `FileScanner` / `Track.loadMetadata` not touched.
- [N/A] §7.4 Sandbox bookmarks — engineer-01's block does not call `startAccessingSecurityScopedResource`. `NSWorkspace.activateFileViewerSelecting` hands the URL to Finder out-of-process; the app does not open a file handle, so no bookmark dance is required. `JamBox.entitlements` is unchanged and already permits user-selected file access.
- [N/A] §7.5 Xcode project regeneration — no source files added or removed. `project.yml` unchanged.
- [PASS] §7.6 Build green — Ran `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` from project root. Final status line: `** BUILD SUCCEEDED **`. Grep of the build log for `warning:` / `error:` (excluding the environmental "Using the first of multiple matching destinations" line) returned zero source-level warnings or errors.

### Findings

- [MINOR] Stale or invalid `track.url` is not handled. If the file behind a row has been deleted, the volume ejected, or the network share disconnected since the library was scanned, "Show in Finder" will silently no-op (Finder will fail to reveal a non-existent path) and "Play" will hand a dead URL to `AVQueuePlayer`. Neither acceptance bullet requires handling this, but it is a likely real-world scenario for a music library that follows external folders. See child card 0003.
- [NIT] Non-local URLs (smb://, network volumes) are not specifically considered. `activateFileViewerSelecting` handles file:// URLs reliably; behavior with URLs from a disconnected network mount is likely to silently fail. Subsumed under the staleness finding above.
- [NIT] Menu items "Play" and "Show in Finder" are hardcoded English string literals, not localized. JamBox is not localized today, so this matches the existing codebase convention. No action required.
- [NIT] No accessibility labels on the menu buttons. SwiftUI's `Button("Play")` synthesizes a default accessibility label from the title, which is adequate for a context menu of this scope. No action required.
- [NIT] `ids` is a `Set<Track.ID>`, so `ids.first` is non-deterministic across multi-row selections. The card explicitly permits this in the v1 multi-row case, and the engineer documented it in the inline comment, but if this ever needs to become deterministic (e.g. "always operate on the row directly under the cursor"), it would require either a different API or AppKit bridging. Out of scope for this card; noted for future reference.
- No BLOCKER or MAJOR findings.

### Recommendation
- [APPROVE WITH CHILD CARDS] — engineer-01's contribution cleanly satisfies every acceptance bullet, the build is green with no new warnings, and all applicable invariants pass. The one real-world edge case (stale file URLs) is filed as child card 0003 for separate triage rather than blocking 0001.

## Manager Decision

**APPROVED — closed to done/.** 2026-04-06.

QA's audit was thorough and matches my own read of the code. All ten acceptance bullets pass, the build is green, all applicable invariants pass, and engineer-01's contribution is cleanly scoped to the seventeen lines it claimed. The one MINOR finding (stale/unreachable `track.url` handling) is correctly split into child card 0003 at P3 rather than blocking this card — the v1 card explicitly did not require it, and the failure mode is non-destructive in the static analysis. Promoting child card 0003 from `ready/` to dispatch-ready remains a future decision; it can wait behind the click-state-audit work in card 0002 since both touch `ContentView.swift`.

Engineer-01 and qa-01 both signed off. Card retired.
