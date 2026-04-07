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

### Visual direction

Confident, vibrant, and quiet at the same time. The mood is "indie record-store website circa 2026" — a deep, near-black violet stage that lets the gold phonograph sit dead center under spotlight, with the candy gradient leaking in from the corners as colored stage lighting rather than as foreground. References: Bandcamp's product pages (restraint, type-led), the Linear marketing site (confident wordmark, single CTA), classic vinyl reissue sleeves (gold-on-purple). Emotional read: "this was made by someone who cares; it is going to sound good; the download button is right there." The page should feel like it was made by the same person who built the app's Candy theme — not a literal port of the app UI, but a clear sibling.

### Layout (wireframe)

```
+--------------------------------------------------------+
|                                                        |
|                  [ HERO — full viewport ]              |
|                                                        |
|              ( phonograph.png, 240px square )          |
|                                                        |
|                       JamBox                           |  ← gradient wordmark
|                                                        |
|       A minimalist macOS music player.                 |  ← tagline
|              Gapless by design.                        |
|                                                        |
|         [  Download for macOS  ]                       |  ← pill button, gradient fill
|         [  Free · macOS 14+    ]                       |     subtitle inside the button
|                                                        |
+--------------------------------------------------------+
|                                                        |
|         Built for people who care about music.         |  ← section title
|                                                        |
|   +----------+  +----------+  +----------+             |
|   | Gapless  |  | Local    |  | Wide     |             |  ← 6 feature cards
|   | playback |  | files    |  | format   |             |     auto-fit grid
|   +----------+  +----------+  +----------+             |     (1 / 2 / 3 cols)
|   +----------+  +----------+  +----------+             |
|   | Album    |  | Three    |  | Instant  |             |
|   | art      |  | themes   |  | search   |             |
|   +----------+  +----------+  +----------+             |
|                                                        |
+--------------------------------------------------------+
| github.com/emiller6505/JamBox  ·  macOS 14+            |  ← footer, low contrast
+--------------------------------------------------------+
```

Three sections only: hero, features, footer. No nav. No sticky anything.

### Copy (verbatim, ship as-is)

- **`<title>`:** `JamBox — A music player for macOS`
- **`<meta description>`:** `JamBox is a minimalist macOS music player built around gapless playback. Point it at a folder of music and let it roll.`
- **Wordmark:** `JamBox`
- **Tagline:** `A minimalist macOS music player. Gapless by design.`
- **Download button label:** `Download for macOS`
- **Download button sub-label:** `Free · macOS 14+`
- **Section title:** `Built for people who care about music.`
- **Feature card 1 title:** `Gapless playback`
- **Feature card 1 body:** `The whole point. Tracks flow into each other with no audible seam.`
- **Feature card 2 title:** `Local files only`
- **Feature card 2 body:** `No accounts, no streaming, no library import. Pick a folder, get a track list.`
- **Feature card 3 title:** `Wide format support`
- **Feature card 3 body:** `MP3, M4A, FLAC, AIFF, WAV, ALAC, AAC. FLAC durations done right.`
- **Feature card 4 title:** `Album art that just works`
- **Feature card 4 body:** `Pulled from embedded metadata or a cover image sitting next to your tracks.`
- **Feature card 5 title:** `Three themes`
- **Feature card 5 body:** `Light, Dark, and Candy. Pick your mood; it sticks across launches.`
- **Feature card 6 title:** `Instant search`
- **Feature card 6 body:** `Filter by title, artist, or album as you type. No indexing wait.`
- **Footer:** `github.com/emiller6505/JamBox  ·  macOS 14+`

### Color & typography

**Palette (hex):**

| Token | Hex | Use |
|---|---|---|
| Hot pink | `#FF1F8F` | gradient stop 1 (pulled from Theme.swift `.candy`) |
| Deep purple | `#8C198C` | gradient stop 2 (pulled from Theme.swift `.candy`) |
| Cyan | `#3FB5FF` | gradient stop 3 (pulled from Theme.swift `.candy`) |
| Lemon | `#FFE34D` | accent (pulled from Theme.swift `.candy.accent`) — feature titles, focus ring |
| Stage violet | `#0b0418` | page background |
| Mid violet | `#1a0526` → `#2a0a3a` | hero gradient base |
| Text primary | `#f5f3ff` | body text |
| Text secondary | `rgba(245,243,255,0.75)` | feature body, tagline |
| Text muted | `rgba(245,243,255,0.45)` | footer |

