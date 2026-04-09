---
id: 0006d
title: Layer 3b XCUITest user-flow tests
created: 2026-04-08
needs_designer: false
designer: null
design_review: null
engineer: engineer-06d
qa: null
parent: 0006
priority: P1
estimate: L
depends_on: [0006a]
touches:
  - JamBoxUITests/
  - project.yml
acceptance:
  - A new XCUITest target is added to `project.yml` and wired so `xcodegen generate` produces a valid project.
  - Launch app, verify the main window appears with the song table or the empty-state folder picker.
  - With a fixture folder loaded, double-click a row and verify the now-playing bar populates with that track's title. REGRESSION TEST for card 0001 (right-click context menu area).
  - With a fixture folder loaded, right-click a row and verify a context menu appears containing items "Play" and "Show in Finder". REGRESSION TEST for card 0001.
  - With a fixture folder loaded and playing, press spacebar and verify play/pause toggles. REGRESSION TEST for cards 0008 + 0021 (the spacebar focus story).
  - **REGRESSION TEST for card 0021 specifically** — quit the app while a track is playing, relaunch, immediately press spacebar (without clicking), verify playback toggles. This is the exact bug from card 0021 and is the highest-value UI test in the file.
  - Scrub bar drag updates the displayed time during the drag, and committing the drag seeks the player. REGRESSION TEST for the drag-decouple pattern.
  - With sort and search active, double-click a filtered row and verify the right track plays. REGRESSION TEST for cards 0008 + 0011 composition.
  - Window resize: verify the table and now-playing bar still render correctly across a few sizes (e.g. minimum 500 wide, 800 wide, 1400 wide).
  - All tests pass via `xcodebuild test`.
  - UI tests are slower than other layers — runtime documented in Self-Audit.
  - Build green, no new warnings.
  - §7 invariants preserved.
---

## Context

Fourth and final card split from 0006. Depends on 0006a's test target setup. XCUITest target is separate from the unit-test target and is added in this card. Tests drive the actual app via accessibility identifiers.

The card 0021 regression test is non-negotiable: that specific bug (post-resume launch + spacebar) is exactly the kind of cross-card-interaction failure the per-card review process is bad at catching, and a UI test is the systemic fix.

This is the slowest layer to develop and run. May be split further (0006d-1 / 0006d-2) by the engineer if it gets unwieldy.

## Plan

### Approach

Add a separate `JamBoxUITests` XCUITest target of type `bundle.ui-testing`. UI tests drive the real `JamBox.app` via `XCUIApplication`. They are slow (each test launches the actual app, ~3-10s apiece) so the suite is kept as small as possible while still covering every acceptance bullet, with careful test-ordering and a shared fixture setup path to minimize overhead.

The single hardest infrastructure problem is folder selection: XCUITest cannot cleanly click through `NSOpenPanel`, and seeding a security-scoped bookmark into `UserDefaults` from outside the sandbox requires binary data we don't easily have. Chosen solution: **add a launch-argument override to `AppModel`** that bypasses both the bookmark path and `NSOpenPanel` when a fixture-folder path is passed on launch. This is a tiny, isolated production change, flagged in Self-Audit scope check.

Launch argument format: `--ui-test-fixture-folder <absolute-path>`. When present in `CommandLine.arguments` at `AppModel.init()` time, `loadSavedFolder()` is bypassed and `loadFolder(url)` is called directly with the passed path as a plain (non-security-scoped) `URL`. Because XCUITest launches the app as a child process with the test runner as parent, and the tests run under the user's account (not a sandboxed subprocess from the app's perspective), the fixture path is accessible without a bookmark. Documented in `TESTING.md`.

The fixture folder for UI tests is a temp directory populated in `setUp()` of each test class by copying the bundled audio fixtures (from the JamBoxUITests bundle resources) to a fresh `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`. This keeps tests isolated: no test mutates another's folder, and a test that quits/relaunches the app still points at a stable path. We reuse the same six fixture files 0006a produced — they're re-copied into the UI test bundle via `project.yml` resources entry so `Bundle(for: XCUITestCaseAnchor.self)` can find them. This avoids cross-target coupling.

