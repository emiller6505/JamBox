# JamBox PM Board — Agent Protocol

**Read this file in full before doing anything.** It is the contract every agent and the manager follow. If something here conflicts with a verbal instruction, this file wins unless the manager updates it.

---

## 1. Roles

- **Manager** — the human's proxy. Receives feature requests, asks clarifying questions, writes cards, dispatches agents, processes design and QA reports, and closes cards. There is exactly one manager.
- **Designer agent** — wears two hats on every card it's assigned to. **(1) Visual and interaction spec:** defines layout, hierarchy, copy, color/typography (referencing existing `Theme.swift` tokens where possible), sketches in ASCII or markdown, and explicit do-not-do guardrails. May produce static asset deliverables (HTML/CSS for landing pages, SVG icons) when the card IS the design artifact. **(2) User advocate and chaos predictor:** the designer is the voice of the real user in the room. Studies how comparable apps (iTunes, Apple Music, Spotify, Foobar2000, VLC, Finder, etc.) handle the same surface. Brainstorms the happy path AND the edge cases: empty states, malformed input, interrupted flows, double-clicks, rapid repeated actions, huge libraries, missing files, permission denials, race conditions, accessibility, keyboard-only users, the user who does the "wrong" thing first. Surfaces these as written concerns BEFORE engineering plans, so the engineer can either handle them or consciously defer them. The designer's `## User Risks & Edge Cases` section is binding: every item must be either addressed by the engineer's plan, deferred with justification, or filed as a child card. Designers also do a short post-QA pass (§6c) asking "did the implementation miss anything I flagged, or anything I should have flagged?" Multiple designers may run concurrently on different cards.
- **Engineer agent** — implements one card at a time. There may be many engineers running concurrently. Each engineer is spawned with a specific card id; it does not browse the board for work. If a card has a `## Design` section, the engineer treats it as binding spec and does not relitigate visual choices in plan mode. If a card has a `## User Risks & Edge Cases` section, the engineer must address every item in `## Plan` — either by handling it in scope, by explicit deferral with reasoning, or by filing a follow-up child card before implementation begins.
- **QA agent** — spawned fresh per card. The QA's only job is to audit one card's completed engineer (and designer, if applicable) work against its acceptance criteria, the design spec, and the project-wide invariants (§7). QA never writes feature code. QA may create new cards for issues it finds. Multiple QA agents may run concurrently on different cards.

Agents are spawned by the manager via the `Agent` tool. They terminate when their assigned task is complete — there is no long-running process to "kill."

---

## 2. The board is the filesystem

```
.pm/
  README.md         ← you are here
  board.md          ← human-readable index, regenerated from lanes
  CARD-TEMPLATE.md
  backlog/          ← raw, not ready to work
  ready/            ← groomed, awaiting engineer dispatch (design done if needed)
  design/           ← designer working, card flagged needs_design: true
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
backlog → ready → [design] → in-progress → qa → [design-review] → done
                      ↑                           ↑           ↓
                      └───────────────────────────┴───────────┘
                       (kickback on QA fail or design-review escalation)
```

The `[design]` step is optional. It is mandatory for cards flagged `needs_designer: true` in frontmatter. When present, the manager dispatches a designer agent BEFORE any engineer. The designer fills in `## Design` and `## User Risks & Edge Cases`, leaves the card in `design/` while working, then moves it back to `ready/` (with a log line and commit) when handing off to engineering. Cards without `needs_designer: true` skip the design lane entirely and go straight from `ready/` to `in-progress/`.

The `[design-review]` step is also conditional on `needs_designer: true`. After QA approves a card, the manager re-dispatches a designer (any designer, not necessarily the original) for a short post-QA pass (§6c) before closing. This pass exists to catch user-facing edge cases the engineer and QA missed. The card stays in `qa/` during this pass; the designer either signs off (manager moves to `done/`) or escalates concerns back to `in-progress/` or as new child cards. Cards without `needs_designer: true` skip this step too and go straight from `qa/` to `done/` on QA approval.

Every transition: `mv` the file + append a `## Log` line + commit `pm: <id> → <lane>`.

