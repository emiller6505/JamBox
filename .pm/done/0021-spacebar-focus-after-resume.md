---
id: 0021
title: Hotfix — spacebar play/pause doesn't work after launch with resumed track until table is clicked
created: 2026-04-08
needs_designer: false
designer: null
design_review: null
engineer: manager-inline
qa: user-validated
parent: 0012
priority: P0
estimate: S
depends_on: []
touches:
  - JamBox/AppModel.swift
acceptance:
  - After launching the app with a resumed track loaded paused, pressing spacebar toggles play/pause without requiring a click.
  - When the search field has focus, pressing spacebar inserts a literal space character (not a play/pause toggle).
  - When a non-text-field view has focus (e.g. the track table), spacebar continues to toggle play/pause as before.
  - Modified spacebar combos (Cmd+Space, Shift+Space, etc.) are passed through and not intercepted.
  - Build green: ** BUILD SUCCEEDED **
  - User-validated.
---

## Context

After card 0012 (resume on launch) shipped, the user discovered that when the app reopens with a resumed track in its now-playing bar (paused), pressing the spacebar to begin playback **does nothing** until they first click somewhere in the song table. After the click, spacebar works normally.

The bug arose from the interaction of two earlier cards:

- **Card 0008** (search filter) added `WindowAccessor.swift` logic to clear the initial first responder on first launch (`window.makeFirstResponder(nil)`), so the search TextField wouldn't auto-grab focus and swallow the first spacebar press the user made.
- **Card 0012** (resume) made it possible for the app to be in a "track loaded, paused" state at launch *without any user click*. Before 0012, the user would always click a track first to start playback, which gave the SwiftUI Table focus implicitly, and the existing `.onKeyPress(.space)` modifier on the parent VStack would fire from then on.

After both cards shipped, the launch state is: WindowAccessor cleared first responder → nothing in the SwiftUI tree has focus → `.onKeyPress(.space)` has no focused view in its subtree → spacebar key events go nowhere. Clicking the table gives the table focus and the modifier starts firing.

## Fix

Install an `NSEvent` local key-down monitor in `AppModel.init()`. The monitor matches `.keyDown` events, filters to keyCode 49 (spacebar) with no modifier flags, checks whether the current first responder is an `NSText` or `NSTextView` (the search field, when focused), and if not calls `player.togglePlayPause()` and consumes the event by returning nil. If the first responder IS a text field, the event is returned unchanged so the user can type literal spaces.

This is the same focus-independent app-lifetime mechanism `MediaKeyController.swift` already uses for media keys. The monitor is stored as `private var spaceKeyMonitor: Any?` on `AppModel` so it stays alive for the app's lifetime (no deinit needed; AppModel is a top-level `@StateObject` owned by `JamBoxApp`).

The existing `.onKeyPress(.space)` modifier in `ContentView.swift` is left in place. It still serves as the secondary handler when something IS focused inside the content view (which is the common case after the first user interaction). The new NSEvent monitor is the primary handler that always fires regardless of focus state. Both code paths call `player.togglePlayPause()`, which is idempotent — toggling play/pause is the same operation no matter which path delivers the event. Worst case both fire on a single keypress: the second call would un-toggle the first, which would be wrong. In practice that doesn't happen because the NSEvent monitor returns `nil` to consume the event before SwiftUI's `.onKeyPress` ever sees it. Verified by user.

## Code change

`JamBox/AppModel.swift`:

1. New stored property `private var spaceKeyMonitor: Any?` with documentation explaining the rationale.
2. New private method `installSpaceKeyMonitor()` that adds an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` handler. Filters keyCode 49 + no modifier flags + first-responder-is-text-field guard. Calls `player.togglePlayPause()` via `MainActor.assumeIsolated` (the closure isn't MainActor-isolated at the type-system level even though the local monitor delivers on the main thread).
3. `installSpaceKeyMonitor()` called from `init()` immediately before `loadSavedFolder()`.

No changes to `ContentView.swift`. No changes to `WindowAccessor.swift`. The first-responder-clear logic from card 0008 stays in place; the new NSEvent monitor handles spacebar app-wide regardless.

## Validation

User opened the rebuilt Release binary, confirmed the resumed track was loaded and paused, pressed spacebar without clicking — playback started. Pressed spacebar again — paused. Then verified the search field still works for literal-space typing.

## Process note

Same as card 0020: this was fixed inline by the manager rather than dispatched as a full engineer card, because the user was actively testing and the loop time would have been disproportionate to the size of the fix (~30 lines).

This is also a process gap that the PM protocol should consider: **launch-state behaviors that depend on the interaction of multiple shipped cards are invisible to per-card review**. Card 0012's QA and §6c reviews both verified the resume *mechanism* worked correctly. Neither asked "what is the focus state of the SwiftUI view tree at the moment resume completes, and does that focus state interact correctly with other shipped behaviors?" That question doesn't naturally arise from reading 0012 in isolation — it requires holding all of 0008, 0011, and 0012 in mind at once.

A possible mitigation: every card with `needs_designer: true` AND that touches launch-state behavior should include a "post-launch first-interaction" check in the designer's `## User Risks & Edge Cases` section. "What does the user experience when they press the most natural keyboard shortcut at the moment immediately after the app finishes launching?" For a music player, that shortcut is spacebar. Filing as a future consideration for the PM protocol.

## Manager Decision

2026-04-08 — APPROVE. User validated. Closing to done/ as a hotfix to card 0012. Process gap documented above for future PM protocol revision and for inclusion in any "launch-state cross-card interaction" checklist.
