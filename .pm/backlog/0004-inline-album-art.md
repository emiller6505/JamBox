---
id: 0004
title: Show album art in song table, visually spanning consecutive same-album rows
created: 2026-04-06
engineer: null
qa: null
parent: null
priority: P2
estimate: L
depends_on: [0002, 0003]
touches:
  - JamBox/ContentView.swift
  - JamBox/PlayerEngine.swift
  - JamBox/Track.swift
acceptance:
  - For each contiguous run of tracks in the song table that share the same album, the leftmost area of the table displays exactly ONE album art thumbnail that visually spans the vertical extent of that run (not just one image at the top of the run with empty space below — the image must appear to occupy the height of the whole album block)
  - Album grouping is determined by consecutive tracks sharing the same `album` metadata field (the same field used by the existing "Album" column). If `album` is empty for a track, it does not group with anything; treat it as a one-track group
  - The artwork resolution chain is identical to the now-playing bar's existing chain (embedded metadata → folder image with known names: cover/folder/album/front → any image in folder), and the existing per-folder artwork cache in `PlayerEngine` is reused — no duplicate resolution logic
  - When no artwork can be resolved for a group, a subtle SF Symbol placeholder (`music.note` or similar muted-style icon) is shown in its place, sized to the same area an art thumbnail would occupy
  - The currently-playing-track speaker indicator (`speaker.wave.2.fill`) continues to mark the playing row visually. It must coexist with the album art — either as an overlay on top of the art (when the playing row is the first row of its album group) or as an inline indicator on its row (when the playing row is not the first row of its group). Engineer chooses approach in plan mode and documents the choice. The user must NEVER lose the ability to see at a glance which row is playing
  - The now-playing bar artwork (bottom of window) is COMPLETELY UNCHANGED — no edits to that artwork code, no shared state mutation. Verify with a diff
  - Right-click context menu (card 0001) continues to work on every row, including rows whose leftmost cell visually contains album art
  - Double-click-to-play continues to work on every row, including the row that visually contains the album art
  - Single-click row selection continues to work on every row (including the row containing the art) — explicitly verify against the click bug from card 0002 to ensure the new view structure doesn't reintroduce or worsen it
  - Keyboard navigation of the table (arrow keys, return) is unaffected
  - If the user later sorts the table by a non-album column (not currently possible, but architecturally — clicking a different column header), the grouping will visibly degrade (one image per row). This is acceptable for v1 and is documented in the Plan as a known limitation. Do not attempt to handle it in this card
  - Tables with no tracks (empty library) render correctly with no album art column artifacts
  - Tables with a single track render that track's art (group of one) correctly
  - Build passes cleanly with no new warnings: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - AVURLAsset invariant unaffected (no audio code touched)
  - Gapless playback unaffected (no PlayerEngine queue logic touched — artwork cache reads only)
  - Two-phase loading invariant unaffected — album art resolution must NOT block the initial fast filesystem scan; if art isn't ready yet, show the placeholder until it loads
---

## Context

User-facing request from the human owner:

> "adding album arts to the table. currently things are grouped by album anyway due to folder structure. for consecutive items all from the same album, I want ONE album art to appear in the leftmost column next to the song names. this does not supercede or replace the existing album art logic in the 'now playing' bar at the bottom"

The user provided a screenshot of the current app state showing the song table grouped by album due to folder structure (e.g. all UADA / Cult of a Dying Sun tracks together, then all White Wizzard / Over the Top tracks together, etc.). The leftmost column today is a narrow ~20px column that shows a speaker icon for the currently playing track.

The user explicitly chose **visual spanning** (not "first-row-only with blank cells below") and **`music.note` SF Symbol** for the no-art fallback, when offered the trade-off in chat.

### Why this is hard in SwiftUI Table

`SwiftUI.Table` does not support cells that span multiple rows. Every row gets a fixed-height cell in every column. To achieve "one image visually spanning N rows," the engineer has three known approaches, each with trade-offs:

1. **Tall uniform rows + first-row-only paint.** Make every row tall enough (e.g. 60px) to fit a square album art thumbnail. Paint the art only in the first row of each group; subsequent rows of the group have an empty leftmost cell. The visual effect is "one image at the top, blank below" — which is NOT visual spanning, so this approach **does not satisfy the acceptance** unless paired with something else. Listed for completeness; the engineer should not pick this on its own.

2. **Overlay layer positioned by row geometry.** Render the table as today (or with slightly bumped row heights), then overlay a `ZStack` layer above the leftmost column area that contains one `Image` view per album group, positioned and sized using a `PreferenceKey` collected from each row's `GeometryReader`. The overlay reads the actual y-positions of each row from preferences and lays out album art images at the right vertical offsets, sized to span their group. This is the "real" visual spanning approach. It's a known SwiftUI pattern but takes care to get right — particularly around scroll synchronization (the overlay must scroll with the table content, not stay pinned) and dynamic resizing (window resizes, font scaling, sidebar toggle, etc.).

3. **Abandon `Table`, use `List` with grouped sections or a custom layout.** Each album group becomes a `Section` with a header that contains the album art and a body that contains the track rows. macOS sidebar style. Pros: trivial to implement spanning correctly. Cons: loses the `Table`'s columnar layout and column resize/reorder behavior, which the user has spent prior cards getting right. **Almost certainly not the right choice for this card** — the user values the column layout. Listed for completeness; reject in plan mode unless you have a strong reason.