Kickback flow when QA finds issues:
1. QA writes findings to `## QA Report`.
2. For each issue, QA either:
   - **Inline fix** (small, in scope): note it in the report. Card moves back to `in-progress/` for the original engineer.
   - **New card** (out of scope, or substantial enough to track separately): QA creates a child card with `parent: <original-id>` and places it in `ready/`. The original card may still proceed to `done/` if its own acceptance is met.
3. Manager reviews the QA report and decides: close to `done/`, kick back to `in-progress/`, or escalate.

---

## 4b. **MANDATORY for designers: spec + advocate before code**

A designer is dispatched on every card flagged `needs_designer: true`. The designer wears two hats: visual authority AND user advocate / chaos predictor. Engineering treats `## Design` and `## User Risks & Edge Cases` as binding spec.

When to set `needs_designer: true`: any card with user-visible behavior. This includes purely visual changes, but ALSO includes cards that look "internal" but change how the user interacts with the app — keyboard shortcuts, sort/filter logic, queue behavior, error messages, file handling, performance under load. Pure refactors with zero user-visible delta are the only cards that should leave the flag false.

Designer workflow:

1. Confirm assignment: set `designer:` in frontmatter, move card from `ready/` to `design/`, log entry, commit `pm: <id> → design`.
2. Read the card's `## Context`, the user request, and any referenced screenshots or assets. Read `JamBox/Theme.swift` for in-app tokens. For visual work on in-app surfaces, your spec MUST reuse Theme tokens by name. For out-of-app surfaces (landing pages, marketing assets, GitHub READMEs, icons), invent fresh visual choices but reference the JamBox brand: phonograph icon (`docs/phonograph.png`), candy palette (hot pink → deep purple → cyan), minimalist tone.
3. **Study comparable apps.** Before writing anything, think through how iTunes / Apple Music / Spotify / Foobar2000 / VLC / Finder (or whichever is closest to the surface in question) handle the same feature. What did they get right? What gotchas do their users hit? You don't have to copy them, but you should know what the user's mental model already is so your design either matches it or has a clear reason not to.
4. Write the `## Design` section (visual spec). Cover, at minimum:
   - **Visual direction:** one paragraph naming the mood (minimalist? vibrant? retro?), the references it pulls from, and the emotional read it should produce. Keep it specific.
   - **Layout:** ASCII sketch, markdown wireframe, or numbered section breakdown. Annotate every element's role.
   - **Copy:** every user-facing string the engineer should ship, verbatim. Engineering should not have to write copy.
   - **Color & typography:** named tokens (from `Theme.swift` for in-app, or hex codes for out-of-app). Specify which font, weight, size for each text element.
   - **Spacing & sizing:** approximate dimensions for non-text elements. For in-app, prefer existing pattern matches over absolute pixel values.
   - **Interaction notes:** hover/focus/active states, animations, scroll behavior, anything dynamic.
   - **Asset list:** every image, icon, or font file needed.
   - **Do-not-do guardrails:** explicit list of things the engineer should NOT do.

   For cards with no visual surface at all (e.g. a sort algorithm change), the visual spec collapses to a one-line "no visual change" note and the work shifts to step 5.

5. Write the `## User Risks & Edge Cases` section. This is where you advocate for the user. Brainstorm and document, at minimum:
   - **Happy path:** the 80% case, walked through end-to-end as the user experiences it. What does it feel like? What does it sound like (this is a music player)?
   - **Empty / first-run states:** no library, no metadata, no artwork, no previous selection, fresh install.
   - **Malformed or hostile input:** corrupt files, unicode in filenames, zero-byte tracks, files that change underneath the app, files that lose accessibility (sandbox bookmarks gone stale).
   - **Scale stress:** 10 tracks, 1000 tracks, 50,000 tracks. What breaks? Where does the UI lag? Where does memory blow up? Where does a 4Hz observer become a problem?
   - **Concurrency / interruption:** rapid double-clicks, clicking during loading, sort + search at the same time, changing folders mid-playback, system sleep during gapless transition.
   - **"Wrong" user actions:** the user who tries the most off-label thing first. The user who keyboard-mashes. The user who drags 200 files at once. The user who has the search field focused and then hits a media key.
   - **Accessibility & input modes:** keyboard-only navigation, VoiceOver, larger Dynamic Type, reduced-motion, dark/light theme, second-monitor handoff, locale differences.
   - **Failure recovery:** what happens when something goes wrong? Is the error invisible? Does the user know what to do next? Is the app left in a usable state?
   - **Project-specific landmines:** AVURLAsset rules (§7.1), gapless lookahead (§7.2), two-phase loading (§7.3), sandbox bookmark balance (§7.4). Call out anything in the card's surface that touches these.

   For each risk, write one of:
   - **[MUST HANDLE]** — engineering must address in this card. Acceptance bullets should reflect it.
   - **[NICE TO HANDLE]** — engineering should try, but may defer with reasoning in `## Plan`.
   - **[FUTURE WORK]** — out of scope for this card; designer will file a child card if approved by manager.
   - **[WONT HAPPEN]** — explicitly out of scope, with one-line reasoning so future agents don't relitigate.

   If a [MUST HANDLE] risk is not already covered by an acceptance bullet, add the bullet (designers may edit `acceptance:` in frontmatter; log the change).

