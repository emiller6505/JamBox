# JamBox PM Board — Agent Protocol

**Read this file in full before doing anything.** It is the contract every agent and the manager follow. If something here conflicts with a verbal instruction, this file wins unless the manager updates it.

---

## 1. Roles

- **Manager** — the human's proxy. Receives feature requests, asks clarifying questions, writes cards, dispatches agents, processes QA reports, and closes cards. There is exactly one manager.
- **Engineer agent** — implements one card at a time. There may be many engineers running concurrently. Each engineer is spawned with a specific card id; it does not browse the board for work.
- **QA agent** — spawned fresh per card. The QA's only job is to audit one card's completed engineer work against its acceptance criteria and the project-wide invariants (§7). QA never writes feature code. QA may create new cards for issues it finds. Multiple QA agents may run concurrently on different cards.

Agents are spawned by the manager via the `Agent` tool. They terminate when their assigned task is complete — there is no long-running process to "kill."

---

## 2. The board is the filesystem

```
.pm/
  README.md         ← you are here
  board.md          ← human-readable index, regenerated from lanes
  CARD-TEMPLATE.md
  backlog/          ← raw, not ready to work
  ready/            ← groomed, awaiting engineer dispatch
  in-progress/      ← engineer working, exactly one owner
  qa/               ← engineer done, QA auditing
  blocked/          ← stuck on external input
  done/             ← signed off by engineer + QA, closed by manager
  archive/          ← old done cards, out of sight
```

A card's **lane is its status**. There is no `status:` field in frontmatter — the folder *is* the truth. Move cards with `git mv` so the rename is atomic.

---

## 3. Card format

Filename: `NNNN-kebab-slug.md` where `NNNN` is a zero-padded id. Reference cards in commits and chat as "card 0007".

```markdown
---
id: 0007
title: Add 10-band equalizer to NowPlayingBar
created: 2026-04-06
engineer: null            # set when dispatched to an engineer
qa: null                  # set when dispatched to QA
parent: null              # if this card was spawned by QA, the parent card id
priority: P2              # P0 critical · P1 important · P2 normal · P3 nice-to-have
estimate: M               # S/M/L/XL — gut feel
depends_on: []            # other card ids
touches:                  # files this card will likely modify
  - JamBox/NowPlayingBar.swift
  - JamBox/PlayerEngine.swift
acceptance:
  - 10-band EQ visible in now-playing bar
  - settings persist across launches
  - no audible glitch when toggling bands
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - all AVURLAsset creations still pass AVURLAssetPreferPreciseDurationAndTimingKey
---

## Context
Why this exists. Link to roadmap, user quote, screenshots, parent card.

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits.*

## Log
Append-only chronological record. Newest at bottom.

## Self-Audit
*Filled in by the engineer before handing off to QA.*

## QA Report
*Filled in by the QA agent. PASS/FAIL per acceptance bullet, plus invariant checks and any new findings.*

## Manager Decision
*Filled in by the manager when closing or kicking back.*
```

---

## 4. Lifecycle

```
backlog → ready → in-progress → qa → done
                       ↑         ↓
                       └─────────┘
                       (kickback on QA fail)
```

Every transition: `mv` the file + append a `## Log` line + commit `pm: <id> → <lane>`.

Kickback flow when QA finds issues:
1. QA writes findings to `## QA Report`.
2. For each issue, QA either:
   - **Inline fix** (small, in scope): note it in the report. Card moves back to `in-progress/` for the original engineer.
   - **New card** (out of scope, or substantial enough to track separately): QA creates a child card with `parent: <original-id>` and places it in `ready/`. The original card may still proceed to `done/` if its own acceptance is met.
3. Manager reviews the QA report and decides: close to `done/`, kick back to `in-progress/`, or escalate.

---

## 5. **MANDATORY for engineers: plan mode before code**

Every engineer picking up a card MUST plan before editing.