The gold phonograph is left untouched. The dark violet hero stage lets the gold pop. The candy gradient appears in three places only: (1) the wordmark text fill, (2) the download button fill, (3) two soft radial-gradient washes in the hero corners — pink top-left, cyan bottom-right.

**Type stack (every text element):**
`-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif`

| Element | Size | Weight | Letter-spacing |
|---|---|---|---|
| Wordmark `h1` | `clamp(64px, 12vw, 144px)` | 800 | `-0.04em` |
| Tagline | `clamp(17px, 2.2vw, 22px)` | 400 | normal |
| Download label | 18px | 700 | `0.01em` |
| Download sub-label | 12px UPPERCASE | 500 | `0.04em` |
| Section title `h2` | `clamp(24px, 4vw, 36px)` | 700 | `-0.02em` |
| Feature `h3` | 17px | 700 | `-0.01em` |
| Feature body | 15px | 400 | normal |
| Footer | 13px | 400 | normal |

### Spacing & sizing

- Logo: 240×240 desktop, 180×180 mobile, capped at `60vw` so it never overflows narrow viewports
- Hero: `min-height: 100vh`, padding `64px 24px 96px` desktop, `48px 20px 72px` mobile
- Hero content max-width: 720px, centered
- Tagline max-width: 480px (forces a tight, two-line read)
- Download button: padding `18px 44px`, border-radius `999px` (pill), large drop-shadow halo
- Features section: padding `96px 24px` desktop, `64px 20px` mobile
- Features inner max-width: 960px
- Feature grid: `repeat(auto-fit, minmax(260px, 1fr))` with 20px gap → 3 cols ≥960px, 2 cols ≥600px, 1 col below
- Feature card: padding `24px 24px 26px`, border-radius 16px, 1px translucent border
- Footer: padding `32px 24px 40px`, single line of low-contrast text
- Single mobile breakpoint at `max-width: 600px`

### Interaction notes

- Download button hover: `translateY(-2px)`, `filter: brightness(1.06)`, deeper shadow. Transition `160ms ease` on transform/box-shadow/filter.
- Download button active: returns to `translateY(0)`, `brightness(0.96)` — gives a "press" feel.
- Download button focus-visible: `3px solid #FFE34D` outline, `4px` offset (keyboard accessibility, lemon ring matches the candy accent).
- Feature card hover: subtle background lift `rgba(255,255,255,0.04) → 0.06`, border picks up a faint lemon tint.
- Footer link hover: text and underline both go lemon `#FFE34D`.
- `prefers-reduced-motion: reduce` disables all transitions and the button hover translate.
- No JavaScript. No scroll-triggered animations. No autoplay anything.

### Asset list

| Path | Source | Notes |
|---|---|---|
| `gh-pages-staging/index.html` | designer-authored | single page, semantic HTML5 |
| `gh-pages-staging/style.css` | designer-authored | < 10KB, no external imports |
| `gh-pages-staging/phonograph.png` | `cp` from `docs/phonograph.png` | 76,902 bytes, used as both hero logo and favicon |

### Do-not-do guardrails

- Do **not** recolor the phonograph. It is gold-on-circle and that is the point.
- Do **not** add a screenshot of the app. We don't have polished marketing screenshots. Out of scope.
- Do **not** add any external font (`fonts.googleapis.com`, Typekit, Bunny, etc.). System stack only.
- Do **not** add JavaScript. Not for analytics, not for "smooth scroll", not for a theme toggle.
- Do **not** add a navigation bar, sticky header, or anchor links. There is one page; nothing to navigate to.
- Do **not** add a mailing-list signup, popup, cookie banner, "as seen in" logo strip, testimonial, or carousel.
- Do **not** add Open Graph / Twitter Card meta tags in v1 — explicitly out of scope per the card.
- Do **not** add a custom favicon different from the phonograph — reuse the same file.
- Do **not** apply the candy gradient as a flat full-page background. The dark violet stage with gradient *accents* is the point; flooding the whole page kills the gold.
- Do **not** add scroll-triggered effects, parallax, marquee, animated background, or particle systems.
- Do **not** introduce a CSS framework (Tailwind, Bootstrap, etc.). Hand-rolled CSS only.
- Do **not** add a build step. The files in `gh-pages-staging/` ship as-is.
- Do **not** use `AVURLAsset` — irrelevant here, but listed to short-circuit any auto-checklist.
- Do **not** touch git branches. The manager handles `gh-pages` orphan setup and push.

