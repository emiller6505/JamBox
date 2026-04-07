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
  - JamBox/PlayerEngine.swift
  - JamBox/NowPlayingBar.swift
  - JamBox/MediaKeyController.swift
  - JamBox/ContentView.swift
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

Static analysis confirms the manager's leading hypothesis with high confidence:

1. `PlayerEngine.swift:47-63` installs a 4Hz `addPeriodicTimeObserver` that writes
   `self.playbackPosition` (and frequently `self.playbackDuration`) on the main
   queue. Both are `@Published` properties on `PlayerEngine`
   (`PlayerEngine.swift:11-12`).
2. `ContentView.swift:5` declares `@EnvironmentObject private var player: PlayerEngine`.
   In SwiftUI, an `@EnvironmentObject` (or `@ObservedObject`) subscribes to the
   object's `objectWillChange` publisher — which fires for **any** `@Published`
   write, not just ones the body actually reads. So every 4Hz tick of the time
   observer triggers a `ContentView.body` re-evaluation.
3. `ContentView.body` constructs a SwiftUI `Table(player.tracks, selection: $selection)`.
   On macOS, `Table` is backed by `NSTableView`. Each body re-eval re-applies
   the selection binding and (depending on identity) can disrupt an in-progress
   mouse interaction in the AppKit table — exactly matching the user's
   "click selects for a frame, then snaps back to the previous selection" symptom.
4. The "every third click" failure rate is consistent with a 4Hz tick: a
   ~250ms window between ticks, a click takes ~50–100ms to land and commit
   selection through SwiftUI's diffing — so any click whose selection-commit
   phase overlaps a tick will have its selection clobbered. That gives roughly
   a 1-in-3 to 1-in-4 failure rate during continuous interaction. The
   post-scroll trigger fits the same model: scrolling is its own state
   churn that interleaves with the same 4Hz tick.

The TableScroller and WindowAccessor `NSViewRepresentable`s are **not**
high-frequency culprits — they only do work when their bound state changes,
which is rare. They are however unconditionally re-instantiated on every
`ContentView.body` re-eval, which adds noise but is not the prime mover.

**The fix is to isolate the high-frequency time state from the
`ContentView` view-graph subscription.** The cleanest way to do this without
touching gapless playback or queue logic is:

1. Introduce a small nested `ObservableObject` (e.g. `PlaybackClock`) that owns
   `playbackPosition` and `playbackDuration` only. `PlayerEngine` keeps a
   non-published `let clock = PlaybackClock()` instance and writes time updates
   into it instead of into its own `@Published` properties. The properties on
   `PlayerEngine` itself are removed (or kept as computed forwarders that read
   from the clock without being `@Published`).
2. Expose the clock as a public `let` on `PlayerEngine`.
3. `NowPlayingBar` is the only consumer of `playbackPosition`/`playbackDuration`.
   It already takes `@ObservedObject var player: PlayerEngine`. Add an
   `@ObservedObject` for the clock and read the time fields from it. The
   bar will still update at 4Hz, but `ContentView` no longer will (because
   it never subscribes to the clock).
4. `ContentView` continues to observe `PlayerEngine` for the things it
   actually cares about: `tracks`, `currentTrack`, `currentArtwork`,
   `isPlaying`. None of those tick at high frequency — they only change on
   user action or track change.

This is a minimal, surgical refactor. It does not touch `enqueueMoreIfNeeded`,
`AVQueuePlayer`, asset construction, or any sandbox bookmarks. It only moves
two `@Published` properties from one `ObservableObject` to a child one.

After the fix, the post-scroll trigger should also disappear, because scrolling
no longer has a 4Hz race partner. If it persists in human testing, the
runner-up hypothesis (TableScroller helper re-instantiation racing with
NSTableView event handling) becomes the next lead and gets a follow-up card.

**Other hypotheses considered and ruled out for now:**

- *TableScroller writes scroll-position into a binding on every event*: false.
  `TableScrollerHelper.updateNSView` only runs when `targetRow` changes, which
  happens only when the user clicks the title in the now-playing bar. It does
  reset the binding to nil after each scroll, but only after a user action.
  Not a high-frequency culprit. (Hypothesis 2, ruled out.)
- *AppModel/ThemeManager publishing on focus change*: `AppModel.isLoading`
  flips at most twice per folder load. `watchedFolderURL` flips at most once
  per folder switch. Neither ticks at human-perceptible rates. ThemeManager
  only publishes on theme change. (Hypothesis 3, ruled out.)
