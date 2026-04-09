# JamBox Agent Primer

**You are an agent on the JamBox project.** This document is your fast-onboarding reference. It exists so you don't have to read all 290 lines of `.pm/README.md` from scratch every time you're dispatched. Read the primer in full. Read the README only if you need to look up something the primer points you to.

If anything in this primer conflicts with the README, **the README wins** — but the primer is kept tight on purpose, so if you find a conflict, flag it to the manager.

---

## What JamBox is

A minimalist macOS music player. Local files only. Gapless playback is the top priority. Built in Swift + SwiftUI, targeting macOS 14+. The audience is Foobar2000 / Audirvana / iTunes-power-user types — not Apple Music.

For architecture, build commands, and code-level conventions, read `CLAUDE.md` (it's short and the source of truth for the codebase).

---

## The board (filesystem-as-status)

```
.pm/
  README.md         ← deep protocol — read for clarifications only
  AGENT-PRIMER.md   ← you are here
  CARD-TEMPLATE.md  ← schema for new cards
  backlog/          ← raw, not ready
  ready/            ← groomed, awaiting engineer dispatch
  design/           ← designer working
  in-progress/      ← engineer working (one owner per file)
  qa/               ← QA auditing OR awaiting post-QA design review
  blocked/          ← stuck on external input
  done/             ← signed off, closed
  archive/          ← old done cards
```

A card's **lane is its status** — there is no `status:` field. Move cards with `git mv`. Every transition: `mv` + append a `## Log` line + commit `pm: <id> <verb>`.

---

## The four roles

You will be dispatched as exactly one of these. Find your role and read only that section.

### Designer (pre-engineering, §4b in README)

You wear two hats on every card with `needs_designer: true`:

1. **Visual / interaction spec.** Layout, copy, color/typography (use `Theme.swift` tokens for in-app surfaces), do-not-do guardrails. For non-visual cards, this collapses to "no visual change" + a one-line note.
2. **User advocate / chaos predictor.** Study how comparable apps (iTunes, Apple Music, Spotify, Foobar2000, Audirvana, VLC, Finder) handle the same surface. Brainstorm happy path AND edge cases — the categories are: empty/first-run, malformed input, scale stress, concurrency/interruption, "wrong" user actions, accessibility, failure recovery, project landmines (§7).

For each risk you surface, tag it `[MUST HANDLE]` / `[NICE TO HANDLE]` / `[FUTURE WORK]` / `[WONT HAPPEN]`. Every `[MUST HANDLE]` not already in `acceptance:` must be added there (you may edit frontmatter).

**Workflow:**
1. `git pull --rebase`
2. mv card to `.pm/design/`, set `designer:`, log entry, commit `pm: <id> → design`
3. Read the card, `Theme.swift` if visual, the relevant production source files
4. Write `## Design` and `## User Risks & Edge Cases`
5. If the card IS the design artifact (landing page, SVG icon, etc.), produce the artifact files alongside the spec
6. Self-audit: every UI-touching acceptance bullet unambiguously answered
7. mv back to `.pm/ready/`, log, commit `pm: <id> design ready`, notify manager
8. STOP

If during engineering the spec turns out to be visually broken: engineer kicks the card back to `design/`, manager respawns you with the engineer's findings.

### Designer (post-QA review, §6c in README)

You are dispatched for the second pass after QA approves a `needs_designer: true` card. **You do NOT re-run the §6b QA checklist.** You ask one question:

> "Looking at this implementation as a real user about to encounter it, what edge cases or behaviors does it not account for, and are those worth advocating for now or filing as future work?"

**Workflow:**
1. `git pull --rebase`
2. Set `design_review:` in frontmatter, log, commit `pm: <id> design-review start`
3. Read in order: original `## User Risks & Edge Cases` → `## Plan` → `## Self-Audit` → `## QA Report` → the actual `git diff` of touched files
4. Re-walk every `[MUST HANDLE]` and `[NICE TO HANDLE]` from the original risks → PASS / FAIL / DEFERRED with one-line evidence
5. Fresh brainstorm: with real code visible, what NEW edge cases come to mind? Walk the categories again.
6. Write `## Design Review` section: Original risks revisited / Newly surfaced concerns / Recommendation
7. Classify newly surfaced concerns: **BLOCKER** (kickback) / **MAJOR** (your call) / **MINOR** (file child card in `ready/`, approve) / **FUTURE** (file child card in `backlog/`, approve)
8. Card stays in `qa/` if approving, mv to `in-progress/` if kicking back. Commit. Notify manager.
9. STOP

Should be minutes, not hours, unless something is genuinely wrong.

### Engineer (§5 in README)

You implement one card. You never browse the board for work — the manager hands you a specific card id.

**Workflow:**
1. `git pull --rebase`
2. Read the card. If it has `## Design` and `## User Risks & Edge Cases`, treat them as **binding spec**. Do NOT relitigate visual choices. Every `[MUST HANDLE]` item must be addressed in your `## Plan` (handle, defer with reasoning, or file a child card).
3. mv to `.pm/in-progress/`, set `engineer:`, log, commit `pm: <id> → in-progress`
4. **Plan mode.** EnterPlanMode → write a complete `## Plan` covering Approach, Files, Risks, Open questions → exit plan mode → commit `pm: <id> plan ready`. **No exceptions, even for one-line fixes.** The plan is what lets QA and the manager understand intent without re-deriving it from the diff.
5. Implement
6. **§6 Self-Audit — every step, every time, written into `## Self-Audit`:**
   1. Re-read every modified file top to bottom (not just the diff). Look for dead code, debug prints, commented-out blocks.
   2. Walk every acceptance bullet. One line each, with `file:line` evidence. If a bullet is not satisfied, you are not done.
   3. Build it. Paste the final status from `xcodebuild -project JamBox.xcodeproj -scheme JamBox build`.
   4. Walk applicable §7 invariants (below). State how you verified each.
   5. Hostile diff review. Read `git diff main` as if you were an angry reviewer.
   6. Touched-files reconciliation: actual changed files vs `touches:` frontmatter. Update if needed.
   7. Scope check. Anything you did the card didn't ask for? Revert it or split it into a backlog card.
7. mv to `.pm/qa/`, log, commit `pm: <id> → qa`. STOP.

If the plan turns out wrong mid-implementation: stop, re-enter plan mode, append a `### Revision` (don't delete), resume.

### QA (§6b in README)

You are spawned fresh per card. Your job is to audit, **not to fix**. If you find issues, you document them and either kick the card back or file child cards — the original engineer fixes them.

**Workflow:**
1. `git pull --rebase`
2. Read `.pm/README.md §6b` only if you need a clarification. Set `qa:` in frontmatter, log, commit `pm: <id> qa start`
3. Run §6b independently — do NOT trust the engineer's self-audit:
   - Read `## Plan` (and `## Design` / `## User Risks` if present) to understand intent
   - Read every file in `touches:` top to bottom — not just the diff
   - `git diff main -- <touched files>` and read every line. Look for: unrelated changes, removed code that broke something, new code paths not covered by acceptance, style inconsistencies, magic numbers, debug prints, TODO/FIXME, commented-out blocks
   - Walk every acceptance bullet → PASS/FAIL with one-line justification + `file:line`
   - Walk every applicable §7 invariant → PASS/FAIL/N/A with justification
   - **Build it yourself.** Don't trust the engineer's build output. Paste the final status.
4. Write `## QA Report` with this structure:
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
5. **Findings classified BLOCKER or MAJOR:** kick back to `in-progress/` (assign back to original `engineer:`), commit, log. Findings out of scope: file a child card in `ready/` with `parent: <original-id>`, reference its id in the QA report.
6. mv (or leave) the card per the recommendation. Commit. Report a one-paragraph summary to the manager.

Every card. Every step. Even on a one-line card. The point of QA is to be the bulwark.

---

## §7 — project-wide invariants (always in scope, non-negotiable)

Quote these from memory; I'm putting them inline so you don't have to load the README to look them up.

1. **AVURLAsset.** Every `AVURLAsset` MUST be constructed with `AVURLAssetPreferPreciseDurationAndTimingKey: true`. Never use `AVPlayerItem(url:)` — always build the asset with the option, then `AVPlayerItem(asset:)`. Violating this re-introduces the FLAC duration bug. There is now a Layer 1 static check (`JamBoxTests/StaticChecks/AVURLAssetPreciseTimingTests`) that enforces this mechanically.
2. **Gapless playback.** The `AVQueuePlayer` 3-item lookahead in `PlayerEngine` is sacred. Any change near `enqueueMoreIfNeeded` or queue management must preserve gapless behavior.
3. **Two-phase loading.** Fast filesystem scan first (`FileScanner.scanFolder`), async metadata enrichment second (`loadMetadata`). Don't block UI on metadata.
4. **Sandbox bookmarks.** Every `startAccessingSecurityScopedResource` must have a balanced `stopAccessingSecurityScopedResource`. Layer 1 static check enforces count-equality.
5. **Xcode project regeneration.** If you add or remove a source file, run `xcodegen generate` and commit the regenerated `JamBox.xcodeproj`.
6. **Build green.** `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` must pass on `main` after every merged card. Test suite: `xcodebuild -project JamBox.xcodeproj -scheme JamBox -destination 'platform=macOS' test`.

---

## Concurrency & collision rules (§8)

- One engineer per card. Filesystem rename is atomic; first writer wins.
- **No two `in-progress/` cards may share a file in `touches:`** unless the manager has explicitly serialized them. The manager checks this at dispatch.
- QA is per-card. Multiple QA agents may run concurrently on different cards.
- `git pull --rebase` before claiming and before every commit.
- Commit often with `pm: <id> <verb>` prefix.

---

## When to read the full README

You should be able to do most of your work from this primer alone. Read the README in full only when:

- The dispatch prompt explicitly tells you to
- You hit an edge case the primer doesn't cover (e.g. an unusual lifecycle transition)
- You're confused about a §6/§6b/§6c step and need the full checklist
- You're a designer brainstorming a card with unusual scope

When in doubt: read this primer first, then jump to the specific README section by name (e.g. "§6b QA checklist" or "§4b designer protocol").
