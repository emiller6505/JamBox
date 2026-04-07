---
id: 0002
title: Audit & fix song-table clicking/focus state machine
created: 2026-04-06
engineer: engineer-02
qa: null
parent: null
priority: P1
estimate: L
depends_on: [0001]
touches:
  - JamBox/ContentView.swift
  - JamBox/TableDoubleClick.swift
  - JamBox/PlayerEngine.swift
acceptance:
  - Root cause of the focus-flicker bug is identified and documented in the Plan section with a clear explanation of the failing state transition
  - Reliable repro steps for the focus-flicker bug are documented (or, if the bug is genuinely intermittent, the conditions that increase its likelihood are documented along with the investigation that ruled out a deterministic trigger)
  - After the fix, single-clicking a row to select it works reliably the first time, every time, immediately after the JamBox window regains focus from any other app or window
  - After the fix, right-clicking a row (including via two-finger trackpad click) reliably opens the context menu added in card 0001, including immediately after a focus change
  - Double-click-to-play continues to work in all the same conditions
  - The fix does not regress keyboard navigation of the song table (arrow keys, return, etc. — verify whatever currently works still works)
  - Selection state is consistent across mouse, keyboard, and right-click interactions — there are no states where the visual selection disagrees with the underlying `selection` binding
  - All findings from the clicking-state audit (even ones not part of the immediate fix) are written into a Findings section in the card so future cards can pick up follow-up work
  - Build passes cleanly with no new warnings: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - AVURLAsset invariant unaffected
  - Gapless playback unaffected (no PlayerEngine queue logic touched unless rigorously justified)
---

## Context

Two reported symptoms from the human owner, recorded verbatim:

> "right clicking doesn't work. there's also a bug (which has been there for a while) where sometimes when I focus a different window, then come back to jambox, when I try to click on a track it doesn't stick. like it flickers to the track I wanted to click, then back to the previously clicked track. and right-clicks (two finger click on mac touchpad) not working at all."

**Manager's interpretation** (engineer should confirm during plan mode):

1. The "right-click doesn't work" line refers to JamBox's current state *before* card 0001 lands. Card 0001 adds the right-click context menu. This audit card depends on 0001 being merged first, then verifies that right-click works *robustly across focus states*, not just in the happy path.

2. The "click flicker" bug is the longstanding one and is the heart of this card. Symptom: a single-click on a row visually selects the intended row for a frame and then snaps back to the previously-selected row.

### UPDATED SYMPTOMS (manager edit, post-claim, before re-dispatch)

After the original card was written, the user reported additional details that significantly broaden the picture:

> "the clicking thing happens not just when focusing to other windows and back. it also happens after scrolling and then clicking different tracks. usually every third click or so fails and has to be retried to actually 'stick.'"

> "it's very inconsistent though so it's annoying to try and repro. not sure what's going on."

**What this changes:**

- The bug is **not gated on window-focus changes alone.** Focus-return is *one* trigger, but **scrolling-then-clicking is another** — and based on the "every third click" observation, the failure rate during normal use is roughly 1 in 3 clicks. That's frequent. Far more frequent than a focus-change-only bug would be.
- Both triggers (focus return, post-scroll click) point at something that mutates state during/after the user gesture and clobbers the `selection` binding before the click "lands." The shared element across both triggers is plausibly **scroll-position state and/or some `@Published` property writing back into a parent view, forcing a Table identity refresh that drops in-flight selection.**
- This significantly **raises suspicion on `JamBox/TableScroller.swift`**, which is brand-new. Read it carefully — if it observes scroll position via an `NSScrollView` notification or coordinator and writes it into a SwiftUI `@State` or `@Binding` on every event, that write will trigger a parent re-render, which can race with a click in progress. This is a classic SwiftUI Table footgun.
- It also raises suspicion on **anything that publishes from `PlayerEngine` at a regular interval** — there is a 4Hz periodic time observer for the scrub bar (per CLAUDE.md). If that observer writes into a property that the `ContentView` body reads (directly or transitively), every tick at 4Hz triggers a body re-eval, which on a Table can cancel an in-progress mouse interaction. **This is now the leading hypothesis** because it would naturally produce an "every third click" failure rate (clicks landing in the gap between ticks succeed; clicks landing during a tick fail).

### Revised hypotheses (the engineer should still generate their own)

1. **4Hz periodic time observer in `PlayerEngine` writes into a published property that `ContentView` observes**, causing the whole Table to re-render mid-click on every tick. Failure rate would correlate with tick rate. This is the new leading candidate.
2. **`TableScroller.swift` writes scroll position into a SwiftUI binding on every scroll event**, causing a parent re-render that races with the click. Would explain the "after scrolling" trigger specifically.
3. **A `@Published` property on `AppModel` or `ThemeManager` is being written from somewhere that fires on focus return AND on scroll** (e.g. window-key state, or a derived value that recomputes on view geometry changes).
4. **The `Table`'s `selection: $selection` binding is being reset by something downstream** — find what writes to `selection` other than user clicks.
5. **First-mouse / first-responder semantics** for the focus-return case specifically (still possible for the focus-return trigger, but does NOT explain the post-scroll trigger).

