---
id: NNNN
title: <imperative one-liner: "Add X", "Fix Y", "Refactor Z">
created: YYYY-MM-DD
needs_designer: true      # set false ONLY for pure refactors with zero user-visible delta
designer: null            # set when dispatched to a designer (pre-engineering)
design_review: null       # set when dispatched to a designer for the post-QA review
engineer: null
qa: null
parent: null
priority: P2
estimate: M
depends_on: []
touches:
  - path/to/file.swift
acceptance:
  - <observable behavior 1>
  - <observable behavior 2>
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - <invariants from .pm/README.md §7 that apply to this card>
---

## Context
Why this card exists. Link to roadmap line, user quote, screenshot, or parent card.

## Design
*Filled in by the designer BEFORE engineering starts. Required when `needs_designer: true`. For non-visual cards, collapses to "no visual change" + a one-line note. See .pm/README.md §4b.*

## User Risks & Edge Cases
*Filled in by the designer BEFORE engineering starts. Required when `needs_designer: true`. The designer's voice-of-the-user pass: happy path, empty/malformed/scale/concurrency/wrong-actions/a11y/recovery. Each item tagged [MUST HANDLE] / [NICE TO HANDLE] / [FUTURE WORK] / [WONT HAPPEN]. See .pm/README.md §4b step 5.*

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

## Log
- YYYY-MM-DD HH:MM — <agent-name> <event>

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

## Design Review
*Filled in by the designer AFTER QA approves. Required when `needs_designer: true`. See .pm/README.md §6c.*

### Original risks revisited

### Newly surfaced concerns

### Recommendation

## Manager Decision
*Filled in by the manager when closing or kicking back.*