1. Confirm assignment: set `engineer:` in frontmatter, move card to `in-progress/`, log entry, commit.
2. **Enter plan mode** (`EnterPlanMode` tool). While in plan mode you may read files and run searches, but you may NOT edit, write, or run mutating commands.
3. Draft a complete `## Plan` covering:
   - **Approach:** what you will change at a high level.
   - **Files:** every file you expect to touch (update `touches:` to match).
   - **Risks:** what could break. Specifically call out gapless playback, AVURLAsset rules, sandbox bookmarks, and two-phase loading if your card is in that area.
   - **Open questions:** anything you'd ask the manager. Leave unanswered if blocked.
4. Commit the updated card with `pm: <id> plan ready`.
5. **Exit plan mode** (`ExitPlanMode`) and begin implementation.

**No exceptions.** Even a one-line fix gets a one-paragraph plan. The plan is the artifact that lets the manager, the QA agent, and any future agent understand intent without re-deriving it from the diff.

If during implementation the plan turns out wrong: stop, re-enter plan mode, append a `### Revision` to `## Plan` (don't delete the original), then resume.

---

## 6. **MANDATORY for engineers: self-audit before QA handoff**

You do not get to declare yourself done. You audit your own work first, write the audit into the card, and only then move to `qa/`. The self-audit is the first line of defense — QA is the second. Don't ship sloppy work to QA expecting them to catch it; that wastes a cycle and fails the card.

The self-audit checklist — every item, every time, written into `## Self-Audit`:

1. **Re-read every file you modified, top to bottom.** Not just the diff. Look for dead code, debug prints, commented-out blocks, inconsistent style, comments that no longer match the code.
2. **Walk every acceptance bullet** in the frontmatter. For each one, write one line stating exactly how it is satisfied, with file:line references where possible. If a bullet is NOT satisfied, you are not done.
3. **Build it.** Run `xcodebuild -project JamBox.xcodeproj -scheme JamBox build`. Paste the final status line. Warnings are not a pass — explain any new ones.
4. **Run the project-wide invariants** (§7). For each one that applies to your card, state how you verified it.
5. **Hostile diff review.** Run `git diff` against `main`. Read the entire diff as if you were a hostile reviewer. Note anything you'd flag.
6. **Touched-files reconciliation.** Compare actual changed files against `touches:`. If they differ, update the frontmatter and explain why in the log.
7. **Scope check.** Did you do anything the card did not ask for? If yes: revert it, or split it into a new backlog card. Do not smuggle unrelated changes into a card.

Only after all seven steps are written into `## Self-Audit` may you move the card to `qa/` and notify the manager.

If any step fails and you can't fix it: move to `blocked/` with a clear reason, not to `qa/`.

---

## 6b. **MANDATORY for QA: independent audit**

QA's job is to audit, not to fix. QA does **not** edit feature code. If QA finds an issue, QA documents it and either kicks the card back or files a child card — the original engineer fixes it.

When the manager dispatches the QA agent on a card in `qa/`:

1. Set `qa:` in frontmatter, log entry, commit `pm: <id> qa start`.
2. **Independent of the engineer's self-audit**, run the full QA checklist:
   - **Read the card's `## Plan` first** to understand intent. Then read the engineer's `## Self-Audit` — but treat it as a hint, not gospel.
   - **Read every file in `touches:` top to bottom.** Not just the diff. Code can be locally correct but globally broken.
   - **Read the diff:** `git diff main -- <touched files>`. Every line. Look for:
     - Unrelated changes (scope creep).
     - Removed code that broke something.
     - New code paths that aren't covered by acceptance.
     - Style inconsistencies with surrounding code.
     - Magic numbers, debug prints, TODO/FIXME, commented-out blocks.
   - **Walk every acceptance bullet.** For each: PASS or FAIL with a one-line justification and file:line reference.
   - **Walk every project-wide invariant in §7.** For each that applies: PASS or FAIL with justification. **The AVURLAsset rule (§7.1) must be checked on every card that touches audio code, no exceptions.**
   - **Build it yourself.** Don't trust the engineer's build output. Run `xcodebuild -project JamBox.xcodeproj -scheme JamBox build`. Paste the final status.
   - **Look for what the card *didn't* ask but should have.** Did the engineer miss an obvious related case? E.g. "added a setting but didn't persist it across launches." If so, file a finding.
3. Write the full report into `## QA Report` with this structure:
   ```
   ### Acceptance
   - [PASS/FAIL] <bullet> — <evidence>
   ### Invariants
   - [PASS/FAIL/N/A] §7.1 AVURLAsset — <evidence>
   - …
   ### Findings
   - [BLOCKER/MAJOR/MINOR/NIT] <description> — <file:line>
   ### Recommendation
   - [APPROVE / KICK BACK / APPROVE WITH CHILD CARDS]
   ```
4. For findings classified BLOCKER or MAJOR: kick the card back to `in-progress/` (assign back to original `engineer:`) and log it.
5. For findings that are out of scope or substantial enough to track separately: create a child card in `ready/` with `parent: <original-id>` and a clear acceptance bullet. Reference the child card id in the QA Report.
6. Move the card to its next lane (`in-progress/` on kickback, or leave in `qa/` for the manager to close on approve), commit, and report back to the manager with a one-paragraph summary.

QA may not skip any of these steps, even on a one-line card. The point of QA is to be the bulwark; cutting corners defeats the purpose.

---

## 7. Project-wide invariants (always in scope)

These are non-negotiable. Any card that violates them fails QA.

1. **AVURLAsset:** every `AVURLAsset` MUST be constructed with `AVURLAssetPreferPreciseDurationAndTimingKey: true`. Never use `AVPlayerItem(url:)` — always build the asset with the option first, then `AVPlayerItem(asset:)`. Violating this re-introduces the FLAC duration bug.
2. **Gapless playback:** the `AVQueuePlayer` 3-item lookahead in `PlayerEngine` is sacred. Any change near `enqueueMoreIfNeeded` or queue management must preserve gapless behavior.
3. **Two-phase loading:** fast filesystem scan first, then async metadata enrichment. Don't block UI on metadata.
4. **Sandbox bookmarks:** every `startAccessingSecurityScopedResource` must have a balanced `stopAccessingSecurityScopedResource`.
5. **Xcode project regeneration:** if you add or remove a source file, run `xcodegen generate` and commit the regenerated `JamBox.xcodeproj`.
6. **Build green:** `xcodebuild … build` must pass on `main` after every merged card.

---

## 8. Concurrency & collision rules

- **One engineer per card.** Filesystem rename is atomic — first writer wins.
- **No two `in-progress/` cards may share a file in `touches:`** unless the manager has explicitly serialized them. The manager checks this at dispatch time.
- **QA is per-card.** Each card in `qa/` gets its own freshly-spawned QA agent. Multiple QA agents may run concurrently. Each one only reads and reports on its assigned card.
- **`git pull --rebase` before claiming and before every commit.**
- **Commit often** with `pm: <id> <verb>` prefix so the log stays scannable.

---

## 9. Quick reference

### Engineer loop
```
1. git pull --rebase
2. Read .pm/README.md and the assigned card in .pm/ready/
3. mv card to .pm/in-progress/, set engineer:, log, commit
4. EnterPlanMode → write ## Plan → commit → ExitPlanMode
5. Implement
6. Self-audit (§6) → write ## Self-Audit
7. mv to .pm/qa/, log, commit, notify manager
8. STOP. Wait. Do not pick up another card.
```

### QA loop
```
1. git pull --rebase
2. Read .pm/README.md and the assigned card in .pm/qa/
3. set qa: in frontmatter, log, commit
4. Run §6b checklist independently
5. Write ## QA Report with full structure
6. If kickback: mv to in-progress/, commit. Else: leave in qa/.
7. If new findings warrant child cards: create them in .pm/ready/ with parent:
8. Report one-paragraph summary back to manager
9. STOP.
```

### Manager loop
```
1. Receive feature from human, ask clarifying questions
2. Write card in .pm/ready/
3. Spawn engineer agent pointed at the card id
4. When engineer hands off to qa/, spawn QA agent pointed at the card id
5. Read QA report:
   - APPROVE → mv to done/, write ## Manager Decision, commit, notify human
   - KICK BACK → respawn original engineer with QA findings
   - CHILD CARDS → triage them; dispatch new engineers as needed
6. When all related cards (including QA-spawned children) are in done/, the feature is closed.
```
