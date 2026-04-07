---
id: 0009
title: Add global text size setting (50%–200%) persisted across launches
created: 2026-04-07
engineer: null
qa: null
parent: null
priority: P2
estimate: M
depends_on: []
touches:
  - JamBox/JamBoxApp.swift
  - JamBox/ContentView.swift
  - JamBox/NowPlayingBar.swift
  - JamBox/Theme.swift
acceptance:
  - The user can pick a text size from a discrete set of options ranging from 50% to 200% (suggested set — engineer may refine in plan mode: 50%, 75%, 100%, 125%, 150%, 175%, 200%). 100% is the default and matches the app's current appearance exactly
  - The picker lives in the menu bar under **JamBox** (next to / near the existing **Theme** picker), implemented as a `CommandGroup` `Picker` mirroring the Theme picker pattern in `JamBoxApp.swift`
  - The user's choice persists across launches via `@AppStorage` (same persistence pattern as `ThemeManager` in `Theme.swift`)
  - The selected scale applies globally to ALL text in the app: track table cells, column headers, now-playing bar (title/artist/album/timestamps), folder sidebar entries, search field, menu items where applicable, and any other in-window text. Menus that are part of the macOS menu bar itself (rendered by AppKit) are NOT expected to scale — that is a system-level concern outside this card's scope
  - The implementation uses Apple's built-in dynamic type / accessibility scaling rather than rolling a custom font-size system. Specifically, the engineer should evaluate `dynamicTypeSize(_:)` (SwiftUI environment value, available macOS 11+) which scales any text built from `Font.TextStyle` (`.body`, `.headline`, `.caption`, etc.) and also `ScaledMetric` for non-text dimensions if needed. Confirm the choice in plan mode and document why
  - Any text in the app currently using fixed-size fonts (`Font.system(size: 14)` or similar) must be migrated to a `Font.TextStyle`-based font so it participates in scaling. The engineer must grep the codebase for fixed-size font usage and migrate every instance, or document why a specific instance must remain fixed (e.g. SF Symbols sized to match a UI element)
  - **Layout integrity at every scale:** at 50%, 100%, 150%, and 200%, the app must remain usable and visually acceptable. No clipped text, no overflowing rows, no labels covering icons, no broken alignment in the now-playing bar, no truncated column headers without ellipsis. Row heights, button hit-targets, and toolbar/chrome spacing should grow with the text where appropriate. **A design-minded review is mandatory** — the engineer must take screenshots (or describe in detail) the app at 50%, 100%, 150%, 200% and confirm acceptable layout in their self-audit
  - Album-art thumbnails, the play/pause/skip button glyphs, the magnifying glass in the search field, and other non-text glyph elements remain at their current sizes (do NOT scale with text). The relationship of their containers to the text should still look right at all scales, but the glyphs themselves are not text and should not grow
  - Scrub bar height, slider knob size, and other interactive control dimensions remain fixed (do not scale)
  - All three themes (light, dark, candy) must look acceptable at all four representative scales. The engineer verifies all 12 combinations in self-audit
  - Build passes cleanly with no new warnings: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - Gapless playback unchanged — no edits to PlayerEngine queue logic
  - AVURLAsset invariant unaffected — no audio code touched
  - Two-phase loading invariant unaffected — text scaling is pure presentation
  - Click responsiveness from card 0002 unaffected — text size changes are infrequent and human-driven, not high-frequency, but the engineer should verify the persistence object follows the same pattern as `ThemeManager` (a small `ObservableObject` with one `@AppStorage`-backed property) and is plumbed via `@EnvironmentObject` only where needed
---

## Context

User-facing request:

> "text size change. Let's add a global text size modifier to the app. Is there a built in apple library for this? Think accessibility. Somewhere in the app settings menu, I want an option to select the text size - anywhere from 50% to 200% (a scale based on the current text size being 100%, the default). This should just be a menu to select from within the settings somewhere - not a zoom in/zoom out type thing like in web browsers. This preference should persist across sessions. Use a design-minded agent to make sure the font sizes don't explode past their boundaries and make the app look bad."