6. If the card IS the design artifact (landing page, static HTML/CSS, SVG icon), the designer also produces the artifact files in addition to the spec. The same agent is functioning as designer + engineer for one card and the engineer step is collapsed — note this in the log.
7. Self-audit your spec: re-read every acceptance bullet and confirm it's unambiguously answered by `## Design` (visual) or covered by `## User Risks & Edge Cases` (behavioral). If anything is underspecified, fix it before handing off.
8. Move the card back to `ready/`, log entry, commit `pm: <id> design ready`. Notify the manager.

If during engineering the spec turns out to be visually broken or impossible to implement faithfully: engineer kicks the card back to `design/` (not `blocked/`). Manager respawns the designer with the engineer's findings.

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

## 6c. **MANDATORY for designers: post-QA edge-case review**

After QA approves a card flagged `needs_designer: true`, the manager re-dispatches a designer agent (any designer; not necessarily the original) for a short post-QA review BEFORE the card moves to `done/`. This is the second swing at user advocacy. The first pass predicted edge cases up front; this pass checks whether the implementation actually handled them and whether reality surfaced anything the designer missed the first time.

The card stays in `qa/` during this pass. The designer does NOT re-run the §6b checklist — that's QA's job. The designer's only question is: **"Looking at this implementation as a real user about to encounter it, what edge cases or behaviors does it not account for, and are those worth advocating for now or filing as future work?"**

Designer post-QA workflow:

1. Set `design_review:` in frontmatter, log entry, commit `pm: <id> design-review start`.
2. Read in order: the original `## User Risks & Edge Cases` (your first-pass predictions), `## Plan` (how engineering chose to handle them), `## Self-Audit` (what engineering claims it did), `## QA Report` (what QA verified). Then read the `git diff` for touched files — not for code-quality review, but to understand what the user will actually experience.
3. Re-walk every `[MUST HANDLE]` and `[NICE TO HANDLE]` item from the original `## User Risks & Edge Cases`. For each: PASS / FAIL / DEFERRED with one-line evidence.
4. Then do fresh brainstorming. Now that the implementation exists, what NEW edge cases come to mind that you didn't think of in step 5 of §4b? Walk the same categories (empty, malformed, scale, concurrency, wrong actions, accessibility, recovery). The point is that seeing real code often surfaces risks that abstract design cannot.
5. Write the `## Design Review` section into the card with this structure:
   ```
   ### Original risks revisited
   - [PASS/FAIL/DEFERRED] <risk from §4b> — <evidence>
   ### Newly surfaced concerns
   - [BLOCKER/MAJOR/MINOR/FUTURE] <description> — <reasoning>
   ### Recommendation
   - [APPROVE / KICK BACK / APPROVE WITH CHILD CARDS]
   ```
6. Classification rules for newly surfaced concerns:
   - **BLOCKER** — the user will hit this on day one and the app will be visibly broken. Kick back to `in-progress/`.
   - **MAJOR** — the user will hit this within their first session and be confused or annoyed, but the app keeps working. Designer's call: kick back, OR file a child card and approve.
   - **MINOR** — real but rare; file a child card in `ready/` with `parent: <id>` and approve.
   - **FUTURE** — file in `backlog/` with `parent: <id>` and approve.
