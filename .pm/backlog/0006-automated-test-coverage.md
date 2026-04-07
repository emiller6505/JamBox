---
id: 0006
title: Establish automated test coverage for main user flows and project invariants
created: 2026-04-06
engineer: null
qa: null
parent: null
priority: P1
estimate: XL
depends_on: []
touches:
  - project.yml
  - JamBox.xcodeproj
  - JamBoxTests/
  - JamBoxUITests/
  - JamBox/PlayerEngine.swift
  - JamBox/Track.swift
  - JamBox/FileScanner.swift
  - JamBox/AppModel.swift
  - CLAUDE.md
acceptance:
  - A working test target (or targets) exists in the Xcode project, wired into project.yml so xcodegen regenerates them correctly
  - `xcodebuild -project JamBox.xcodeproj -scheme JamBox test` runs all tests and exits 0 on a clean main
  - The chosen test framework (XCTest vs Swift Testing) is documented with a one-paragraph rationale in CLAUDE.md or a new TESTING.md
  - Test fixtures (small real audio files in mp3, m4a, flac, wav, aiff formats — each 1-3 seconds of silence or tone) are committed to a known directory (e.g. `JamBoxTests/Fixtures/`) and used by both unit and integration tests
  - **Unit tests (fast, hermetic, no AVFoundation against real files unless using fixtures):**
  - "  - Track.init(url:) produces correct displayName from filename without extension"
  - "  - Track.loadMetadata parses ID3 tags correctly from a fixture mp3 with known title/artist/album/track number"
  - "  - Track.loadMetadata parses Vorbis comments correctly from a fixture flac with known metadata under vorb/TITLE / vorb/ARTIST / vorb/ALBUM identifiers (REGRESSION TEST for the known bug where AVFoundation's commonMetadata is empty for FLAC)"
  - "  - Track.loadMetadata returns sensible defaults when metadata is missing"
  - "  - FileScanner.scanFolder returns only files with supported extensions (mp3, m4a, flac, aiff, aif, wav, alac, aac), filters out non-audio"
  - "  - FileScanner.scanFolder returns files in a stable order"
  - "  - AppModel state persistence round-trips correctly (write state, recreate AppModel, read back state)"
  - "  - ThemeManager persistence and restoration"
  - "  - Duration formatting helpers (mm:ss, h:mm:ss boundaries)"
  - "  - Track number string formatting"
  - **Integration tests (real AVFoundation against fixture audio files, slower):**
  - "  - PlayerEngine.play(startingAt:) on a freshly-loaded fixture track starts playback within a reasonable timeout"
  - "  - PlayerEngine maintains a 3-item lookahead in the AVQueuePlayer queue when more than 3 tracks are loaded (REGRESSION TEST for gapless playback invariant)"
  - "  - PlayerEngine advances from one track to the next on natural end-of-track without manual intervention"
  - "  - PlayerEngine pause/resume preserves position correctly"
  - "  - PlayerEngine seek to a known offset works and updates the published clock position correctly"
  - "  - FLAC fixture file with a STREAMINFO header reports the correct duration when loaded via PlayerEngine (REGRESSION TEST for the FLAC duration bug — invariant §7.1)"
  - **Static / structural checks:**
  - "  - A test (or build-phase script) greps the entire JamBox/ source tree for `AVURLAsset(` constructions and fails if any of them do not include `AVURLAssetPreferPreciseDurationAndTimingKey: true` in the options dictionary (enforces invariant §7.1 mechanically — this is the most important regression defense in the project)"
  - "  - A test (or build-phase script) verifies that every `startAccessingSecurityScopedResource` call has a matching `stopAccessingSecurityScopedResource` in the same scope or via deferred / scoped pattern (enforces invariant §7.4)"
  - "  - A test (or unit test) verifies that PlayerEngine does NOT have any @Published properties that are written at high frequency (>1Hz) — guards against re-introducing the click race fixed in card 0002 by re-merging high-frequency state into the wrong observable. The implementation can be a unit test that introspects PlayerEngine's published property names against a known allowlist, OR a comment-driven convention enforced in code review. Engineer chooses."
  - **UI / interaction tests (XCUITest, slowest, can be skipped on CI for speed if needed but must exist):**
  - "  - Launch app, verify the main window appears with the song table or the empty-state folder picker"
  - "  - With a fixture folder loaded, double-click a row and verify the now-playing bar populates with that track's title (REGRESSION TEST for double-click-to-play, card 0001 area)"
  - "  - With a fixture folder loaded, right-click a row and verify a context menu appears containing items 'Play' and 'Show in Finder' (REGRESSION TEST for card 0001)"
  - "  - With a fixture folder loaded and playing, press spacebar and verify play/pause toggles (REGRESSION TEST for the spacebar shortcut from ROADMAP.md)"
  - "  - Scrub bar drag updates the displayed time during the drag, and committing the drag seeks the player (REGRESSION TEST for the drag-decouple pattern from CLAUDE.md)"
  - "  - Window resize: verify the table and now-playing bar still render correctly after resizing the window across a few sizes"
  - All tests pass on a clean main checkout. Engineer must verify by running `xcodebuild test` and pasting the final summary into the Self-Audit section.
  - Test runtime is documented (how long does the full suite take?). If any single test takes >5 seconds, it is annotated with a comment explaining why
  - CLAUDE.md (or new TESTING.md) gains a "Testing" section that documents: how to run the suite locally, where fixtures live, how to add a new test, how to add a new fixture audio file, and the mechanical-enforcement scripts (AVURLAsset / sandbox bookmark grep checks) so contributors know they exist
  - The test target / scheme settings do NOT require any custom code signing the user has not already configured. If a fresh JamBox checkout with no extra setup cannot run `xcodebuild test`, the card fails review
  - No production code is touched UNLESS the engineer needs to expose internal types as `@testable import` (which is fine and standard) or to add `internal` accessors for testability — and any such changes must be flagged in the Self-Audit Scope-Check
  - Build passes cleanly with no new warnings: `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` AND `xcodebuild -project JamBox.xcodeproj -scheme JamBox test`
  - The AVURLAsset, gapless playback, two-phase loading, and sandbox bookmark invariants are all preserved (the test target's existence cannot break the app's runtime behavior)
  - Engineer regenerates the Xcode project via `xcodegen generate` after adding the test target to project.yml, and commits the regenerated `JamBox.xcodeproj`
