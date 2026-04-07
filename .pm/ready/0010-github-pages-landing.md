---
id: 0010
title: Build a flashy GitHub Pages landing page for JamBox
created: 2026-04-07
needs_design: true
designer: null
engineer: null
qa: null
parent: null
priority: P2
estimate: M
depends_on: []
touches:
  - gh-pages-staging/index.html
  - gh-pages-staging/style.css
  - gh-pages-staging/phonograph.png
acceptance:
  - A single static HTML page (index.html) with a hero section featuring the phonograph logo prominently
  - Visually flashy but not gaudy — the candy theme palette (hot pink #FF1F8F → deep purple #8C198C → cyan #3FB5FF) is the right reference, but the page should feel modern and confident, not chaotic
  - Page is responsive — readable on a 375px-wide phone and a 1920px desktop with no horizontal scroll, no broken layout
  - Page works with NO JavaScript. Pure HTML + CSS. No build step, no frameworks, no external font CDNs that might be blocked. System fonts only
  - Hero contains: phonograph logo (rendered from `phonograph.png` copied alongside the page), the name "JamBox", a one-line tagline, and a primary "Download" button linking to the latest GitHub release page (`https://github.com/emiller6505/JamBox/releases/latest`)
  - Below the hero, a short feature section listing 4-6 of JamBox's distinguishing features (gapless playback, local files only, wide format support, album art, theme support, search) — copy lifted from the existing README.md and tightened by the designer
  - Footer with a link to the GitHub repo (`https://github.com/emiller6505/JamBox`) and a small "macOS 14+" note
  - All copy is final and shippable — the designer writes it, the engineer does not improvise
  - File size budget: total page (HTML + CSS + image) under 500KB. The phonograph.png is ~50-100KB; CSS should stay under 10KB
  - No tracking, no analytics, no third-party JavaScript, no fonts.google.com requests, no fingerprinting. The page is entirely self-contained on github.io
  - Files are staged in `gh-pages-staging/` at repo root. The manager will move them onto an orphan `gh-pages` branch and push — the designer/engineer does NOT touch git branches
  - The phonograph image is the same `docs/phonograph.png` already in main, copied (not symlinked) into the staging folder so it lives alongside the HTML when the orphan branch is pushed
  - HTML validates as HTML5, CSS has no syntax errors. The page renders without console warnings in modern Chrome and Safari
  - The candy theme aesthetic is the spiritual reference; the page should feel like the same designer made the app and the website. But the page is NOT required to mimic the app's exact UI — it's a marketing page, not a screenshot of the app
---

## Context

User-facing request:

> "let's make a github pages for this. create a gh pages branch, make a flashy landing page for the project that features the phonograph logo. keep it simple. employ a designer agent for this."

JamBox is a minimalist macOS music player. The GitHub repo currently has a README with a phonograph icon at the top. There is no marketing site. The goal is a single-page landing site at `emiller6505.github.io/JamBox` (the default URL for a `gh-pages` branch) that:

1. Looks good enough that a curious visitor stops scrolling.
2. Communicates what JamBox is in under five seconds.
3. Has an obvious download path.

This is the first card of its kind for JamBox so we are establishing taste, not iterating on prior work. The designer should treat the candy theme palette and the phonograph icon as the brand's only fixed points and build outward from there.

### Why a designer agent leads this card

The user explicitly asked for one. More importantly, "flashy but simple" is a taste call, not a technical one — it deserves a designer's full attention to layout, hierarchy, copy, and color before any HTML gets written. The designer also writes the actual files for this card (per §4b: "If the card IS the design artifact, the designer also produces the artifact files"). One agent does both spec and implementation.

### Technical notes for the designer-as-implementer

- The orphan `gh-pages` branch is the manager's job to set up and push. Do NOT run `git checkout`, `git branch`, `git push`, or any branch-mutating command. Do NOT run `git commit`. Just write files into `gh-pages-staging/` at repo root.
- The phonograph image lives at `docs/phonograph.png` in main. Copy it (with the `cp` shell command via Bash) to `gh-pages-staging/phonograph.png`. The manager will pick up the staging folder as the source of truth for the orphan branch.
- The download button must link to `https://github.com/emiller6505/JamBox/releases/latest` so the link does not go stale on every release.
- macOS 14+ is the minimum supported version (per project.yml). Mention it in the footer or next to the download button.
- Themes available in JamBox: Light, Dark, Candy. Search: filters by title/artist/album. Gapless: top-priority feature. Local files only, no streaming, no accounts.
- Latest published version as of card creation: v1.1 (https://github.com/emiller6505/JamBox/releases/tag/v1.1)

### Out of scope for v1

- Multi-page site (about, features, blog, etc.)
- Screenshots of the app — we don't have polished marketing screenshots and capturing them is its own task
- Light/dark mode toggle for the page itself
- Animation libraries or scroll-triggered effects beyond basic CSS transitions
- A custom domain — `emiller6505.github.io/JamBox` is the URL
- Open Graph / Twitter Card meta tags — nice to have but skip if it complicates the spec; can be a follow-up card
- A favicon different from the phonograph (just reuse the phonograph as the favicon)

## Design
*Filled in by the designer BEFORE engineering starts. Required when `needs_design: true`. See .pm/README.md §4b.*

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

## Log
- 2026-04-07 — manager created card; flagged needs_design: true; promoted to ready/

## Self-Audit
*Filled in by the engineer (or designer-as-engineer) before handing off to QA. See .pm/README.md §6.*

## QA Report
*Filled in by the QA agent. See .pm/README.md §6b.*

### Acceptance

### Invariants

### Findings

### Recommendation

## Manager Decision
*Filled in by the manager when closing or kicking back.*