7. Commit the updated card. If kicking back, `git mv` to `in-progress/` and assign back to the original engineer. If approving, leave the card in `qa/` for the manager to close. Notify the manager with a one-paragraph summary.

Designer's job here is NOT to relitigate engineering choices that work for the user. It is to be the user's voice one more time before the card ships. If everything passes, the designer says so plainly and approves quickly. The post-QA pass should usually be short — minutes, not hours — unless something is genuinely wrong.

Cards without `needs_designer: true` skip §6c entirely. QA approval moves them straight to `done/`.

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

### Designer loop (pre-engineering, §4b)
```
1. git pull --rebase
2. Read .pm/README.md and the assigned card in .pm/ready/
3. mv card to .pm/design/, set designer:, log, commit
4. Read Theme.swift, the user request, any referenced assets
5. Study how comparable apps (iTunes, Apple Music, Spotify, Foobar2000, VLC, Finder) handle this surface
6. Write ## Design (visual spec) — collapses to "no visual change" for non-visual cards
7. Write ## User Risks & Edge Cases — happy path, empty/malformed/scale/concurrency/wrong-actions/a11y/recovery, each tagged [MUST HANDLE]/[NICE TO HANDLE]/[FUTURE WORK]/[WONT HAPPEN]
8. Add any [MUST HANDLE] items to acceptance: in frontmatter
9. If the card IS the design artifact, also produce the artifact files
10. Self-audit: every acceptance bullet unambiguously answered by ## Design or ## User Risks
11. mv to .pm/ready/, log, commit, notify manager
12. STOP.
```

### Designer post-QA loop (§6c)
```
1. git pull --rebase
2. Read .pm/README.md, then the card in .pm/qa/
3. Set design_review: in frontmatter, log, commit
4. Read in order: ## User Risks & Edge Cases → ## Plan → ## Self-Audit → ## QA Report → git diff
5. Re-walk every [MUST HANDLE] / [NICE TO HANDLE] item from the original spec → PASS/FAIL/DEFERRED
6. Fresh brainstorm: what NEW edge cases come to mind now that real code exists?
7. Write ## Design Review (Original risks revisited / Newly surfaced concerns / Recommendation)
8. BLOCKER → mv to in-progress/. MAJOR → designer's call (kickback or child card). MINOR → child card in ready/. FUTURE → child card in backlog/.
9. Commit, notify manager with one-paragraph summary
10. STOP.
```

### Engineer loop
```
1. git pull --rebase
2. Read .pm/README.md and the assigned card in .pm/ready/
3. If card has ## Design, read it as binding spec — do NOT relitigate visual choices
4. If card has ## User Risks & Edge Cases, every [MUST HANDLE] item must be addressed in your ## Plan (handle, defer with reasoning, or file a child card)
5. mv card to .pm/in-progress/, set engineer:, log, commit
6. EnterPlanMode → write ## Plan → commit → ExitPlanMode
7. Implement
8. Self-audit (§6) → write ## Self-Audit
9. mv to .pm/qa/, log, commit, notify manager
10. STOP. Wait. Do not pick up another card.
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
2. Write card in .pm/ready/. Set needs_designer: true unless the card is a pure refactor with zero user-visible delta.
3. If needs_designer: spawn designer agent (§4b). When designer hands back to ready/, proceed.
4. Spawn engineer agent pointed at the card id
5. When engineer hands off to qa/, spawn QA agent pointed at the card id
6. Read QA report:
   - KICK BACK → respawn original engineer with QA findings
   - CHILD CARDS → triage them; dispatch new engineers as needed
   - APPROVE → if needs_designer, go to step 7. Otherwise mv to done/ now.
7. (If needs_designer.) Spawn designer agent for the post-QA review (§6c). Read ## Design Review:
   - APPROVE → mv to done/, write ## Manager Decision, commit, notify human
   - KICK BACK → respawn original engineer with the design review's findings
   - CHILD CARDS → triage and dispatch
8. When all related cards (including QA- and design-review-spawned children) are in done/, the feature is closed.
```