---

## Context

User-facing request from the human owner:

> "create a P1 ticket for creating automated test coverage of all the main user flows. I don't know what the common patterns are for swift apps, so that's up to you and the engineers. from all our markdown docs, code, and your knowledge so far: create regression tests that enshrine the highest priorities of this app and defend against regressions."

The user has explicitly delegated the framework / pattern choice to the manager and engineers. They are not opinionated about XCTest vs Swift Testing vs anything else. The goal is **regression defense for the things this project has explicitly identified as load-bearing**, not a generic "high coverage" exercise.

### What "the highest priorities of this app" actually means in this codebase

Read across CLAUDE.md, ROADMAP.md, the closed cards (0001, 0002), and the in-flight card (0005), the project has explicitly identified these as load-bearing:

1. **Gapless playback via AVQueuePlayer 3-item lookahead** (CLAUDE.md, invariant §7.2). The whole reason the app exists. If this regresses, the app is dead.
2. **AVURLAssetPreferPreciseDurationAndTimingKey on every AVURLAsset** (CLAUDE.md, invariant §7.1). The FLAC duration bug. Without this option, FLAC files play 2-5 seconds past their stated end and emit `FigFilePlayer err=-12864`. This rule is so important that CLAUDE.md spells it out in capital letters. **A mechanical regression check for this rule is the single highest-value test in the entire suite.**
3. **Two-phase loading** — fast filesystem scan first, async metadata enrichment second. Don't block the UI on metadata.
4. **Vorbis metadata fallback for FLAC** — AVFoundation's `commonMetadata` is empty for FLAC; the code reads `vorb/TITLE` etc. instead. This is a known footgun and a likely regression target.
5. **Sandbox bookmarks balanced** (invariant §7.4).
6. **Click responsiveness** (just fixed in card 0002). The sub-bug — `@Published` properties on `PlayerEngine` written at high frequency causing `ContentView.body` to re-evaluate at the same rate, racing with AppKit click commits — is subtle and easy to re-introduce by accident. A unit test that introspects `PlayerEngine`'s `@Published` properties against an allowlist is a cheap and durable defense.
7. **Right-click context menu** (just shipped in card 0001). UI tests are the right home for this.
8. **Scrub bar drag-decouple** (CLAUDE.md). Local `@State isScrubbing` / `scrubFraction` decouple the slider from live playback during drags. Easy to break in a refactor.
9. **App state persistence** (recent commit "Theme switcher, persistent app state, and macOS media keys").
10. **Spacebar play/pause and macOS media keys** (ROADMAP.md, recent commit).

### Recommended test architecture

Three layers, in order from cheapest-and-most-valuable to most-expensive:

**Layer 1 — Static / structural checks (CHEAPEST, HIGHEST VALUE).** A small set of grep-style checks, implemented either as XCTest unit tests that read the source tree as text, or as a build-phase shell script. These enforce the project's explicit invariants mechanically without needing any runtime execution.
- AVURLAsset precise-timing key check (invariant §7.1) — single most important test in the suite
- Sandbox bookmark balance check (invariant §7.4)
- PlayerEngine @Published-property allowlist (regression defense for card 0002)

**Layer 2 — Unit tests (FAST, HERMETIC).** XCTest or Swift Testing unit tests against pure model logic. These run in milliseconds and catch most logic regressions.
- `Track` parsing (mp3 ID3, FLAC vorb/, defaults)
- `FileScanner` filtering and ordering
- `AppModel` and `ThemeManager` persistence round-trips
- Formatting helpers

