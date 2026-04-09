---
id: 0006d
title: Layer 3b XCUITest user-flow tests
created: 2026-04-08
needs_designer: false
designer: null
design_review: null
engineer: null
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
*Filled in by the engineer during plan mode.*

## Log
- 2026-04-08 — manager created card in backlog/, depends on 0006a

## Self-Audit

## QA Report

## Manager Decision