### Is there a built-in Apple library for this? Yes.

SwiftUI ships **Dynamic Type** via the `dynamicTypeSize(_:)` view modifier and the `DynamicTypeSize` enum (`.xSmall` through `.accessibility5`, with `.large` as the default). Any text built from a `Font.TextStyle` semantic font (`.body`, `.headline`, `.title`, `.caption`, etc.) automatically scales when the environment's dynamic type size changes. This is the same machinery iOS uses for system-wide text scaling and the same machinery macOS Sonoma+ uses for the system Text Size accessibility setting.

For non-text dimensions that need to scale with text (e.g. row heights, padding around text), SwiftUI has `ScaledMetric`:
```swift
@ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 28
```
This makes `rowHeight` grow proportionally with the user's text scale.

**The engineer should use these. Do NOT roll a custom font-size system, do NOT thread a `CGFloat` scale through every view manually.** The right shape is:

1. A `TextSizeManager` ObservableObject (mirroring `ThemeManager`) with an `@AppStorage("textSize")` backed property whose value is one of the discrete percentages.
2. That percentage is mapped to a `DynamicTypeSize` enum value at the root view.
3. The root view applies `.dynamicTypeSize(textSizeManager.current.dynamicTypeSize)`.
4. Any fixed-size fonts in the codebase get migrated to `Font.TextStyle` so they participate.

### Mapping percentages to DynamicTypeSize

`DynamicTypeSize` is an enum with twelve cases ranging from `.xSmall` to `.accessibility5`. The default is `.large` (100% in user-facing terms). The engineer needs to pick a mapping in plan mode. A reasonable starting point:

| User-facing % | DynamicTypeSize |
|---|---|
| 50% | `.xSmall` |
| 75% | `.small` |
| 100% | `.large` (default) |
| 125% | `.xLarge` |
| 150% | `.xxLarge` |
| 175% | `.xxxLarge` |
| 200% | `.accessibility1` |

Note that the actual scale factors aren't exactly linear with the percentages — Apple's enum jumps by ~12% per step in the lower range and ~20%+ in the accessibility range. The engineer should confirm by testing what the actual rendered ratios look like and label the menu items by the user's desired percentages, even if the underlying enum case isn't a perfect match. Document the mapping in the plan.

### Why the design review is mandatory

The user explicitly asked: "Use a design-minded agent to make sure the font sizes don't explode past their boundaries and make the app look bad." This is a hard requirement. The engineer must:

- Audit the now-playing bar, where horizontal space is tight (artwork + title/artist + scrub bar + transport controls + timestamps).
- Audit the table column headers and cells — at 200%, will the columns still fit, or will they truncate? Are the column widths fixed or flexible?
- Audit the folder sidebar — at 200%, do folder names fit?
- Audit the search field — at 200%, does the field still render acceptably?
- Audit the candy theme specifically — its background gradient may interact poorly with very large text if the layout breaks.

### Where to put the menu

Currently `JamBoxApp.swift` adds a `CommandGroup(after: .appInfo)` with a Theme picker. The text size picker should live in the same group, immediately after Theme:

```swift
.commands {
    CommandGroup(after: .appInfo) {
        Divider()
        Picker("Theme", selection: themeBinding) { ... }
        Picker("Text Size", selection: textSizeBinding) { ... }
    }
}
```

The user said "settings menu" which on macOS typically means **JamBox → Settings… (Cmd-,)** as a Settings scene. JamBox does NOT currently have a Settings scene — it uses the menu bar items directly. **Do NOT introduce a Settings scene in this card.** Adding one is its own design decision that should be a separate card. Mirror the existing Theme pattern.

### Out of scope for v1

- A live preview of the text size while picking
- Per-element text size overrides (only the global scale is supported)
- A keyboard shortcut for cycling sizes (Cmd-+ / Cmd-−) — the user explicitly said "not a zoom in/zoom out type thing like in web browsers"
- A Settings scene
- Scaling of non-text glyphs / icons / album art
- Migration of system menu bar text (handled by AppKit, not us)

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