**Layer 3 — Integration & UI tests (SLOW, HIGH-VALUE FOR USER-FACING REGRESSIONS).** Integration tests use real AVFoundation against fixture audio files. UI tests use XCUITest to drive the actual app. These are slower and flakier but only way to catch the user-flow regressions.
- Integration: PlayerEngine plays / advances / seeks, FLAC duration is correct, gapless invariant
- UI: launch, double-click plays, right-click menu, spacebar, scrub bar drag

### Framework choice

Two reasonable choices, both fine. The engineer picks in plan mode and documents the choice with a paragraph rationale:

- **XCTest** — Apple's standard test framework. Bombproof. Works in every Xcode version. Familiar. **Recommended default unless the engineer has a strong reason to pick the other option.**
- **Swift Testing (Xcode 16+)** — modern macro-based framework with `@Test`, parameterized tests, better failure messages. JamBox targets macOS 14+, which is fine, but the build system is Xcode-version-dependent. If the developer's Xcode is 16+, this is a more pleasant developer experience. If Xcode 15, fall back to XCTest.

XCUITest is the standard choice for the UI layer regardless.

### Test fixture audio files

The integration and UI tests need real audio files. Generate small fixtures:

- 1-3 seconds of silence in each format: mp3, m4a, flac, wav, aiff
- One FLAC fixture with known embedded metadata under `vorb/TITLE`, `vorb/ARTIST`, `vorb/ALBUM` to regression-test the Vorbis fallback path
- One FLAC fixture with a STREAMINFO header that reports its duration correctly to regression-test the precise-timing-key requirement
- Each fixture should be small (under 100 KB ideally) to keep the repo lean

These can be generated with `ffmpeg`/`afconvert` and committed. Engineer should script the generation in a small `JamBoxTests/Fixtures/generate.sh` so future contributors can regenerate.

### What is explicitly OUT of scope for this card

- **CI configuration.** This card establishes the test target and the suite. Hooking it up to GitHub Actions or another CI system is a separate concern; if the engineer wants to add a CI config they should file it as a follow-up backlog card.
- **Code coverage measurement.** Coverage as a metric is a tool, not a goal. This card establishes the right tests, not high coverage numbers. If the engineer wants to add coverage tooling, separate card.
- **Performance / memory regression tests.** Card 0005 is the right home for memory measurement if it ends up needing automation. CPU/perf tests are not yet a thing the project asks for.
- **Snapshot tests** of view rendering. Not yet — they add a third-party dependency, complicate code signing, and the SwiftUI view layer is still churning.
- **Mutation testing, fuzz testing, etc.** Not yet.
- **Tests for future cards** that haven't shipped yet (0003, 0004). When those cards land, they should each include their own targeted test additions in their acceptance.

### Why P1 / XL

P1 because every other card we ship from now on benefits from a regression net underneath it. Specifically: card 0005 (memory audit) is going to make architectural changes that touch the playback pipeline, and having a gapless-playback regression test in place BEFORE that card lands would be a huge confidence boost. Card 0004 (album art) is going to touch the SwiftUI view tree heavily, and having UI tests for the existing user flows would catch any inadvertent regressions.

XL because this is real work: setting up a test target, choosing a framework, writing fixtures, writing the static checks, writing the unit tests, writing the integration tests, writing the UI tests, documenting it all. None of these layers is hard, but there are a lot of them.

### Manager dispatch note (not for the engineer)

This card is large enough that the manager should consider **splitting it into 3-4 smaller cards before dispatching**, in approximately this order:

- **0006a — Test infrastructure & Layer 1 (static checks):** set up the test target, generate fixtures, write the AVURLAsset / sandbox-bookmark / @Published-allowlist static checks. This is the highest-value work in the smallest blast radius. Could be S/M.
- **0006b — Layer 2 (unit tests):** all the model-level unit tests. Builds on 0006a's infrastructure. Could be M.
- **0006c — Layer 3a (integration tests):** real-AVFoundation tests for PlayerEngine. M.
- **0006d — Layer 3b (UI tests):** XCUITest for the user flows. M/L.

The split lets a single engineer ship value incrementally and lets QA validate each layer separately. The manager and user should decide on splitting before dispatch.

If dispatched as one XL card, this will take a long time, and the engineer should be told that incremental commits at each layer boundary are expected — not one giant final commit.

This card is in `backlog/`. It does not have any hard file collisions with cards 0003, 0004, or 0005 (it lives mostly in a new `JamBoxTests/` directory and only touches `project.yml` for the target wiring), so it could in theory run in parallel with 0005 — but the engineer for 0006 will need to add `@testable import JamBox` and possibly tweak access modifiers in the production source, which could trip on 0005's in-flight changes to `PlayerEngine`. Sequencing is the manager's call.

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

**Framework choice committed (XCTest / Swift Testing):**

## Log
- 2026-04-06 — manager created card in backlog/, recommended split into 4 sub-cards before dispatch

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