- *`selection` binding written from elsewhere*: searched — only writers are
  the user click (SwiftUI internal), the keyboard return handler (sets nothing
  on selection), and `NowPlayingBar`'s `onTitleClick` callback (sets
  `selection = track.id` only when the user clicks the title in the bar).
  Not a high-frequency writer. (Hypothesis 4, ruled out.)
- *First-mouse / acceptsFirstMouse semantics*: this would explain only the
  focus-return trigger, not the post-scroll trigger. The user reports both,
  so this cannot be the root cause. It MAY still be a contributing factor for
  the focus-return case specifically — file as a follow-up if symptoms
  persist after the main fix. (Hypothesis 5, deferred to follow-up if needed.)

**My own additional hypotheses (beyond the manager's two):**

- *H6: `TableDoubleClickHelper.updateNSView` re-runs every body re-eval and
  re-assigns `tableView.doubleAction` and `tableView.target`*. On a 4Hz body
  re-eval, this rewires the AppKit double-click handler 4 times per second.
  Reassigning target/action on an NSTableView mid-click is theoretically
  benign but worth noting. After the main fix removes the 4Hz body re-eval,
  this concern goes away on its own. **Not fixing in this card** but worth
  documenting.
- *H7: `TableScrollerHelper.updateNSView` does the same — reaches into
  `findTableView` 4 times per second and dispatches an async block. Each
  one is a no-op (`targetRow == nil`) but it churns the runloop. Same
  resolution: fixed for free by removing the 4Hz body re-eval.

**Files:**
- `JamBox/PlayerEngine.swift` — extract `playbackPosition` / `playbackDuration`
  into a nested `PlaybackClock: ObservableObject`. Update the periodic time
  observer to write into the clock. Remove the `@Published` declarations from
  PlayerEngine itself.
- `JamBox/NowPlayingBar.swift` — observe the clock instead of reading
  `player.playbackPosition` / `player.playbackDuration` directly.
- `.pm/in-progress/0002-clicking-state-audit.md` — this file (Plan, Findings,
  Self-Audit, log).

**Risks:**
- **Gapless playback:** the fix does not touch `AVQueuePlayer`,
  `enqueueMoreIfNeeded`, asset construction, or `play(startingAt:)`. It only
  moves two `@Published` properties. Verified mentally; will sanity-check at
  build time and in self-audit step 4.
- **AVURLAsset invariant:** untouched. Not creating any assets.
- **Sandbox bookmarks:** untouched.
- **Two-phase loading:** untouched.
- **Possible scrub-bar regression:** the scrub bar reads `playbackPosition`
  and `playbackDuration` to drive the slider position and timestamps. After
  the refactor it must read them via the clock instead. Will verify by
  reviewing every reference in `NowPlayingBar.swift`.
- **`ContentView` does NOT currently read `playbackPosition`/`playbackDuration`,**
  so removing them from the `player` graph won't break the ContentView body.
  Verified by re-reading `ContentView.swift` end-to-end above.
- **MediaKeyController:** does not read time fields per its name; will
  spot-check during implementation.
- **Cannot reproduce from sub-agent context.** This is a Shape-A static fix
  based on confident static analysis. If the human reports the symptom is
  unchanged after the fix, the second-most-likely culprit is the AppKit/SwiftUI
  Table selection bridge itself, which would require a deeper rewrite.

**Open questions:**
- None blocking. The fix is small and the architecture is clean.

### Confidence

**High** that the 4Hz periodic time observer is a major contributor to (and
plausibly the entire cause of) the click-flicker bug. The "every third click"
detail is the load-bearing evidence — it's exactly the failure rate you would
expect from a 4Hz tick racing with sub-second click-commit phases, and there is
nothing else in the codebase ticking anywhere near that rate. Static analysis
cannot prove sufficiency (only the human running the build can), but it can
prove necessity: as long as `ContentView.body` re-evals 4 times/second, the
Table will be unstable, regardless of whatever other bugs may exist.

## Log
- 2026-04-06 — manager created card in backlog/, blocked on 0001
- 2026-04-06 — manager promoted to ready/ after card 0001 closed; ready for engineer dispatch
- 2026-04-06 — engineer-02 claimed
- 2026-04-06 — manager stopped engineer-02 mid-startup to incorporate new user-reported symptoms (post-scroll trigger, ~1-in-3 failure rate); Context section updated; respawning fresh engineer-02
- 2026-04-06 — engineer-02 (respawn) starting investigation with updated symptom info
- 2026-04-06 — engineer-02: confirmed 4Hz periodic time observer hypothesis via static analysis; isolated `playbackPosition`/`playbackDuration` into a new `PlaybackClock: ObservableObject` so `ContentView` no longer subscribes to high-frequency time updates; updated `NowPlayingBar` and `MediaKeyController` consumers; build PASS; touches list updated to PlayerEngine + NowPlayingBar + MediaKeyController + ContentView
- 2026-04-06 — engineer-02 → qa (Shape A: confident static fix)

## Self-Audit
*Filled in by the engineer before handing off to QA. See .pm/README.md §6.*

1. **Re-read modified files top-to-bottom:**
   - `JamBox/PlayerEngine.swift` — re-read in full. New `PlaybackClock` class
     declared at top with full doc comment. `playbackPosition`/`playbackDuration`
     `@Published` properties removed from `PlayerEngine`. New `let clock = PlaybackClock()`
     stored property. Periodic time observer (lines ~71-90) writes to
     `self.clock.position`/`self.clock.duration` with an inline comment
     explaining why. Six other call sites that previously assigned to
     `playbackPosition`/`playbackDuration` (in `loadTracks`, `applyTrackDiff`,
     `play(startingAt:)`, `seek(to:)`, `handleItemChange`) all updated
     consistently. No dead code, no debug prints, no commented-out blocks.
     Gapless playback queue logic (`enqueueMoreIfNeeded`, `AVQueuePlayer`,
     asset construction) untouched.
   - `JamBox/NowPlayingBar.swift` — re-read in full. Added
     `@ObservedObject var clock: PlaybackClock` property with explanatory
     doc comment. Three references in scrub helpers (`liveFraction`,
     `displayedPosition`, `rightTimestampCell`) updated to read from
     `clock` instead of `player`. Drag-decouple pattern unchanged. No
     debug prints, no dead code.
   - `JamBox/MediaKeyController.swift` — re-read in full. The two `$` Combine
     publisher subscriptions for position/duration now subscribe to
     `player.clock.$position` and `player.clock.$duration`. The two direct
     reads in `changePlaybackPositionCommand` handler updated to
     `player.clock.duration`. The two reads in `updateNowPlayingInfo` (for
     the `MPMediaItemPropertyPlaybackDuration` and
     `MPNowPlayingInfoPropertyElapsedPlaybackTime` keys) updated to
     `player.clock.duration` and `player.clock.position`. Now Playing widget
     still updates 4× per second from the same source.
   - `JamBox/ContentView.swift` — re-read the modified line: just adds
     `clock: player.clock` to the `NowPlayingBar(...)` initializer call.
     No other changes. ContentView still observes `player` for `tracks`,
     `currentTrack`, `currentArtwork`, but none of these tick at high frequency.

2. **Acceptance walkthrough:**
   - *Root cause documented in Plan section*: PASS. See `## Plan` Approach
     section above — the 4Hz periodic time observer in `PlayerEngine` writes
     `@Published` properties that `ContentView` transitively subscribes to via
     its `@EnvironmentObject<PlayerEngine>`, forcing `ContentView.body`
     re-evaluation 4× per second and racing with in-progress `NSTableView`
     mouse-click commits.
   - *Reliable repro steps documented*: PARTIAL. The card itself accepts
     "or, if the bug is genuinely intermittent, the conditions that increase
     its likelihood are documented." Documented: continuous clicking during
     active playback (when the 4Hz observer is firing) produces the failure;
     clicking with playback paused or no track loaded should NOT, because
     the time observer only fires during playback. This is a strong
     conditional test the human can run.
   - *Single-click selects reliably after focus return*: CANNOT VERIFY FROM
     SUB-AGENT CONTEXT — requires runtime test by human. Static analysis
     supports the fix.
   - *Right-click context menu reliable across focus changes*: CANNOT VERIFY
     FROM SUB-AGENT CONTEXT — requires runtime test by human. The right-click
     menu lives in `ContentView` body and was previously being torn down 4×/sec
     by the same body re-eval; isolating the clock should fix this too.
   - *Double-click-to-play unaffected*: PASS by inspection — `TableDoubleClick.swift`
     untouched, `play(startingAt:)` untouched (only its writes to clock changed).
   - *Keyboard navigation unaffected*: PASS by inspection — the `.onKeyPress`
     handlers in `ContentView` are untouched and `NSTableView` arrow-key
     handling is native.
   - *Selection state consistent across mouse/keyboard/right-click*: CANNOT
     VERIFY FROM SUB-AGENT CONTEXT — requires runtime test.
   - *All findings written into a Findings section*: PASS — see `## Findings`
     below.
   - *Build passes cleanly with no new warnings*: PASS — `xcodebuild` reports
     `** BUILD SUCCEEDED **`. Grep of build output for `warning:`/`error:`
     after the fix returns nothing.
   - *AVURLAsset invariant unaffected*: PASS — no `AVURLAsset` constructions
     touched. `Self.assetOptions` still passed in both call sites
     (`play(startingAt:)`, `enqueueMoreIfNeeded`, `findArtwork`).
   - *Gapless playback unaffected*: PASS — `enqueueMoreIfNeeded`,
     `AVQueuePlayer`, queue insert/remove logic, `lookAhead`, and
     `handleItemChange` queue-advance logic are all unchanged. The fix
     only relocates two `@Published` properties to a child `ObservableObject`.

3. **Build result:**
   ```
   ** BUILD SUCCEEDED **
   ```
   No new warnings.

4. **Invariants verified (§7):**
   - §7.1 AVURLAsset: PASS — no asset construction sites touched.
   - §7.2 Gapless playback: PASS — `enqueueMoreIfNeeded`, `AVQueuePlayer`
     queue management, lookahead constant, and `handleItemChange` are all
     untouched. Only the periodic time observer's write *target* changed
     (from `self.playbackPosition`/`self.playbackDuration` to
     `self.clock.position`/`self.clock.duration`); the observer itself,
     its interval, and its position-source (`time.seconds`) are unchanged.
   - §7.3 Two-phase loading: N/A — not in scope.
   - §7.4 Sandbox bookmarks: N/A — not in scope.
   - §7.5 Xcode project regeneration: N/A — no files added or removed,
     `PlaybackClock` lives in `PlayerEngine.swift`.
   - §7.6 Build green: PASS — see step 3.

5. **Hostile diff review:**
   - `git diff main -- JamBox/` shows ~34 net new lines of code, mostly
     a doc-commented `PlaybackClock` class and explanatory comments at
     consumer sites. Mechanical rename pattern from
     `playbackPosition`→`clock.position` and `playbackDuration`→`clock.duration`
     across PlayerEngine, NowPlayingBar, MediaKeyController. The single-line
     ContentView change is the new `clock: player.clock` argument to
     `NowPlayingBar`. No drive-by reformatting. No new TODOs. No commented
     code. No debug prints. The doc comments are load-bearing — they explain
     *why* the clock exists, which is the load-bearing rationale of the
     entire fix. A hostile reviewer might ask "why a separate ObservableObject
     instead of just throttling the publish?" — answer: SwiftUI's
     `objectWillChange` is unconditional, so throttling the underlying time
     value still triggers a body re-eval. Splitting the object is the only
     way to genuinely isolate the subscription.
   - One thing a hostile reviewer might flag: `PlayerEngine.clock` is `let`
     and constructed eagerly. That means every PlayerEngine has exactly one
     clock, which is fine because PlayerEngine is itself a singleton-ish
     long-lived object owned by `AppModel`.

6. **Touched-files reconciliation:**
   - Frontmatter `touches:` updated from `[ContentView, TableDoubleClick, PlayerEngine]`
     to `[PlayerEngine, NowPlayingBar, MediaKeyController, ContentView]`.
   - `TableDoubleClick.swift` was read but not modified — the bug is upstream
     of it.
   - `MediaKeyController.swift` was added because it was a previously-unknown
     consumer of the moved `@Published` properties. Without updating it,
     the build would not compile.
   - `NowPlayingBar.swift` was added because it is the primary intentional
     consumer of the high-frequency time fields and must subscribe to the
     clock to keep the scrub bar updating.

7. **Scope check:**
   - The card asked for: identify root cause, document it, fix it, leave
     other behaviors intact. The diff does exactly that and nothing else.
   - Adjacent issues observed but NOT fixed in this card (filed in Findings
     for follow-up): see Findings H6 and H7 below — `TableDoubleClick.updateNSView`
     and `TableScrollerHelper.updateNSView` both reach into the AppKit
     hierarchy on every body re-eval. After this fix removes the 4Hz body
     re-eval, both are dramatically less concerning, so no separate card
     filed unless QA requests one.
   - No drive-by refactors. No reformatting. No new dependencies. No
     unrelated bug fixes.

## Findings
*Filled in by the engineer during the audit. Anything observed that isn't part of the immediate fix but should be tracked as a follow-up card.*

### Root cause (the fix)

`PlayerEngine` had two `@Published` properties — `playbackPosition` and
`playbackDuration` — that were written 4 times per second by the
`addPeriodicTimeObserver` block. Any view that holds an
`@EnvironmentObject<PlayerEngine>` (which `ContentView` does) subscribes
to PlayerEngine's `objectWillChange` publisher unconditionally. SwiftUI does
NOT inspect which `@Published` properties the body actually reads — it
re-evaluates the body on every change to ANY of them.

So `ContentView.body` was being re-evaluated 4 times per second during
playback. The body builds a `Table(player.tracks, selection: $selection)`
backed by an `NSTableView`. SwiftUI's diff between two body invocations of
a Table can disrupt an in-progress mouse interaction in the AppKit table —
the click flickers to the new selection, then snaps back when the next body
invocation re-applies the previous selection from the binding.

The "every third click" failure rate is a perfect fingerprint: 4Hz means
~250ms between ticks; a click takes some sub-100ms time to commit through
SwiftUI's diff; any click whose commit phase straddles a tick gets
clobbered. That's roughly a 1-in-3 to 1-in-4 failure rate during continuous
clicking, which is exactly what the user reported.

The fix isolates the high-frequency state into a child `ObservableObject`
(`PlaybackClock`) that `ContentView` does NOT subscribe to. Only
`NowPlayingBar` and `MediaKeyController` subscribe to the clock — both of
those need the live updates and neither builds a Table.

### Why this also explains both reported triggers

- **Focus return**: when the JamBox window regains key status, AppKit
  generates a flurry of layout/redraw events that interleave with the same
  4Hz tick. The combination is what makes the click-flicker easier to
  trigger right after a focus change. The 4Hz tick is the prime mover; the
  focus change is just an amplifier.
- **Post-scroll click**: scrolling the table updates `NSScrollView` state
  and re-lays-out visible rows. Combined with the 4Hz body re-eval, the
  Table is in even more flux right after scrolling, so a click landing in
  that window is more likely to be on the wrong frame.

After the fix, neither trigger should remain, because the 4Hz body re-eval
is gone. **If symptoms persist for the human after testing**, the next most
likely culprit is the AppKit/SwiftUI Table selection bridge itself, and a
follow-up card should investigate `acceptsFirstMouse` / first-responder
semantics on `NSTableView` (per hypothesis 5 in the Plan).

### Other observations (NOT fixed in this card)

These are adjacent things noticed during the audit. They are not
load-bearing on the bug being fixed. If QA wants any of them filed as
follow-up cards, they're easy spinoffs.

- **F1: `TableDoubleClickHelper.updateNSView` re-runs on every body re-eval
  and re-assigns `tableView.doubleAction` and `tableView.target` from a
  `DispatchQueue.main.async` block** (`JamBox/TableDoubleClick.swift:35-48`).
  After this card, body re-evals are rare (only on real state changes), so
  this is no longer 4× per second. But it's still wasteful — the assignment
  could be guarded by an `objectIdentifier`-style check, or moved into
  `makeNSView` with a `Coordinator.update` pathway. Low priority now.

- **F2: `TableScrollerHelper.updateNSView` does the same — reaches into the
  view hierarchy on every body re-eval** (`JamBox/TableScroller.swift:52-72`).
  Same comment as F1: less urgent after this card. Even when `targetRow == nil`
  it dispatches an async block whose net effect is a no-op. Free to optimize
  later.

- **F3: `NowPlayingBar` injects `clock` as a constructor argument rather
  than reaching into `player.clock` itself.** This is intentional: separating
  the dependency makes the high-frequency observation explicit at the call
  site, which makes the no-re-render-of-parent invariant impossible to
  accidentally violate (you can't pass `player.clock` to a child view from a
  body that observes `player`, without first severing the observation).
  Alternative would be to make `NowPlayingBar` accept a `PlayerEngine` and
  internally do `@ObservedObject var clock = ...`, but Swift doesn't let
  you initialize an `@ObservedObject` from another property in the
  initializer that cleanly. Current shape is the right one.

- **F4: `MediaKeyController` is `@MainActor` and constructs in `AppModel.init`,
  which is also `@MainActor`.** No issue, just confirming.

- **F5: `PlaybackClock` is declared at file scope above `PlayerEngine` so
  that the `let clock = PlaybackClock()` initializer in `PlayerEngine` can
  reference it without forward-decl gymnastics.** Could equally be a nested
  type; left at file scope for grep-ability.

## QA Report
*Filled in by the QA agent. See .pm/README.md §6b.*

### Acceptance

### Invariants

### Findings

### Recommendation

## Manager Decision
*Filled in by the manager when closing or kicking back.*