Accessibility identifiers: SwiftUI `Table` cells don't get stable identifiers by default, the transport buttons are `Image` labels (not labeled buttons), and the scrub slider has no identifier. We need to add `.accessibilityIdentifier()` modifiers to:
- The `Table` itself (id: `trackTable`)
- The play/pause `Button` in `NowPlayingBar.transportCell` (id: `playPauseButton`)
- The metadata title `Text` in `metadataCell` (id: `nowPlayingTitle`)
- The slider in `sliderCell` (id: `scrubSlider`)
- The left timestamp `Text` (id: `elapsedTime`)
- The search field in `ContentView` (id: `searchField`)
- The empty-state "Choose Folder" button (id: `chooseFolderButton`)
- The "Nothing playing" text (id: `nothingPlaying`)

These are the minimum needed to uniquely locate elements; no other production changes.

Card 0021 regression test specifically:
1. Copy fixtures to tempdir
2. Launch app with `--ui-test-fixture-folder <tempdir>`
3. Double-click first track row → verify now-playing title populates
4. Wait ~1s for playback to actually start (elapsed time advances past 0:00)
5. `app.terminate()` — this triggers `willTerminate` → `savePlaybackState()`, persisting the track+position to real UserDefaults (same UserDefaults domain — which does persist between app launches)
6. Launch the app again with the same launch argument
7. Verify now-playing bar shows the same title (resume seeded it). WITHOUT clicking anywhere, call `app.typeKey(" ", modifierFlags: [])`
8. Assert: elapsed time changes over a short wait (playback started) OR the play/pause button's accessibility value flips to "pause.fill". We'll use the elapsed-time advance check as the authoritative signal since it's more robust to SwiftUI label drift.

**Important UserDefaults consideration for card 0021 test:** the persisted state key is `jambox.playback.state`. That persists across `terminate()`/`launch()` in the same test because both app invocations share the user's defaults domain. BUT we DO need the URL the saved track points at to still exist and be in the folder we pass on the second launch — so the tempdir must survive between the two launches. We keep one tempdir per test (`setUp`-scoped) and tear it down in `tearDown`. Also: the saved state includes the absolute URL of the track; since we're using the same tempdir path across both launches within one test, that matches.

Scrub bar test: start playback, locate the slider, issue a drag from its current value to ~20% from left. Assert the left timestamp text changes after release (it will have moved to a new position). The exact drag mechanics in XCUITest for `NSSlider` backing a SwiftUI `Slider` is `slider.adjust(toNormalizedSliderPosition:)` — we use that.

Sort + search compose test: type "tone-24" into the search field (matches only the 24-bit FLAC fixture by filename), double-click the visible filtered row, verify the now-playing title is "tone-24" (or its metadata title). Sort interaction: click the Title column header first (to flip sort), then search, then double-click. We verify the RIGHT track plays (via title text), which is the bug-class regression.

