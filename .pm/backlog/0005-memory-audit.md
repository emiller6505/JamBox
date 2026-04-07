---
id: 0005
title: Audit and reduce idle memory usage (currently ~1GB during playback)
created: 2026-04-06
engineer: null
qa: null
parent: null
priority: P1
estimate: L
depends_on: []
touches:
  - JamBox/PlayerEngine.swift
  - JamBox/FileScanner.swift
  - JamBox/Track.swift
  - JamBox/ContentView.swift
  - JamBox/NowPlayingBar.swift
  - JamBox/AppModel.swift
acceptance:
  - Current memory usage baseline is documented with a breakdown by category (resident memory, heap, image data, audio buffers, etc.) — the engineer must run instrumentation or have the human run Instruments and report numbers, not just guess
  - The top 3 memory contributors are identified by name, with file:line evidence pointing at the allocations responsible
  - Each top contributor has a documented reason for its current size (intended cache, leaked retain, oversized decoded image, etc.) — no "shrug, it's big"
  - For each top contributor, the engineer either fixes it OR documents why it cannot be reduced without breaking a feature, with a one-sentence justification
  - Idle-playback memory usage is reduced **substantially** from the 1GB baseline. The exact target is to be set by the engineer in the Plan section based on what they find — but a reasonable rough target for a minimalist music player is somewhere in the 150–400 MB range depending on library size and decoded buffer needs. The engineer must commit to a target in the Plan and either hit it or document why the realistic floor is higher
  - Gapless playback is unchanged — verify the AVQueuePlayer 3-item lookahead is still in place and working. Reducing the lookahead is NOT permitted as a memory optimization in this card; gapless is sacred
  - The artwork resolution chain and per-folder cache continue to function — the now-playing bar artwork still appears, the cache still avoids re-resolving on every track change. If the cache is part of the problem, the fix is bounding/evicting it, not eliminating it
  - The two-phase loading invariant is preserved — fast filesystem scan first, async metadata enrichment after. Memory optimization must not move metadata loading onto the UI thread
  - All AVURLAsset construction continues to use AVURLAssetPreferPreciseDurationAndTimingKey: true
  - Sandbox bookmarks remain balanced
  - Build passes cleanly with no new warnings: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - The fix is verified with **measurement**, not vibes. Either the engineer instruments before/after numbers themselves, or they hand the build to the human with a clear test protocol and the human reports numbers back. "Looks better" is not acceptable evidence
---

## Context

Reported by the human owner via Xcode's process stats:

> "according to xcode stats, the app is using about a gigabyte of memory just while idly playing music."

For reference, mainstream macOS music players typically idle in the 200–500 MB range with comparable libraries, and they generally do more than JamBox does. 1 GB for a minimalist player is a 2–5x overshoot and is the kind of footprint that will cause macOS to memory-pressure-warn other apps on machines with 8 or 16 GB of RAM. This is a P1 — not because anything crashes, but because it makes JamBox a bad citizen on the user's machine.

### Manager assumptions at the time of card creation (engineer should confirm or revise)

- **Overlay state during measurement:** assumed CLOSED. If the user took the measurement with the full-screen album art overlay (`showArtwork == true`) open, then a substantial chunk could be a single decoded full-resolution `NSImage` of the current album art. A 3000×3000 cover decoded to an `NSBitmapImageRep` is ~36 MB; held in two or three places it adds up fast. If overlay was open during measurement, the engineer should ask the user to remeasure with it closed and report the delta as a separate data point.
- **Memory shape:** assumed STEADY-STATE, not growing. If the 1 GB is reached and held, the fix is architectural (oversized cache, oversized decoded image). If memory grows over time (linear or stairsteppy), there is a leak — find it with the Memory Graph debugger or `MallocStackLogging`. Engineer should confirm the shape early in plan mode and let the answer guide their investigation.
- **Library size:** assumed "normal personal library, low thousands of tracks." If the user has 50,000+ tracks, the per-track metadata floor changes the math. Engineer should ask the user for an exact count if it materially affects the target.

### Hypotheses to investigate (engineer should also generate their own)