The expected approach is **(2) overlay layer positioned by row geometry**. The engineer should confirm in plan mode and document the architectural choice in detail before writing code.

### Album grouping algorithm

Grouping is purely positional and based on the rendered order of `player.tracks`:

```
groups = []
current = nil
for track in player.tracks:
    if current is nil or track.album != current.album or track.album.isEmpty:
        current = new group starting at this track
        groups.append(current)
    else:
        current.tracks.append(track)
```

Tracks with empty `album` strings each form a group of one. The grouping is recomputed whenever `player.tracks` changes (e.g. folder rescan via `FolderWatcher`).

The grouping is **stable across the existing track ordering** (which is folder-order today). If a future card adds column sorting, the grouping will naturally degrade to "one image per row" when sorted by a non-album column. That degradation is acceptable for v1 and is documented in the acceptance — do NOT add sort-aware grouping in this card.

### Artwork resolution

`PlayerEngine` already implements the resolution chain for the now-playing bar artwork: embedded metadata → folder images named `cover.*` / `folder.*` / `album.*` / `front.*` → any image in the folder. It maintains a per-folder cache. **Reuse it.** If the cache API isn't currently exposed, expose it via a small accessor — but do not duplicate the resolution logic.

**IMPORTANT CONSTRAINT (added 2026-04-06 after card 0005 closed):** the per-folder artwork cache is now bounded to **8 entries with LRU eviction**, and every cached image is downscaled to ≤1024 px on its longest side before storage (see commit `183872f`, card 0005). This was the fix for a 500 MB memory sawtooth.

For card 0004, this means:
- If the user's library spans more than 8 distinct visible album groups in the table at one time, the LRU cap will thrash — every scroll across album boundaries will evict and re-decode artwork. Expect this and **plan for it during plan mode**. Either: (a) accept the thrash (the re-decode is fast and the cap exists for memory reasons that 0004 should not break), (b) propose raising the cap to a higher value with a justification (e.g. cap to N where N is roughly the number of albums likely to be visible at once — maybe 20-32 — but ONLY if you can show the memory cost is acceptable), or (c) introduce a separate, smaller "thumbnail-resolution" cache layer specifically for table-row art that holds many more entries at much lower per-entry cost (e.g. 64 px square), separate from the main full-resolution cache used by the now-playing bar.
- Option (c) is probably the right call for 0004: the table's leftmost-column thumbnails don't need 1024 px artwork, so a parallel thumbnail cache (say 128 entries × ~30 KB each = ~4 MB) is both more memory-efficient AND avoids thrashing the main cache.
- Whichever option the engineer picks, **the now-playing bar artwork must continue to work without regression** — the main full-resolution cache and its bound must not be compromised.

Artwork loading is async. The initial fast scan (`FileScanner.scanFolder`) shows track filenames immediately; metadata enrichment follows in the background. Album art comes via the metadata pass and the folder-image scan. **The Table must render immediately and show the placeholder for groups whose art has not yet loaded**, then update when art arrives — don't block any UI on art.

### Speaker indicator coexistence

The currently-playing speaker icon today lives in the leftmost narrow column. Once that column is occupied by album art, the speaker icon needs a new home. Two reasonable approaches (engineer chooses in plan mode):

- **Overlay on the album art** when the playing row is the first row of its group: paint a small `speaker.wave.2.fill` badge in a corner of the art image (e.g. bottom-right with a translucent dark scrim).
- **Inline on the playing row** when the playing row is *not* the first row of its group: paint the speaker icon in the row's normal cell area, perhaps to the left of the title, so the user can still see at a glance which track is playing.

The user must **never** lose the ability to see which row is playing. This is a hard requirement.

### Collisions and dependencies

This card has heavy file overlap with cards 0002 (clicking-state audit) and 0003 (stale-URL handling for the context menu). All three touch `JamBox/ContentView.swift`. Per the protocol, **this card cannot be in `in-progress/` simultaneously with either of those.** Sequencing:

1. Card 0002 must close first — fixing the click bug is a prerequisite for changing view structure around the table (we don't want to ship a new view structure on top of a known click bug).
2. Card 0003 should close before this card too if possible, to avoid having to merge stale-URL handling into the new view structure later. If 0003 is parked indefinitely, 0004 may proceed without it, but the engineer should rebase 0003 on 0004's view structure once 0004 lands.

### Manager dispatch note (not for the engineer)

This card is in `backlog/`, NOT `ready/`. Promote it to `ready/` only after card 0002 closes (and ideally after 0003 closes). When promoting, re-check this card's hypotheses against whatever 0002 actually shipped — the click-bug fix may change the view structure enough that some of the implementation orientation here is stale.

## Plan
*Filled in by the engineer during plan mode, BEFORE any code edits. See .pm/README.md §5.*

**Approach:**

**Files:**

**Risks:**

**Open questions:**

## Log
- 2026-04-06 — manager created card in backlog/, blocked on cards 0002 and 0003 (file collision on ContentView.swift)

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