Window resize test: resize the main window to 500w, 800w, 1400w via `window.resize(byDelta:)` or by setting frame via AppleScript (XCUITest doesn't have a clean API for this). Alternative: use `NSAccessibility` frame setting via XCUITest's `XCUIElement.value`-based resize, which doesn't exist. Actually, XCUITest's `XCUIElement.coordinate().press(forDuration:thenDragTo:)` can grab the window's resize handle. Simpler: skip low-level resize mechanics and use `app.windows.firstMatch.coordinate(withNormalizedOffset:).press(...)`. Even simpler and most reliable: add a hidden launch-argument `--ui-test-window-width <N>` that sets the initial window size. But that's more production plumbing. Chosen compromise: use `XCUIApplication`'s standard "zoom" / resize via its window element's `.resize(by:)` helper if available; if not, we accept a narrower test that asserts the window exists at its default size and that `minWidth: 500` from `.frame(minWidth: 500)` prevents a zero-width layout (this is enforced by the SwiftUI modifier, not testable at the window-chrome level from XCUITest without brittle coordinate math). 

Resolution: window resize will be tested by attempting resize via the resize-corner drag (XCUITest coordinate-based drag at the window's bottom-right corner to move it by delta pixels) at three target widths, verifying after each that the key UI elements (`trackTable`, `playPauseButton`) are still hittable/exist. This is the minimum viable "UI still renders correctly at size N" assertion achievable from XCUITest without adding more production hooks.

### Files

New:
- `project.yml` — add `JamBoxUITests` target (edit existing file)
- `JamBoxUITests/JamBoxUITests.swift` — placeholder + shared base class
- `JamBoxUITests/LaunchAndEmptyStateTests.swift` — launch + empty-state coverage
- `JamBoxUITests/PlaybackFlowsTests.swift` — double-click, context menu, spacebar, scrub, sort+search, window resize
- `JamBoxUITests/ResumeRegressionTests.swift` — card 0021 regression isolated in its own file (highest-value test, must be easy to find)
- `JamBoxUITests/Support/FixtureSetup.swift` — temp folder fixture helper
- `JamBoxUITests/Support/LaunchArguments.swift` — constants for launch arg keys
- `JamBoxUITests/Fixtures/*.{mp3,m4a,flac,wav,aiff}` — copied from JamBoxTests/Fixtures via XcodeGen resources (not duplicated on disk; resource path in project.yml points at `JamBoxTests/Fixtures`)

Modified:
- `JamBox/AppModel.swift` — launch argument handling (~10 lines, gated on CommandLine.arguments presence)
- `JamBox/ContentView.swift` — add `.accessibilityIdentifier()` modifiers (~5 additions)
- `JamBox/NowPlayingBar.swift` — add `.accessibilityIdentifier()` modifiers (~4 additions)
- `project.yml` — new `JamBoxUITests` target
- `TESTING.md` — document the UI test target, launch arg format, runtime expectations
- `JamBox.xcodeproj/project.pbxproj` — regenerated by xcodegen

### Risks

1. **XCUITest resource bundling for fixtures.** If the JamBoxUITests target points its resources path at `JamBoxTests/Fixtures/`, XcodeGen will emit a copy-resources build phase that dedupes. If that's not possible cross-target, fallback is to glob-copy via `resources:` entry with an explicit path; worst case we commit a second copy (tiny overhead, 6 small files). Mitigation: try the cross-target resource reference first.
2. **`app.terminate()` timing.** `willTerminate` runs synchronously on main thread but the `savePlaybackState` write goes through UserDefaults, which may not flush to disk before the next `XCUIApplication().launch()` reads it. Mitigation: after terminate, call `UserDefaults.standard.synchronize()` from inside the app's willTerminate handler (it already writes via `.set()` which is queued). If reads fail, add a short `sleep(1)` before re-launch. Docker-style: we measure.
3. **Spacebar via `typeKey`.** `app.typeKey(" ", modifierFlags: [])` sends a key event to the focused element. If nothing is focused (the post-resume state), the event goes to the key window. Card 0021's fix installs an app-level `NSEvent.addLocalMonitorForEvents` monitor that catches spacebar regardless of first responder, so this should work. If it doesn't, the test will fail and reveal that card 0021's fix doesn't cover this exact code path — which is itself valuable signal.
4. **Context menu via XCUITest.** `app.tables.cells.element(boundBy: 0).rightClick()` opens the context menu. The menu items appear in `app.menuItems` (not `app.buttons`). We match by label "Play" and "Show in Finder".
5. **Runtime budget.** Six tests × ~8s each = ~50s for the UI suite. XCUITest doesn't fit the "fast" budget, but it's acceptable per the card.
6. **Flakiness.** UI tests are famously flaky. We use `XCTWaiter.wait(for: [expectation], timeout: N)` patterns with explicit element `.waitForExistence(timeout:)` calls before every assertion instead of bare `sleep`.

### Open questions

- None load-bearing. The launch-argument approach is standard and documented. The accessibility identifier additions are minimal and flagged in scope check.

### Revision

(none yet)

## Log
- 2026-04-08 — manager created card in backlog/, depends on 0006a
- 2026-04-08 — engineer-06d claimed, mv ready → in-progress

## Self-Audit

## QA Report

## Manager Decision
