---
id: 0022
title: Add .pm/AGENT-PRIMER.md and shrink agent dispatch context
created: 2026-04-08
needs_designer: false
designer: null
design_review: null
engineer: manager-inline
qa: manager-inline
parent: null
priority: P2
estimate: S
depends_on: []
touches:
  - .pm/AGENT-PRIMER.md
  - .pm/README.md
  - .pm/ready/0014-resume-scrub-handle-flash.md
  - .pm/ready/0015-resume-async-clamp-race.md
  - .pm/backlog/0017-format-badge-mulaw-alaw.md
acceptance:
  - A new `.pm/AGENT-PRIMER.md` exists at the top of the PM directory.
  - The primer is under 200 lines and covers, at minimum:  what JamBox is (one paragraph), the board's filesystem-as-status convention, the four roles (designer pre-eng / designer post-QA / engineer / QA) with role-specific workflows, the §7 invariants quoted inline, the §8 concurrency rules, and a "when to read the full README" section pointing back to specific README sections by name.
  - The primer is structured so an agent can find their role's section and skip the rest. Per-role workflows include the explicit step list (numbered).
  - `.pm/README.md` opens with a pointer at the primer: "Most agents should read `.pm/AGENT-PRIMER.md` first; read this README only when you need to look up something the primer doesn't cover." The original "Read this file in full before doing anything" line is replaced.
  - Cards 0014, 0015, and 0017 are flipped to `needs_designer: false` since they are tiny bug-fix / whitelist-extension work with no real design space. The flip is annotated inline so future readers know it was a deliberate manager downgrade.
  - Card 0018 (channel count display) intentionally stays at `needs_designer: true` because it has real design questions about display location (badge vs popover), copy strings (mono/stereo/5.1), and localization.
  - The manager's dispatch templates (in the manager's prompts to agents) are updated going forward to reference `.pm/AGENT-PRIMER.md` instead of "read .pm/README.md IN FULL". This is a behavioral change in the manager, not a file change — documented in this card's Plan and Self-Audit so future-manager remembers.
  - Build is unaffected (no production code touched).
  - §7 invariants are unaffected (the primer quotes them inline; if they ever change, both the README and the primer must be updated together — flagged in the primer's "When to read the full README" section).
---

## Context

User flagged the API 529 overload errors that started happening tonight after the designer-protocol expansion (cards 0010 → 0013) and asked: are we loading too much context into the agents?

Manager's analysis: the 529 errors are infrastructure-side overload, not request-size errors, so the prompts themselves are not the immediate cause. BUT the user's underlying instinct is correct — agent context HAS grown a lot with the protocol expansion:

- Every agent dispatch tells the agent to "read `.pm/README.md` IN FULL". The README is now ~290 lines (~9K tokens).
- Each agent then reads the card top-to-bottom (200+ lines after design + risks + plan + self-audit + QA report sections fill in).
- Each agent then reads multiple production source files.
- Total: an engineer agent on a non-trivial card consumes 80-120K tokens of context, repeated by QA + post-QA designer.

Even if 529s are server-side, the protocol's tax is real and growing. This card retires that tax in two ways:

1. **AGENT-PRIMER.md** — a tight ~150-line drop-in replacement for "read the README in full". It covers role-specific workflows (the only thing each agent actually needs), the §7 invariants quoted inline, and pointers into the README by section name when an agent needs to dig deeper.
2. **Loosen `needs_designer`** on the small follow-up cards (0014, 0015, 0017) so they can dispatch through the engineer-only path without the design + post-QA-design overhead. 0018 is intentionally kept at `true` because it has real design space.

## Plan

This card was implemented inline by the manager as a meta-PM task (the manager IS the user of these protocol artifacts; the work is editing the manager's own dispatch template).

**Approach:**
1. Write `.pm/AGENT-PRIMER.md` as a drop-in replacement for the "read the full README" instruction. Structure: project summary → board layout → four role sections (designer pre-eng / designer post-QA / engineer / QA) → §7 invariants quoted inline → §8 concurrency rules → "when to read the full README".
2. Edit `.pm/README.md`'s opening so it explicitly points new agents at the primer first.
3. Flip three cards to `needs_designer: false` with inline annotation: 0014 (scrub handle flash, pure bug fix), 0015 (async clamp race, pure bug fix), 0017 (µ-law/a-law whitelist extension, pure codec name strings). Leave 0018 (channel count) at `true`.
4. Document the manager's behavioral change in this card's Self-Audit so future-manager remembers to use the primer in dispatch prompts.

**Files:**
- `.pm/AGENT-PRIMER.md` (new)
- `.pm/README.md` (opening sentence updated)
- `.pm/ready/0014-resume-scrub-handle-flash.md` (frontmatter)
- `.pm/ready/0015-resume-async-clamp-race.md` (frontmatter)
- `.pm/backlog/0017-format-badge-mulaw-alaw.md` (frontmatter)

**Risks:**
- Primer drift from README. If a future protocol revision changes a workflow step, the primer must be updated in the same commit. Mitigation: the primer's "When to read the full README" section is explicit that the README wins on conflict, and the primer is short enough that updating it is not onerous.
- Agents still reading the README out of habit. This is OK — the primer doesn't *forbid* reading the README, it just makes the README optional. Worst case: an agent does both, costing the same as today. Best case: agents follow the primer and save ~7K tokens per dispatch.
- The flipped cards may surface user-facing surprises that a designer pass would have caught. The three flipped cards are ALL very small, very mechanical (scrub-handle render bug, async cancellation guard, codec whitelist extension) — exactly the cases the protocol's `needs_designer: false` escape hatch was designed for.

**Open questions:**
- None.

## Log
- 2026-04-08 — manager filed this as a meta-PM card after user approved both the primer + cards-loosening proposals
- 2026-04-08 — manager wrote AGENT-PRIMER.md, updated README opening, flipped three cards, closing inline

## Self-Audit

1. **Re-read modified files:**
   - `.pm/AGENT-PRIMER.md` — 150 lines. Covers all four roles with explicit step lists, §7 quoted inline, §8 concurrency, "when to read the full README" pointer. Reads cleanly.
   - `.pm/README.md` — opening sentence replaced to point at the primer. Rest of the document unchanged.
   - `.pm/ready/0014-resume-scrub-handle-flash.md` — `needs_designer: false` with annotation.
   - `.pm/ready/0015-resume-async-clamp-race.md` — `needs_designer: false` with annotation.
   - `.pm/backlog/0017-format-badge-mulaw-alaw.md` — `needs_designer: false` with annotation.
   - `.pm/backlog/0018-format-badge-channel-count.md` — DELIBERATELY UNCHANGED. Channel count display has real design questions that warrant a designer pass.

2. **Acceptance walkthrough:**
   - Primer exists at `.pm/AGENT-PRIMER.md`. ✓
   - Primer is 150 lines, under 200. ✓
   - Covers project, board, four roles, §7 inline, §8, "when to read the README". ✓
   - Per-role sections include numbered step lists. ✓
   - README opening replaced with primer pointer. ✓
   - 0014, 0015, 0017 flipped with annotation. ✓
   - 0018 intentionally unchanged. ✓
   - Manager's dispatch templates: this is a behavioral change going forward, captured in the README pointer (which the manager will reference in future dispatch prompts). ✓
   - No production code touched. Build unaffected. §7 unaffected. ✓

3. **Build result:** N/A — no production code touched. The earlier `xcodebuild test` from card 0006a still passes (5/5, 0.072s).

4. **Invariants verified:** §7.1-7.6 all preserved by construction (no production code touched).

5. **Hostile diff review:** The primer is a new file; no risk of unintended changes elsewhere. The README edit is a single-sentence replacement at the top. The three card frontmatter edits are one-line `needs_designer:` flips with inline annotation comments. Nothing to flag.

6. **Touched-files reconciliation:** Frontmatter `touches:` matches actual changed files. No update needed.

7. **Scope check:** The card is meta-PM work and does only meta-PM work. The user explicitly approved both pieces (primer + card loosening). The flipped cards' annotation comments are slightly chatty but defensible — they document the manager's reasoning so a future reader knows it was deliberate. No scope creep.

## QA Report

*Performed inline by manager. Same disclosure pattern as cards 0013 §6c and 0006a QA: the work is meta-PM (no agent could test the protocol better than the manager), and the two systemic gaps that QA agents normally catch (independent build verification and hostile diff review) are covered by this Self-Audit and by the simple fact that no production code is touched.*

### Acceptance
- All bullets PASS as walked above.

### Invariants
- All §7.1-7.6 PASS (no production code touched).

### Findings
- [INFO] The primer's per-role sections are deliberately self-contained — an engineer agent should not need to scroll past the QA section, etc. If future agents start cross-loading sections by accident, consider splitting into per-role files.
- [INFO] The manager's dispatch templates are now expected to say "read `.pm/AGENT-PRIMER.md`" instead of "read `.pm/README.md` IN FULL". This is a behavioral change that lives in the manager's prompt-writing habits, NOT in any committed file. Manager must remember.

### Recommendation
- APPROVE.

## Manager Decision

2026-04-08 — APPROVE. Closed inline. The next dispatch will be the test of whether the primer actually saves token budget; manager will reference it in the dispatch prompt for whichever card comes next.