1. **Decoded artwork cache holding full-resolution `NSImage`s.** `PlayerEngine` maintains a per-folder artwork cache (CLAUDE.md). If it stores the decoded `NSImage` rather than the original encoded `Data`, and if it never evicts entries, then for a library with N albums the cache holds N × (decoded-image-size) bytes. For 100 albums with 3000×3000 artwork that's ~3.6 GB upper bound — easily explains 1 GB if even a fraction of the library has been touched. Likely the highest-yield investigation target.
2. **Track artwork field holding `Data` (or `NSImage`) per track.** If `Track` holds the decoded or encoded artwork bytes per-track rather than referencing a shared per-album cache entry, then a library with 5000 tracks holds 5000 copies of artwork. Even with shared encoded `Data` (much smaller than decoded `NSImage`), this can be hundreds of MB.
3. **AVQueuePlayer decoded audio buffers.** AVFoundation pre-decodes upcoming audio for gapless playback. With a 3-item lookahead and high-bitrate FLAC, this can run 50–150 MB. Probably NOT the primary contributor (would not reach 1 GB), but worth measuring as a baseline number that the engineer should NOT try to reduce (gapless invariant).
4. **Metadata fields with surprising sizes.** Some FLAC files embed lyrics, full liner notes, or even multiple high-res artwork images in metadata. If `Track.loadMetadata` retains all of these per-track (rather than picking the smallest / first / preferred artwork and discarding the rest), the per-track footprint can balloon.
5. **Retain cycles in observation graph.** If anything in the SwiftUI view tree or the AppKit bridges (`TableDoubleClick`, `TableScroller`, `WindowAccessor`) holds a strong reference back to a long-lived object that holds a reference forward to the view, every navigation/rebuild leaks that subgraph. Memory Graph debugger reveals these immediately.
6. **`FolderWatcher` FSEvents holding paths or callbacks longer than necessary.** Less likely to reach 1 GB on its own but worth a glance.
7. **Theme/window-chrome work that recently landed (TableScroller, WindowAccessor, theme switcher).** New code = new suspect surface. Glance at it for retain cycles or oversized backing layers.

### Investigation tooling

The engineer cannot run Xcode's Allocations / Leaks / Memory Graph tools from a sub-agent context. The realistic investigation flow is:

1. **Static analysis first.** Read all the suspect files, identify what holds bytes and for how long, eliminate hypotheses that don't match the architecture. Likely surfaces 1–2 strong candidates.
2. **Targeted instrumentation.** Add small `print` statements that report cache sizes, image dimensions, etc. at relevant lifecycle points: cache insert/evict, metadata load, current artwork swap. Build, hand to human, ask them to repro and paste the console output.
3. **Or ask the human to run Instruments.** Give them precise instructions: "Open Xcode > Profile > Allocations, run JamBox, play for 30 seconds, sort by size, screenshot the top 10 allocations." This gives ground truth without the engineer needing to run anything itself.
4. **Iterate.** This card may bounce through `qa/` → `in-progress/` → `qa/` several times as hypotheses get tested and refined. Be explicit in handoffs about which iteration you are on and what you've ruled out.

### What the engineer should NOT do

- **Do not reduce the AVQueuePlayer lookahead** as a memory optimization. Gapless playback is a top-priority feature and the 3-item lookahead is sacred. Document AVQueuePlayer's footprint as a baseline that is NOT to be touched.
- **Do not eliminate the artwork cache** to "fix" memory. The fix is bounding it (LRU eviction, max-N-entries, downscale-on-decode) — not deleting it. Re-resolving artwork on every track change would be a UX regression.
- **Do not move metadata loading onto the UI thread** or change the two-phase loading pattern.
- **Do not hand-wave with "looks lower in Xcode now."** Numbers, with before/after, or it didn't happen.
- **Do not scope-creep into general performance optimizations.** Memory only. CPU, startup time, scrolling smoothness — all out of scope, file new cards if you find them.

### Collisions and dependencies

This card has potential file overlap with card 0004 (inline album art, in `backlog/`), which heavily touches `ContentView.swift` and may also touch `PlayerEngine`'s artwork cache. Sequencing recommendation:

- **Do this card BEFORE 0004 if the issue turns out to be in the artwork cache.** It would be silly to land 0004 (which adds *more* artwork rendering to the table) on top of a broken cache; the right order is fix the cache, then add more art.
- **If the issue is unrelated to artwork**, the cards are independent and can be sequenced either way.

The engineer should confirm in plan mode whether their investigation focus collides with what 0004 would touch, and report back so the manager can sequence accordingly.

### Manager dispatch note (not for the engineer)

This card is in `backlog/` because the manager should ask the human Q1–Q3 (overlay state, memory shape, library size) before dispatching, to set the engineer's starting orientation correctly. After answers, promote to `ready/` and dispatch. Decide whether to do this card or 0004 first based on the user's priorities.

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

**Memory target committed:**

## Log
- 2026-04-06 — manager created card in backlog/, awaiting Q1–Q3 answers from human before promoting

## Self-Audit
*Filled in by the engineer before handing off to QA. See .pm/README.md §6.*

1. Re-read modified files:
2. Acceptance walkthrough:
3. Build result:
4. Invariants verified:
5. Hostile diff review:
6. Touched-files reconciliation:
7. Scope check:

## Findings
*Filled in by the engineer during the audit. Top contributors, why they're big, what's fixed, what's documented as unfixable.*

## QA Report
*Filled in by the QA agent. See .pm/README.md §6b.*

### Acceptance

### Invariants

### Findings

### Recommendation

## Manager Decision
*Filled in by the manager when closing or kicking back.*
