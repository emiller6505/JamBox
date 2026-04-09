---
id: 0006a
title: Test infrastructure — target, fixtures, Layer 1 static checks
created: 2026-04-08
needs_designer: false
designer: null
design_review: null
engineer: null
qa: null
parent: 0006
priority: P1
estimate: M
depends_on: []
touches:
  - project.yml
  - JamBox.xcodeproj
  - JamBoxTests/
  - TESTING.md
  - CLAUDE.md
acceptance:
  - A new XCTest (or Swift Testing — engineer's choice, documented) test target exists in `project.yml`, wired so `xcodegen generate` produces a valid `JamBox.xcodeproj` with the test target included. The regenerated `.xcodeproj` is committed.
  - `xcodebuild -project JamBox.xcodeproj -scheme JamBox -destination 'platform=macOS' test` runs from a clean checkout with no extra setup and exits 0. Engineer pastes the final summary line into `## Self-Audit`.
  - The chosen test framework (XCTest vs Swift Testing) is documented in a new `TESTING.md` at the repo root, with a one-paragraph rationale. If Xcode 16+ is available, Swift Testing is acceptable; otherwise XCTest. Engineer commits to one and explains why.
  - Audio fixtures live in `JamBoxTests/Fixtures/` and include, AT MINIMUM:
  - "  - 1 mp3 (1-3 seconds, silence or tone, ID3 tags with known title/artist/album/track number)"
  - "  - 1 m4a (AAC, 1-3 seconds, iTunes-style tags)"
  - "  - 1 flac at 16-bit (1-3 seconds, vorb/TITLE / vorb/ARTIST / vorb/ALBUM tags with known values — regression coverage for the AVFoundation-commonMetadata-empty-for-FLAC bug)"
  - "  - 1 flac at 24-bit (1-3 seconds — explicitly required as the regression coverage for card 0020, where the format badge hid for every FLAC file because reviewers had no real 24-bit FLAC to test against)"
  - "  - 1 wav (LPCM, 1-3 seconds)"
  - "  - 1 aiff (LPCM, 1-3 seconds)"
  - "  - Each fixture is under 100 KB."
  - A reproducible `JamBoxTests/Fixtures/generate.sh` script using `ffmpeg` and/or `afconvert` regenerates every fixture from scratch deterministically. The script is committed and executable. Future contributors can regenerate fixtures without guessing.
  - **Layer 1 static check — AVURLAsset precise-timing-key (§7.1, the single highest-value test in the entire suite):** A test (XCTest) reads every `.swift` file under `JamBox/` as text and fails if any `AVURLAsset(` construction does NOT include `AVURLAssetPreferPreciseDurationAndTimingKey` in the same statement (or in an `assetOptions` constant referenced from the construction). False positives are acceptable as long as the test fails clearly enough that the engineer knows what to fix. False negatives are unacceptable.
  - **Layer 1 static check — sandbox bookmark balance (§7.4):** A test that greps the source for `startAccessingSecurityScopedResource` and `stopAccessingSecurityScopedResource` and verifies counts are equal OR that every start has a matching stop in a balanced pattern (deferred, scoped, or paired). A simple count-equality check is acceptable for v1 if the engineer documents the limitation.
  - **Layer 1 static check — `PlayerEngine` `@Published` allowlist (regression defense for card 0002):** A test that introspects `PlayerEngine`'s `@Published` properties (via reflection or a hand-maintained allowlist constant) and fails if any new `@Published` is added without being in the allowlist. The allowlist is small — current values are roughly `isPlaying`, `currentTrack`, `currentArtwork`, `tracks`, `currentFormat`. The test exists to force a code-review conversation any time a new `@Published` lands on `PlayerEngine`, because the click-race bug from card 0002 is one such addition away from coming back.
  - **Layer 1 static check — single AVURLAsset construction site rule (defense for card 0012's `makeAssetItem` extraction and §7.1):** A test that asserts the count of `AVURLAsset(` constructions in `JamBox/PlayerEngine.swift` is exactly 1 (the one inside `makeAssetItem`), counting the artwork search path separately. The test is brittle by intent — if a future engineer adds a second construction site, the test fails and forces them to either use the helper or update the test deliberately. Engineer can implement this as a single test with two grep counts.
  - All Layer 1 checks live in a `JamBoxTests/StaticChecks/` directory or similar. They run with the rest of the suite via `xcodebuild test`.
  - `TESTING.md` documents: how to run the suite locally (`xcodebuild test` command), where fixtures live, how `generate.sh` works, the framework choice and why, what each Layer 1 check defends against (one paragraph each, naming the card it traces back to), and how to add a new fixture.
  - `CLAUDE.md` gains a one-paragraph "Testing" subsection that points to `TESTING.md` and adds the test command to the existing "Build Commands" list.
  - No production source files are touched UNLESS the engineer needs to add `@testable import JamBox` access or expose internal types for testability. Any such change is flagged in `## Self-Audit` step 7 (scope check) with a one-line justification.
  - The test target's existence does NOT break the existing app build. `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` still passes cleanly with no new warnings.
  - `xcodebuild test` runtime is documented in the Self-Audit. If any single test takes > 5 seconds, it gets a comment explaining why.
  - Engineer commits the regenerated `JamBox.xcodeproj` (the `.gitignore` currently excludes it — engineer must use `git add -f` or update `.gitignore` deliberately; document the choice in the log).
  - §7.1 / §7.2 / §7.3 / §7.4 / §7.5 / §7.6 all preserved (this card adds tests, doesn't change app behavior).
---

## Context

This card is the first of four split from card 0006 (automated test coverage), recommended split documented in 0006's "Manager dispatch note" section. 0006 was archived as a parent on 2026-04-08; the four sub-cards are 0006a (this card), 0006b (unit tests), 0006c (integration tests), 0006d (UI tests). Manager dispatches them sequentially: 0006a first, then 0006b after 0006a closes, etc.

**Why 0006a goes first:** it is the foundation layer with the smallest blast radius and the highest immediate value. It establishes the test target, generates the fixtures, and ships the Layer 1 static checks — the cheapest, most-mechanical regression defenses in the entire suite. The AVURLAsset grep check alone is the most important regression test in the project.

**Why this card's fixture requirements are explicit and load-bearing.** Cards 0020 and 0021 (hotfixes shipped 2026-04-08) both happened because the engineer, QA, and §6c reviewers were all reading code without running it against real input. The format badge bug (0020) hid the badge for every FLAC file because no reviewer had a 24-bit FLAC to test on. The spacebar focus bug (0021) was invisible to per-card review because no one held cards 0008 + 0011 + 0012 in mind together at the moment of launch. Real fixtures are the systemic fix for the first class of bug. The 24-bit FLAC fixture is non-negotiable.

**Framework choice is the engineer's call.** Both XCTest and Swift Testing are acceptable. The card is opinionated only that the choice be documented and that the suite be runnable from `xcodebuild test` without extra setup.

**Out of scope** (will be covered by 0006b/c/d or never):
- Layer 2 unit tests (Track parsing, FileScanner, ThemeManager) → 0006b
- Layer 3a integration tests (PlayerEngine real-file tests, gapless lookahead, FLAC duration) → 0006c
- Layer 3b XCUITest UI flows → 0006d
- CI configuration (GitHub Actions etc.) → separate future card if desired
- Code coverage tooling → separate future card
- Snapshot tests → not on the roadmap

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

**Framework choice committed (XCTest / Swift Testing):**

## Log
- 2026-04-08 — manager split card 0006 into 0006a/b/c/d; created this card in ready/

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