### Investigation suggestion

The most efficient first move is probably **search for every `@Published` property in `PlayerEngine`, `AppModel`, `ThemeManager`, and any helper that the `ContentView` body transitively reads, and identify which of them tick at a high rate.** Anything ticking faster than human input is a suspect for "click cancelled by re-render." Then confirm by reading the body of the periodic time observer in `PlayerEngine` and tracing what it writes to.

If the leading hypothesis pans out, the fix is likely to **pull the high-frequency state into a child view that isolates re-renders away from the Table**, or to **make the Table's parent view's body not read the high-frequency property**, or to **debounce/throttle the publish**. Choose at the right architectural layer — don't whack-a-mole.

**This card is intentionally an investigation, not a narrowly-scoped bug fix.** The acceptance demands a root-cause writeup, not just a patch that makes the symptom go away. We do not want to whack-a-mole this — we want to understand the click/focus/selection state machine end-to-end and fix it at the right layer.

### Where to start looking (engineer to confirm or revise during plan mode)

- `JamBox/ContentView.swift` — the `Table(player.tracks, selection: $selection)` and surrounding modifiers including the recent uncommitted theme/scrolling changes. The `selection` binding is the prime suspect for the flicker.
- `JamBox/TableDoubleClick.swift` — the `NSViewRepresentable` that reaches into AppKit to wire `doubleAction` on the underlying `NSTableView`. AppKit `NSTableView` and SwiftUI `Table.selection` are two state machines that have to stay in sync; bridges between them are notorious for first-responder/selection bugs.
- Whatever code path handles window-focus changes (search for `windowDidBecomeKey`, `NSWindow.didBecomeKeyNotification`, scene phase, `@Environment(\.scenePhase)`, etc.).
- The recently-added `WindowAccessor.swift` (untracked, from another agent) — read it but **do not modify it**. It may be relevant to focus handling.
- The recently-added `TableScroller.swift` (untracked, from another agent) — read it but **do not modify it**. It may be intercepting events on the table.

### Hypotheses to investigate (not exhaustive — find your own too)

- The `selection` binding is being written twice on focus return: once by AppKit's first-mouse handling and once by SwiftUI's gesture system, with the AppKit write losing the race.
- "First mouse" / `acceptsFirstMouse` behavior on the `NSTableView` may be off, causing the click that brings the window to front to be consumed by the focus change, then a synthesized second event reverts the selection.
- A two-way binding to `player.tracks` selection is being clobbered by an unrelated state update happening on focus return (e.g. a metadata refresh, an FSEvents-driven track list rebuild from `FolderWatcher`).
- The right-click flow (from card 0001) interacts badly with the focus state because right-click on a non-key window has different first-responder semantics.

These are just starting points — the engineer is expected to actually instrument and verify, not pattern-match to the most likely-sounding hypothesis.

### Why P1 and Large

P1 because clicking is the single most fundamental interaction in the app — every other feature depends on it working. Large because root-causing a state-machine bug across the SwiftUI/AppKit boundary is genuinely hard work and will involve real debugging, not just code reading. Do not let the engineer rush this.

### Manager dispatch note (not for the engineer)

This card is in `backlog/`, NOT `ready/`. Do not dispatch it until card 0001 is in `done/`. The two cards have heavy file overlap on `ContentView.swift` and would collide. After 0001 closes, re-read the symptoms with the user to confirm they still reproduce post-0001, then promote to `ready/`.

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

## Log
- 2026-04-06 — manager created card in backlog/, blocked on 0001
- 2026-04-06 — manager promoted to ready/ after card 0001 closed; ready for engineer dispatch
- 2026-04-06 — engineer-02 claimed
- 2026-04-06 — manager stopped engineer-02 mid-startup to incorporate new user-reported symptoms (post-scroll trigger, ~1-in-3 failure rate); Context section updated; respawning fresh engineer-02

## Self-Audit
*Filled in by the engineer before handing off to QA. See .pm/README.md §6.*

1. Re-read modified files:
2. Acceptance walkthrough:
3. Build result:
4. Invariants verified:
5. Hostile diff review:
6. Touched-files reconciliation:
7. Scope check:

## Findings
*Filled in by the engineer during the audit. Anything observed that isn't part of the immediate fix but should be tracked as a follow-up card.*

## QA Report
*Filled in by the QA agent. See .pm/README.md §6b.*

### Acceptance

### Invariants

### Findings

### Recommendation

## Manager Decision
*Filled in by the manager when closing or kicking back.*