### Self-audit

Walking each acceptance bullet against the shipped artifact:

1. **Single static HTML page with hero featuring phonograph prominently** — PASS. `index.html` has `<section class="hero">` with the phonograph at 240×240 (60vw cap on mobile) above the wordmark.
2. **Visually flashy but not gaudy; candy palette as reference** — PASS. Gradient appears only in wordmark text fill, download button, and two corner radial washes against a deep violet stage; the rest is restraint.
3. **Responsive at 375px → 1920px, no horizontal scroll** — PASS. `box-sizing: border-box` everywhere, `clamp()` typography, single `max-width: 600px` breakpoint that re-pads hero/features and shrinks the logo. Feature grid uses `auto-fit minmax(260px, 1fr)` so it collapses to 1 column on narrow viewports. No fixed widths anywhere.
4. **No JavaScript, no build step, no external font CDNs** — PASS. Zero `<script>` tags. Only external links are the two intentional `https://github.com/...` anchors. System font stack only.
5. **Hero has logo + name + tagline + Download button → releases/latest** — PASS. All four present, button href is exactly `https://github.com/emiller6505/JamBox/releases/latest`.
6. **Feature section with 4–6 distinguishing features, copy from README tightened** — PASS. Six cards: gapless, local files, formats, album art, themes, search.
7. **Footer with repo link and macOS 14+ note** — PASS. `<footer>` contains anchor to `https://github.com/emiller6505/JamBox` and the literal `macOS 14+`.
8. **All copy final and shippable** — PASS. Every string is in the Copy section above and in the HTML verbatim.
9. **Total page < 500KB; CSS < 10KB; phonograph ~50–100KB** — PASS. `wc -c` reports 84,852 bytes total (HTML 2,408; CSS 5,542; PNG 76,902). CSS comfortably under 10KB.
10. **No tracking, no analytics, no third-party JS, no fonts.google.com** — PASS. Grep for `http|cdn|googleapis|fonts.google` returns only the two intentional GitHub anchor links. Zero remote asset requests.
11. **Files in `gh-pages-staging/`, manager handles orphan branch** — PASS. All three files staged at `gh-pages-staging/`. Designer ran no git commands.
12. **Phonograph copied (not symlinked) from `docs/phonograph.png`** — PASS. `cp` (not `ln -s`) used; identical 76,902 bytes verified by `wc -c`.
13. **Valid HTML5, no console warnings** — PASS by inspection. `<!DOCTYPE html>`, single `<html lang="en">`, `<meta charset>` and viewport, all tags closed, all images have `alt` and explicit `width`/`height` (no CLS), `link rel="icon"`, `link rel="stylesheet"`. No deprecated tags. No inline event handlers.
14. **Feels like the same designer made app + site** — PASS. Lemon `#FFE34D` accent and the three candy gradient stops are lifted directly from `Theme.swift`'s `.candy` case (verified hex codes match `Color(red: 1.00, green: 0.12, blue: 0.56)` etc.).

Additional self-audit items:
- **Total weight under 500KB:** confirmed 84,852 bytes via `wc -c gh-pages-staging/*`.
- **HTML5 validity:** doctype present; one `<html>`, one `<head>`, one `<body>`; semantic `<main>`, `<section>`, `<footer>`, `<h1>`/`<h2>`/`<h3>` hierarchy without skips; all attributes quoted; all elements closed.
- **No external network requests:** grep confirms only the two intentional GitHub links.
- **Responsive 375px / 1920px:** at 375px the mobile breakpoint shrinks hero padding, logo to 180px, button to 36px padding, feature grid to single column. At 1920px, hero content centers within the 720px max-width, features within 960px max-width — ample whitespace flanks both, no stretching, no horizontal scroll.

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

## Log
- 2026-04-07 — manager created card; flagged needs_design: true; promoted to ready/
- 2026-04-07 — designer-01 picked up card (designer + engineer in one pass per §4b, card IS the design artifact); wrote ## Design with full spec, copy, palette, guardrails; produced gh-pages-staging/{index.html, style.css, phonograph.png}; total weight 84,852 bytes; no git operations performed (manager handles orphan branch). Requested lane moves: ready/0010 → design/0010 → qa/0010.

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
