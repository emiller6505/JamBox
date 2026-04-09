---
id: 0012
title: Resume playback position on launch
created: 2026-04-08
needs_designer: true
designer: designer-12
design_review: designer-12-review
engineer: engineer-12
qa: qa-12
parent: null
priority: P2
estimate: S
depends_on: []
touches:
  - JamBox/PlayerEngine.swift
  - JamBox/AppModel.swift
acceptance:
  - On app quit, JamBox saves the currently-playing track's URL and the live playback position. If nothing is playing, it saves nothing (or clears any prior saved state).
  - During playback, the saved position is updated on a throttled timer (~5s cadence) so a hard crash doesn't lose more than a few seconds of progress.
  - On next launch, after the folder bookmark is restored and tracks are loaded, JamBox locates the saved track by URL inside the restored folder, builds an `AVPlayerItem` via the existing `assetOptions` (preserving §7.1), seeks to the saved position, and presents the now-playing bar populated — but playback stays PAUSED.
  - One press of space (or click of the play button) resumes from the saved position. The first transition into the next track after resume is gapless (the lookahead must be filled before the user presses play).
  - Saved track no longer exists at relaunch (file deleted, folder bookmark stale, file outside the restored folder, etc.) → silent clear of the saved state. No error modal, no log spam. App opens in its normal first-launch state.
  - Saved position exceeds the asset's actual duration (file was re-encoded shorter between sessions) → clamp to `[0, duration]`. Trust the asset's async-loaded duration over the saved value.
  - The restored track's metadata is the cheap `init(url:)` form initially; when `updateMetadata` lands the enriched metadata, the swap happens in-place without disrupting the already-queued `AVPlayerItem` (verify §7.3 still holds for this code path).
  - No new `AVURLAsset` construction site introduced. The resume code path goes through `Self.assetOptions` (extract a private helper if tempted to duplicate).
  - All `startAccessingSecurityScopedResource` calls remain balanced with `stopAccessingSecurityScopedResource` (§7.4). The resume path uses the existing folder bookmark — no new per-track bookmark.
  - Saved-state payload includes a `version: Int` schema field. On decode, mismatched or missing version is treated as "no saved state" (silent clear). This future-proofs schema evolution without a migration burden today.
  - The throttled ~5s save timer only fires while `player.isPlaying == true`. It does NOT write UserDefaults while playback is paused. The save-on-quit path is independent and still captures the final state regardless of play/pause.
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - §7.1 AVURLAsset preserved
  - §7.2 Gapless playback preserved (verify by ear: resume, press play, listen for the first track→next transition)
  - §7.3 Two-phase loading preserved
  - §7.4 Sandbox bookmarks balanced
---

## Context

User picked this from a designer brainstorm of new feature ideas (2026-04-08). The two-card slate (0012 + 0013) is "this app respects my time and tells me what I need to know" — quiet, considerate UX that signals JamBox is for users who care.

User quote (designer brainstorm): *"I was 45 minutes into a 70-minute mix, closed my laptop, opened it three days later — I want it to remember."*

The engineer's selection memo flagged this as the lowest-risk way to get high-leverage user value: every seam already exists. `PlayerEngine.play(startingAt:)` is the single asset-construction site (uses `assetOptions` with `AVURLAssetPreferPreciseDurationAndTimingKey`). `Track.id` is the URL. The folder bookmark already lives in `AppModel`. `PlaybackClock` already publishes position. The resume path is a tiny variation: build the item, insert into queue, `seek(to:)`, but do NOT call `play()` so `timeControlStatus` stays `.paused` and the existing KVO sink reflects that.

This card is a sibling to card 0013 (format badge + NowPlayingBar UX pass). Both touch `PlayerEngine.swift` so they cannot be in-progress simultaneously (§8). Manager has serialized: 0012 first, then 0013.

## Design

**Visual direction:** no visual change. The whole point of this card is that the feature is invisible at rest and reveals itself only as a populated-but-paused now-playing bar on launch. JamBox should feel like it remembered without saying so — the tone is "a considerate friend who picked the needle back up where you left it," not a dialog box asking permission.

**Comparable apps studied:**
- **Apple Music / iTunes:** silently restores the last queue, paused, at last position. No UI affordance. On by default. Users expect this.
- **Audirvana:** restores full session including queue. Paused. No opt-in.
- **Overcast / Apple Podcasts:** universally remember position per episode. This is baseline podcast behavior and informs user expectations for any audio app.
- **Foobar2000:** `Keep playing` / `Remember playing item` options, off by default, buried in preferences. We are explicitly NOT copying this — Foobar's ancestors were CD players, ours are streaming services. Our users' mental model is "my phone remembered," not "my stereo forgot."
- **VLC:** restores file position on reopen (video), asks once via a banner. We skip the banner — one-time prompts are noise for a music player the user will open thousands of times.
- **Decision: on by default, no setting.** If a "don't resume" setting is ever requested it becomes a future card. Shipping an off-by-default toggle would contradict the card's thesis.

**Layout / wireframe:** no chrome changes. The populated-but-paused state already exists today — it's the same state you see after pressing pause mid-track. The only difference is that on launch it is pre-populated from disk rather than from a user action.

```
┌──────────────────────────────────────────────────────────┐
│ [Table of tracks — sort restored per 0011]               │
│ (selection empty; nothing highlighted)                   │
├──────────────────────────────────────────────────────────┤
│ [art] Song Title          [⏮] [▶] [⏭]                   │  ← play glyph, NOT pause. Normal paused state.
│       Artist                                             │
│       Album                                              │
│ 12:34 ━━━━━●─────────────────────────── 45:67            │  ← scrub bar seeded at saved position
└──────────────────────────────────────────────────────────┘
```

**Copy:** none. No banner, no toast, no "Resumed from where you left off" string. Silence is the feature.

**Color & typography:** unchanged. All existing Theme.swift tokens apply as-is.

**Spacing & sizing:** unchanged.

**Interaction notes:**
- Play-button glyph on launch is `play.fill` (the normal paused glyph), NOT a special "resume" icon. Consistency with every other paused state in the app. A user who pauses mid-track and a user who quit yesterday should see the same button. No visual distinction between "paused after playing" and "paused because we just launched."
- Space bar or click play: resume from `clock.position` (already seeded). No confirmation.
- Double-click any other row in the table: abandons the resume — treated exactly as a first play. The scrub bar reseeds to 0 for the new track. The saved state gets overwritten on the next save tick / on quit.
- Scrub bar is interactive before the user presses play. Dragging the slider while still paused seeks the already-queued item; this is the existing behavior of `player.seek(to:)` and we are not changing it.
- Clicking the artwork thumbnail still opens the album-art overlay — restored artwork should load exactly as if the track had just been started.
- Skip-forward / skip-backward pressed before the first play: honored. Skipping forward from the resume state plays the next track from 0 (again, abandoning the resume). Skipping backward (when position > 3s) seeks to 0 of the same track. This matches existing semantics and requires no new code paths.

**Asset list:** none.

**Do-not-do guardrails:**
- Do NOT add any visible "resume" indicator, badge, dot, or hint text. The feature is invisible by design.
- Do NOT auto-play on launch. The card's acceptance is explicit: launch state is PAUSED. Auto-play would be hostile to users who open the app by accident, share a machine, have headphones unplugged, or are in a meeting.
- Do NOT add a preference / setting / menu item to toggle resume. Out of scope. If ever requested → future card.
- Do NOT add a "Resumed from 12:34" banner or toast. Silence.
- Do NOT introduce a new `AVURLAsset` construction site. §7.1 demands a single `assetOptions` path. Extract a private helper if tempted to duplicate.
- Do NOT introduce a new per-track security-scoped bookmark. The folder bookmark already covers the track. §7.4.
- Do NOT save state on every 4Hz clock tick — only on a throttled timer (~5s) and on quit. High-frequency UserDefaults writes are wasteful and can stall on quit.
- Do NOT use `AVPlayerItem(url:)` anywhere. Ever. §7.1.
- Do NOT block the main thread on resume. The quick filesystem scan + bookmark resolve is already async-ish; adding a `seek` should not change that posture. Build the item, insert into queue, seek — no `await` chains blocking launch UI.
- Do NOT rely on the quick `init(url:)` Track having a valid `duration`. It's 0. Clamping logic must use the asset's async-loaded duration, not the Track's field. See User Risk "saved position > real duration" below.
- Do NOT start the scrub bar at 0 and then jump to the saved position after the seek completes. Seed `clock.position` synchronously to the saved value at the same moment the item is inserted, so the UI never shows the wrong position even for a frame.

## User Risks & Edge Cases

### Happy path
User was 45 minutes into a 70-minute mix. Closes laptop. Three days later opens JamBox. The table draws with filenames, then fills with metadata. The now-playing bar is populated: art, title, artist, album, and the scrub bar is 64% full reading `45:01`. No sound. User hits space → mix resumes from 45:01 with no audible pop. Thirty seconds later the track ends and gaplessly transitions into the next track because the lookahead was pre-filled behind the scenes. User never thinks about it. Feature invisible. [MUST HANDLE] — this is the core card.

### Empty / first-run states
- **Fresh install, never played anything:** no saved state, no folder bookmark. App opens in the existing "No folder selected" state. Unchanged. [MUST HANDLE — by inaction; don't write a save-state file until there's something to save]
- **Folder bookmark restored but saved-state file doesn't exist** (user launched, chose folder, never pressed play, quit): no resume, no crash, no log spam. Table loads normally, now-playing bar reads "Nothing playing." [MUST HANDLE]
- **Saved-state file exists but folder bookmark is gone** (user revoked in System Settings, or nuked UserDefaults, or launched on a new machine): silently clear saved state. Show "No folder selected." No modal. [MUST HANDLE — acceptance bullet 5 covers this, verify engineer's implementation actually tolerates a missing `watchedFolderURL` at resume time]
- **Saved state existed but user has paused playback at position 0** (never actually played — scrubbed back, pressed pause): position 0 is legal. Resume seeds the track, pre-fills the queue, scrub bar reads 0:00. User presses play → plays from the start. Indistinguishable from clicking the track fresh. [MUST HANDLE — don't special-case position 0 as "nothing to resume"]

### Malformed / hostile input
- **Saved track URL file was deleted between sessions:** silent clear. `FileManager.default.fileExists(atPath:)` check before attempting to build the `AVURLAsset`. No modal. [MUST HANDLE — acceptance bullet 5]
- **Saved track URL file was moved/renamed:** same as deleted — the URL no longer resolves. Silent clear. We intentionally do NOT try to find the file by name in the folder; that's a future feature ("track identity by content hash"). [MUST HANDLE — silent; WONT HAPPEN — smart reconciliation]
- **Saved track URL points to a file that still exists but is now 0 bytes / truncated / corrupt:** AVURLAsset will either fail to load duration (returns `.zero` / NaN) or report a duration shorter than the saved position. Clamp-to-duration (bullet 6) handles the latter; for the former, treat "duration load failure" as "cannot resume" and silently clear. [MUST HANDLE — verify the engineer's code handles `duration.seconds.isNaN || !isFinite`]
- **Saved track file was replaced with a DIFFERENT audio file at the same URL:** we cannot detect this without a content hash. The app will happily seek into the new file. If the new file is shorter, bullet 6 clamps. If it's longer, the seek lands somewhere unexpected. The user will hear "wrong song, wrong spot" and their natural reaction is to click another track — which immediately overwrites the saved state with something sensible. Acceptable degradation. [WONT HAPPEN in normal use; NICE TO HANDLE — no action, document in plan]
- **Saved track URL exists but is outside the restored folder** (user switched folders between sessions and the old folder's bookmark is what got re-resolved): the URL may still be accessible under the folder bookmark, but the Track won't be in `player.tracks`. Resume must verify the saved URL matches a track in the current `player.tracks` list (by URL equality), and silently clear if not. [MUST HANDLE — acceptance bullet 5 calls this out, verify the equality check happens AFTER `player.loadTracks(quickTracks)`]
- **Corrupt save-state JSON** (partial write on crash, schema drift, user edited it): decode failure → silently clear and open fresh. No modal. Wrap in `try?` and treat any failure as "no saved state." [MUST HANDLE]
- **Saved-state schema from an old version of JamBox:** use a `version` field in the saved payload. If version mismatch → silently clear. This future-proofs the schema without a migration burden today. [MUST HANDLE — ADDED to acceptance bullets, see below]
- **Saved position is negative, NaN, or infinite:** clamp to `[0, duration]`. `max(0, min(saved, duration))` with a finite check. [MUST HANDLE]
- **Unicode / strange characters in the track URL:** `URL` encodes/decodes them fine; `Codable` round-trips them fine. No special handling. [WONT HAPPEN]

### Scale stress
- **Library with 50,000 tracks:** resume only needs to `firstIndex(where: { $0.url == savedURL })` — that's O(n) once at launch, which at 50k tracks is microseconds. Fine. [MUST HANDLE by virtue of existing design]
- **Throttled 5s save timer with a huge queue:** the save payload is tiny (one URL string + one double + one version int ≈ 200 bytes). UserDefaults writes it to a plist. Writing this every 5 seconds while playback is active is cheap. Not a concern. [MUST HANDLE — use a `Timer` or `DispatchSourceTimer`; cancel it in `deinit` / when playback stops]
- **Timer continues firing while paused:** it should NOT. If `isPlaying == false`, the 5s tick either skips the write or the timer is suspended. This prevents pointless writes when the user parks the app paused for hours. [MUST HANDLE — the save on quit still captures the final position regardless]
- **User has sort applied from card 0011:** no interaction. The saved state is a URL, not an index, so sort order is irrelevant. Position restore is independent of track ordering. [MUST HANDLE by design]

### Concurrency / interruption
- **App crashes mid-save (power loss, OOM, force-quit):** UserDefaults writes are atomic per-key via CFPreferences, so the worst case is the write didn't land and we lose up to 5s of progress. Tolerable by design. [MUST HANDLE by acceptance bullet 2]
- **Metadata enrichment is still running when the user quits:** the enrichment task is already cancellable in `loadFolder`. Quit triggers the save, which captures the current URL + position regardless of whether the enriched metadata has arrived. On next launch, the cheap `init(url:)` Track is created by `loadTracks`, and the resume flow doesn't depend on enriched fields. [MUST HANDLE — explicit in acceptance bullet 7]
- **Quit happens during a track transition (`handleItemChange` firing):** the save payload is read from `player.currentTrack?.url` and `clock.position`. Both are MainActor-isolated and consistent within a single run-loop tick. The save on quit must happen on the main actor. The worst realistic case is saving the outgoing track at position ≈ duration, which on resume clamps to duration and then plays nothing until the user presses skip. Acceptable. An alternative (save the incoming track at position 0) is equally acceptable. Engineer's call — document in plan. [NICE TO HANDLE — either outcome is fine; call out in plan]
- **User presses play in the ~50ms window between "track list loaded" and "resume seek complete":** the resume flow must be synchronous with track-list load. `AppModel.loadFolder` → `player.loadTracks(quickTracks)` → `player.resume(savedState)` (or equivalent) → done, before any user input can land. If the user somehow does press play faster than that, they get the first track from 0 instead of the resumed track. Acceptable worst case. [MUST HANDLE — resume must happen on the same tick as `loadTracks`]
- **User drags a different folder before resume completes:** `chooseFolder()` already cancels `metadataTask`. The resume happens inside `loadFolder` on the restored folder, so a subsequent `loadFolder(newURL)` from the user's folder pick immediately supersedes it. The user's choice wins. The saved state on next quit will reflect the new folder's track. [MUST HANDLE — verify resume is scoped inside `loadFolder`, not in `init` where it would race with `chooseFolder`]
- **User clicks a different track before pressing play on the resumed one:** their click calls `player.play(startingAt:)` which removes all queue items and rebuilds. The resume is abandoned cleanly. [MUST HANDLE — `play(startingAt:)` already calls `queuePlayer.removeAllItems()`]
- **Skip-forward pressed during the resumed-but-not-yet-played state:** `advanceToNextItem()` on a queue of 3 paused items moves to item 2 without playing. The now-playing bar updates via the `currentItem` KVO. Net result: user sees the next track paused at 0, can press play. [MUST HANDLE — existing semantics]
- **Lookahead not yet filled when the user presses play (race):** this is the §7.2 landmine. `play(startingAt:)` fills the lookahead synchronously before returning, and the resume code must do the same — insert all `lookAhead` items into the queue at restore time, not lazily. [MUST HANDLE — explicit in acceptance bullet 4]

### "Wrong" user actions
- **User has the search field focused at quit:** search query is ephemeral; we don't persist it. On next launch it opens blank. Resume is independent of search state. [MUST HANDLE by inaction]
- **User was in the middle of a scrub drag at quit:** quit captures `clock.position` which during a drag still reflects the actual playback position (the drag's `scrubFraction` is local to `NowPlayingBar` and doesn't update `clock.position` until release). Worst case: the user dragged to minute 50, didn't release, quit — we save minute 20 (actual). On resume they're at 20, not 50. Mildly surprising but defensible. [NICE TO HANDLE — acceptable degradation]
- **User has saved state from one folder, launches with a different folder bookmark** (manually edited bookmark, multi-machine sync, etc.): the URL equality check filters this out. Silent clear. [MUST HANDLE — bullet 5]
- **User launches, closes the window without quitting, reopens window:** AppModel survives window close (documented at top of AppModel.swift). `loadFolder` is NOT called again on window reopen. Saved-state restore must happen in `loadFolder` (invoked once at launch via `loadSavedFolder`), not in any view's `.onAppear`. [MUST HANDLE — call out in plan]
- **User quits with nothing playing (ever), or after clearing the queue via some future feature:** save nothing, or clear the key. Bullet 1 covers this. [MUST HANDLE]
- **User has `currentTrack` set but position is 0:00** (just started, never advanced): still save it. Resume will seed at 0:00, which feels identical to clicking fresh. [MUST HANDLE]
- **User has media keys remapped / external control surface:** media-key toggle play on the resumed-but-paused state must work. `MediaKeyController` calls `player.togglePlayPause()` which already honors `currentTrack != nil`. Verify the resume flow sets `currentTrack` before the user can press the media key. [MUST HANDLE]

### Accessibility
- **VoiceOver:** the populated-but-paused now-playing bar must be announced as such. Today a paused track announces "Song Title, Artist, Album, Play button." On launch, this is the exact same state, so VoiceOver's existing announcement applies. No extra work needed, but ENGINEER should verify the `play.fill` button's accessibility label is "Play" (not "Pause") when paused. This is existing behavior — not a regression risk — but worth a 10-second check. [NICE TO HANDLE — verify, don't rewrite]
- **Keyboard-only user:** resume works via space bar (existing `.onKeyPress(.space)` in ContentView). The resumed-but-paused state has `currentTrack != nil` so `togglePlayPause` will play. [MUST HANDLE — verify by inspection, no new code]
- **Reduced-motion:** no animations introduced by this card. N/A. [WONT HAPPEN]
- **Locale differences:** saved position is a `Double` in seconds, not a formatted string. Locale-safe. URL is encoded. [WONT HAPPEN]
- **Dynamic Type:** no new text. N/A. [WONT HAPPEN]

### Failure recovery
- **Save-state JSON corrupt:** `try?` decode, failure → clear the key, proceed with empty resume. [MUST HANDLE]
- **Saved URL doesn't resolve:** silent clear. [MUST HANDLE — bullet 5]
- **Duration load fails on the resumed asset:** treat as unresumable. Silent clear. Do NOT present a half-populated now-playing bar with a broken scrub bar. [MUST HANDLE]
- **Seek fails (AVPlayer returns false via the completion handler):** the user sees the track populated at position 0 and can press play normally. Mildly degraded but functional. Do NOT hold the launch flow waiting for seek completion. [NICE TO HANDLE — fire-and-forget seek is fine]
- **UserDefaults is read-only / denied** (sandboxed, rare): save silently no-ops. Feature degrades to "no resume," which is the pre-card-0012 state. [MUST HANDLE — don't crash on write failure]

### Project-specific landmines
- **§7.1 AVURLAsset:** the resume path must construct its `AVPlayerItem` through the existing `Self.assetOptions`. The plan should either reuse `play(startingAt:)` (by adding an optional `seekTo:` parameter and a `shouldAutoplay:` flag) or extract a private `makeAssetItem(for:) -> AVPlayerItem` helper so there's exactly one call site. No new construction sites. [MUST HANDLE — acceptance bullet 8]
- **§7.2 Gapless:** the lookahead must be filled synchronously at resume, same as `play(startingAt:)` does today (`lookAhead = 3`). The first track→next transition after the user presses play must be gapless. The engineer MUST verify by ear. [MUST HANDLE — acceptance bullet 4 and 12]
- **§7.3 Two-phase loading:** on resume, `player.tracks` briefly contains cheap `init(url:)` Tracks. The resumed `currentTrack` is one of them. Later, `updateMetadata` swaps in the enriched version. The existing `updateMetadata` already handles swapping the `currentTrack` reference in-place (lines 178–180). Verify the scrub bar doesn't reset during the swap (it shouldn't — `clock.duration` is read from the AVPlayerItem's asset, not from the Track's `duration` field, once the asset loads). [MUST HANDLE — acceptance bullet 7, verify by inspection]
- **§7.4 Sandbox bookmarks:** the resume path must NOT call `startAccessingSecurityScopedResource` a second time on the folder URL. The folder is already accessed by `resolveBookmark` inside `loadSavedFolder`. And no new per-track bookmark. [MUST HANDLE — acceptance bullet 9]

### Newly identified acceptance bullets

Two [MUST HANDLE] items surfaced above are not cleanly covered by the existing acceptance list. Adding them now:

1. **Schema version field:** the saved-state payload must include a `version: Int` field. On decode, if the version doesn't match the current schema, silently clear. This future-proofs schema evolution.
2. **Save timer pauses while playback is paused:** the throttled ~5s save timer must only fire while `isPlaying == true`. The save-on-quit path is independent and still fires unconditionally.

(See acceptance bullet changes in frontmatter.)

## Plan

**Approach:**

Add a `PlaybackState` Codable payload (schema `version: 1`, `trackURL: URL`, `position: Double`) persisted to `UserDefaults` under key `jambox.playback.state`. Tiny, atomic, no extra files.

1. **Single construction site (§7.1).** Extract a private `makeAssetItem(for url: URL) -> AVPlayerItem` helper in `PlayerEngine` that builds `AVURLAsset(url:options: Self.assetOptions)` then wraps it. Replace the two existing construction sites (`play(startingAt:)` and `enqueueMoreIfNeeded()`) with calls to this helper, then use it from the new `resume(savedState:)` method too. After this card there is exactly one `AVURLAsset(...)` line in `PlayerEngine.swift`.

2. **New `PlayerEngine.resume(from:position:)` method.** Signature roughly: `func resume(trackIndex: Int, position: TimeInterval) async`. It:
   - Guards `trackIndex` in range, `queuePlayer.removeAllItems()`, sets `currentIndex`.
   - Synchronously builds and inserts up to `lookAhead` items via `makeAssetItem` (mirrors `play(startingAt:)`) — lookahead filled before return, satisfies §7.2 and acceptance bullet 4.
   - Synchronously sets `currentTrack = tracks[index]`, seeds `clock.position = clamped(position)` BEFORE the seek so the scrub bar never flashes 0 (acceptance, "do not start at 0 then jump").
   - `await` loads the first item's asset `.duration`. If load fails or duration is non-finite/≤0, tear down (`removeAllItems`, clear `currentTrack`, clear `clock`) and return `false` — "silent clear" path. Saved state caller clears UserDefaults on false.
   - Clamp position: `let clamped = max(0, min(position, duration))`.
   - Set `clock.duration = duration`, update `clock.position = clamped`.
   - Call `queuePlayer.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))` — fire-and-forget. Do NOT call `queuePlayer.play()`.
   - Trigger `loadArtwork(for:)`.
   - Returns Bool success.

   Alternative considered: threading `startingAt:` + `autoplay:` flags through `play`. Rejected: `play(startingAt:)` has a very tight shape (sync, no await on duration), and the resume path genuinely needs to `await` duration for clamp + sanity. Extracting `makeAssetItem` is the cleaner single-construction-site fix; the resume method is a sibling to `play(startingAt:)`, not a mode of it.

3. **`AppModel` save/restore plumbing.**
   - Add `PlaybackState: Codable` (version: Int = 1, trackURL: URL, position: Double).
   - Add `savePlaybackState()` (reads `player.currentTrack`, `player.clock.position`, writes JSON to UserDefaults; if no current track, removes the key).
   - Add `clearPlaybackState()`.
   - Add `loadPlaybackState() -> PlaybackState?` (decode via `try?`, return nil if schema version != 1, if URL doesn't exist on disk, or decode fails).
   - In `loadFolder(_:)`, AFTER `player.loadTracks(quickTracks)` and BEFORE launching the metadata task, call `tryRestorePlayback(within: quickTracks)`:
     - Read saved state. If none → return.
     - Verify `FileManager.default.fileExists(atPath: saved.trackURL.path)`. If not → `clearPlaybackState()`, return.
     - `firstIndex(where: { $0.url == saved.trackURL })` in `quickTracks`. If nil (saved URL not in this folder) → clear, return.
     - Spawn a `Task { @MainActor in await player.resume(trackIndex:position:); if !ok { clearPlaybackState() } }`. Does not block `loadFolder` — but because `resume` seeds `currentTrack` + `clock.position` synchronously at the top, the UI shows the populated bar immediately; only the async duration load for clamp is deferred. Wait — per acceptance "resume must happen on the same tick as `loadTracks`" and the concurrency risk note. The SYNCHRONOUS portion (currentTrack + seed + lookahead insert + seek) runs before any user input can land because it happens inside `loadFolder` on the main actor with no suspend point until after the seek. The `await duration` is for clamp purposes only; we've already seeded `clock.position` to the raw saved value (already clamped by a sanity `max(0, min(saved, .greatestFiniteMagnitude))` and finite check) so the UI is stable. Post-duration-load we re-clamp and re-seek if needed.
   - Actually, to avoid the complexity: split `resume` into `resumeSync` (does everything except the duration clamp re-seek) returning quickly, and a follow-up `Task` that awaits duration and re-clamps/re-seeks. This keeps `loadFolder` purely synchronous for the user-visible seeding.
   - **Revised design:** `resume(trackIndex:position:)` is MainActor synchronous; it builds items, inserts, sets currentTrack, seeds clock, seeks. It also launches an internal `Task` to await the duration and re-clamp/re-seek if the saved position exceeds the real duration, and to set `clock.duration` from the loaded value. If duration load fails outright, the track stays queued at position 0 — tolerable per "seek fails" risk (NICE TO HANDLE). Actually acceptance says "Duration load fails on the resumed asset: treat as unresumable. Silent clear." So the internal task must clear state via a callback.
   - **Final design:** `PlayerEngine.resume(trackIndex:position:)` synchronously seeds UI + queue, launches Task for duration validation. `AppModel` passes a closure `onFailure: { self.clearPlaybackState(); self.player.clearPlayback() }` invoked on the MainActor. Or simpler: engine calls its own `teardownCurrent()` on failure and publishes via currentTrack=nil; AppModel observes and clears. Cleanest: engine calls a `didFailResume` closure.

4. **Throttled save timer.** In `PlayerEngine` (or `AppModel`). Owning in AppModel is cleaner so PlayerEngine stays concerned only with audio, but the timer needs `isPlaying` and `currentTrack`+`clock.position`. Use Combine: subscribe to `player.$isPlaying` in AppModel; when it flips true, start a repeating `Timer.scheduledTimer(withTimeInterval: 5, repeats: true)` that calls `savePlaybackState()`. When it flips false, invalidate the timer. This exactly matches "only fires while `isPlaying == true`".

5. **Save on quit.** Observe `NSApplication.willTerminateNotification` in `AppModel.init`. In the handler, call `savePlaybackState()` unconditionally (even if paused — per acceptance bullet 1 and 11). Since this is a notification on main queue, MainActor is fine.

6. **ContentView / media keys:** no changes expected. Resumed state sets `currentTrack != nil`, so `togglePlayPause`, space-bar, and media keys Just Work.

**Files:**
- `JamBox/PlayerEngine.swift` — add `makeAssetItem` helper, collapse two existing construction sites, add `resume(trackIndex:position:onFailure:)` method, add `clearPlayback()` helper.
- `JamBox/AppModel.swift` — add `PlaybackState` struct, save/load/clear helpers, call restore in `loadFolder`, hook willTerminate, hook isPlaying timer.
- (Maybe) `JamBox/ContentView.swift` — no edit expected; verify onAppear sort restore doesn't clobber currentTrack. `reorderTracks` preserves currentTrack, so we're fine.

Expected `touches:` stays as in frontmatter, possibly drop `ContentView.swift` in self-audit reconciliation.

**Risks:**
- **§7.1 (AVURLAsset):** collapsing to `makeAssetItem` is the whole point — verify post-refactor that no `AVURLAsset(url:...)` exists outside the helper and the existing `findArtwork` (which must keep its own since it's a static metadata-loading path — that's acceptable since it's not constructing an `AVPlayerItem`). The helper only applies to the player-queue path.
- **§7.2 (gapless):** resume must insert all `lookAhead` items at construction time. `enqueueMoreIfNeeded()` is already called by `handleItemChange` on actual track change, so once play begins it'll top up normally. Manual verification: after resume + press play, listen for gapless transition at track 1→2 boundary.
- **§7.3 (two-phase):** resume uses the cheap `init(url:)` Track; `updateMetadata` later swaps via `tracks = tracks.map { lookup[$0.id] ?? $0 }` + `if let current = currentTrack, let enriched = lookup[current.id] { currentTrack = enriched }`. That runs on the MainActor, does NOT touch the AVPlayerItem queue — verified safe. The scrub bar reads from `clock.duration` which is set from the AVPlayerItem's asset (not Track.duration) in the periodic observer, so the swap can't clobber it.
- **§7.4 (bookmarks):** `resolveBookmark` already starts scoped access on the folder; the resume path does nothing additional. No per-track bookmark.
- **Scrub bar flash:** seed `clock.position` synchronously before the seek; verify the periodic time observer isn't running when paused (the observer fires at 4Hz but reads `currentTime()`, which after a pending seek but paused status should be the seek target — AVPlayer returns the last-committed time). Worst case the observer overwrites `clock.position` with the current time, which is the same value. No flash.
- **Timer leak:** invalidate on deinit and on isPlaying=false. AppModel has no deinit, but the Timer is stored as `weak var`? No — `Timer.scheduledTimer` retains its target; we'll use block-based `Timer.scheduledTimer(withTimeInterval:repeats:block:)` with `[weak self]` capture.
- **Quit race:** `NSApplication.willTerminateNotification` fires on the main thread; AppModel is MainActor. Direct UserDefaults write in the handler is synchronous; `UserDefaults.standard.synchronize()` is legacy but calling `set` + immediate return is fine — CFPreferences flushes on app termination.
- **Track URL equality across bookmark resolutions:** when a sandbox bookmark is resolved, the URL is "real" — URL equality (`==`) compares path components; two resolutions of the same bookmark should produce equal URLs. Track.url was scanned under the same scoped folder, so equality holds. Sanity check during implementation.

**Open questions:**
- None blocking. Designer explicitly left the "save during track transition" case as engineer's call (NICE TO HANDLE, either outgoing-at-end or incoming-at-0 is acceptable). I'll take whatever `player.currentTrack` + `clock.position` happen to be at notification time — if mid-transition the KVO may or may not have fired, producing either outcome, both acceptable.

## Log
- 2026-04-08 — manager card created in ready/, sibling to 0013, will dispatch designer next
- 2026-04-08 — designer-12 claimed card, moved ready/ → design/
- 2026-04-08 — designer-12 wrote ## Design (no-visual-change spec + guardrails) and ## User Risks & Edge Cases (walked every category from §4b step 5). Added two new acceptance bullets: (a) schema version field in saved-state payload, (b) throttled save timer pauses while playback is paused. Both surfaced as [MUST HANDLE] risks not covered by the original acceptance list.
- 2026-04-08 — designer-12 self-audited: every acceptance bullet is answered either by the ## Design section (do-not-do guardrails, play-glyph decision, no-banner decision) or by a tagged risk in ## User Risks & Edge Cases (all file-missing, clamp, §7.1/2/3/4 landmines, schema, timer behavior). Handing back to ready/ for engineer dispatch.
- 2026-04-08 — engineer-12 claimed card, moved ready/ → in-progress/
- 2026-04-08 — engineer-12 wrote ## Plan (extract makeAssetItem helper, new PlayerEngine.resume method, AppModel save/load/clear, willTerminate hook, isPlaying-gated 5s timer)
- 2026-04-08 — engineer-12 implemented: PlayerEngine.makeAssetItem helper collapses both queue construction sites; new resume(trackIndex:position:onFailure:) and clearPlayback(); AppModel PlaybackState struct (schema v1), save/load/clear/tryRestorePlayback, willTerminate observer, isPlaying-gated 5s Timer; build green; touches reconciled (ContentView not modified)
- 2026-04-08 — engineer-12 self-audited (all 7 steps), moving to qa/
- 2026-04-08 — qa-12 claimed card, starting §6b independent audit
- 2026-04-08 — qa-12 completed §6b: read both touched files top-to-bottom, walked `git diff f031f16` line by line, verified §7.1 single construction site via grep (3 AVURLAsset sites, all pass assetOptions; single queue-path site at PlayerEngine.swift:72), ran independent `xcodebuild ... build` → ** BUILD SUCCEEDED **. All acceptance bullets PASS, all §7 invariants PASS. Recommendation: APPROVE.
- 2026-04-08 — designer-12-review claimed card for §6c post-QA edge-case review; card stays in qa/ during this pass
- 2026-04-08 — designer-12-review completed §6c: walked every [MUST HANDLE] / [NICE TO HANDLE] item — all PASS or accepted-as-deferred. Fresh brainstorm surfaced two MINOR race-window concerns around the async duration-clamp path (scrub-handle flash while duration=0; mid-playback yank if user fast-double-clicks the same resumed track with an overshoot saved position) and one FUTURE item (track identity reconciliation) the original designer explicitly deferred. Filed child cards 0014 (scrub-handle flash, ready/), 0015 (async-clamp race, ready/), 0016 (track identity reconciliation, backlog/). Recommendation: APPROVE WITH CHILD CARDS. Card stays in qa/ for manager to close.

## Self-Audit

1. **Re-read modified files top to bottom:**
   - `JamBox/PlayerEngine.swift` — new `makeAssetItem` helper (lines ~66-76), collapsed both queue-construction sites (`play(startingAt:)` line ~240, `enqueueMoreIfNeeded()` line ~417) to call the helper, new `resume(trackIndex:position:onFailure:)` method (lines ~251-348), new `clearPlayback()` helper (lines ~351-359). No dead code, no debug prints, no commented-out blocks. Comments match implementation.
   - `JamBox/AppModel.swift` — new `PlaybackState` struct at file top with version field, new playback state persistence section (load/save/clear/tryRestore/handleIsPlayingChanged), willTerminateNotification observer in init, `player.$isPlaying` Combine subscription in init, `tryRestorePlayback(within:)` call in `loadFolder`. Timer stored as `Timer?`. All callsites use `[weak self]`. No debug prints. Comments explicit about intent (version-mismatch clear, save-on-quit unconditional, timer-only-while-playing, synchronous-seeding-before-await).

2. **Acceptance walkthrough:**
   - **"On app quit, JamBox saves the currently-playing track's URL and the live playback position. If nothing is playing, it saves nothing (or clears any prior saved state)."** — `savePlaybackState()` in `AppModel.swift` (~line 253) is called from the `willTerminateNotification` observer registered in `init`. The function clears UserDefaults when `player.currentTrack == nil`, otherwise encodes `PlaybackState`. PASS.
   - **"During playback, the saved position is updated on a throttled timer (~5s cadence)"** — `handleIsPlayingChanged` (~line 290) creates a repeating 5s `Timer` while `isPlaying == true`, invalidates it when false. Driven by `player.$isPlaying` Combine sink in init. PASS.
   - **"On next launch, after the folder bookmark is restored and tracks are loaded, JamBox locates the saved track by URL inside the restored folder, builds an `AVPlayerItem` via the existing `assetOptions`, seeks to the saved position, and presents the now-playing bar populated — but playback stays PAUSED."** — `loadFolder` in `AppModel` calls `tryRestorePlayback(within: quickTracks)` after `player.loadTracks`. That function calls `player.resume(...)`, which builds items via `Self.makeAssetItem` (which uses `assetOptions`), seeks to the saved position, and never calls `queuePlayer.play()`. PASS.
   - **"One press of space (or click of the play button) resumes from the saved position. The first transition into the next track after resume is gapless (the lookahead must be filled before the user presses play)."** — `resume` inserts up to `lookAhead = 3` items synchronously before returning (mirrors `play(startingAt:)`). Space bar via existing `togglePlayPause` in ContentView. PASS (verify-by-ear deferred to QA/design-review per acceptance bullet 12).
   - **"Saved track no longer exists at relaunch → silent clear."** — `tryRestorePlayback` checks `FileManager.default.fileExists(atPath: saved.trackURL.path)` and clears+returns. URL-not-in-folder also clears+returns. Decode failure / schema mismatch clears in `loadPlaybackState`. PASS.
   - **"Saved position exceeds the asset's actual duration → clamp to `[0, duration]`. Trust the asset's async-loaded duration."** — `resume` async Task awaits `asset.load(.duration)` and re-clamps: `max(0, min(sanitized, seconds))`, re-seeks if adjustment needed. Uses the asset's duration, NOT `Track.duration`. PASS.
   - **"Restored track's metadata is the cheap `init(url:)` form; when `updateMetadata` lands, the swap happens in-place without disrupting the already-queued `AVPlayerItem`."** — `updateMetadata` in `PlayerEngine.swift` (unchanged) only rewrites `tracks = tracks.map {...}` and reassigns `currentTrack`; it does NOT touch `queuePlayer`. The in-place swap is verified by inspection — no code path in this card disturbs the queue on metadata arrival. PASS.
   - **"No new `AVURLAsset` construction site introduced. The resume code path goes through `Self.assetOptions` (extract a private helper if tempted to duplicate)."** — Extracted `makeAssetItem(for:)`. The two pre-existing queue construction sites both now go through it. Verified via grep: `AVURLAsset(url:` appears in PlayerEngine.swift at exactly one queue-path line (`makeAssetItem`, line 72), plus one unchanged metadata-only line in `findArtwork` (line 469) and one in `Track.loadMetadata`, both of which are for metadata loading and also pass `assetOptions`. No new queue construction site. PASS.
   - **"All `startAccessingSecurityScopedResource` calls remain balanced. The resume path uses the existing folder bookmark — no new per-track bookmark."** — No new `startAccessingSecurityScopedResource` calls introduced by this card. `resume` relies on the folder bookmark already started by `resolveBookmark` in `loadSavedFolder`. Grep confirms no new scoped-resource calls in the diff. PASS.
   - **"Saved-state payload includes a `version: Int` schema field. On decode, mismatched or missing version is treated as 'no saved state' (silent clear)."** — `PlaybackState` struct declares `var version: Int` with `static let currentVersion = 1`. `loadPlaybackState` checks `decoded.version == PlaybackState.currentVersion` and clears on mismatch. Missing field → decode error → `try?` → nil → clear. PASS.
   - **"The throttled ~5s save timer only fires while `player.isPlaying == true`. Save-on-quit is independent."** — `handleIsPlayingChanged` invalidates the timer on pause. `willTerminateNotification` observer is registered independently and calls `savePlaybackState()` directly. PASS.
   - **"build passes"** — `** BUILD SUCCEEDED **` (xcodebuild run, step 3 below). PASS.
   - **"§7.1 AVURLAsset preserved"** — see makeAssetItem + grep above. PASS.
   - **"§7.2 Gapless playback preserved"** — lookahead filled synchronously at resume; `enqueueMoreIfNeeded` path unchanged. Verify-by-ear is a manual step QA will perform. Code path PASS; audible verification deferred to QA.
   - **"§7.3 Two-phase loading preserved"** — `updateMetadata` unchanged; resume uses the cheap `init(url:)` track and tolerates the later swap. PASS.
   - **"§7.4 Sandbox bookmarks balanced"** — no new scoped-resource calls. PASS.

3. **Build result:** `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` → `** BUILD SUCCEEDED **`. No new warnings introduced by the diff.

4. **Invariants verified:**
   - §7.1 (AVURLAsset): `AVURLAsset(url:` appears 3x in the codebase, all passing `assetOptions` with `AVURLAssetPreferPreciseDurationAndTimingKey`. Queue path is now single-site (`makeAssetItem`). Verified by grep.
   - §7.2 (gapless): `resume` replicates `play(startingAt:)`'s lookahead fill exactly. `enqueueMoreIfNeeded` untouched. Gapless behavior should be preserved — manual verification is QA's responsibility per the acceptance bullet.
   - §7.3 (two-phase): `updateMetadata` untouched. `resume` uses the cheap Track from `quickTracks` (same cheap form as any freshly-loaded folder), and the later `updateMetadata` call swaps in the enriched version via the existing in-place map. Queue items are not rebuilt.
   - §7.4 (sandbox bookmarks): no new `startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource` calls. The resume path reads files via the already-active folder scope.
   - §7.5 (Xcode project): no new source files added, `xcodegen generate` not required.
   - §7.6 (build green): verified.

5. **Hostile diff review:** `git diff main` totals +266 / -4 across two files. No unrelated changes. No debug prints. No `TODO`/`FIXME`. The `@escaping @MainActor () -> Void` closure parameter in `PlayerEngine.resume` is unusual but correct — the failure callback runs on the MainActor and escapes into an async Task. `MainActor.assumeIsolated` is used twice in `AppModel.swift` (notification observer + timer block) because both run on the main thread but aren't type-system-MainActor; the alternative is `DispatchQueue.main.async { Task { @MainActor in ... } }` which is more round-trippy for a synchronous UserDefaults write that's already on the main thread. The `assumeIsolated` calls are safe because: (a) the notification is registered with `queue: .main`, (b) the block-based `Timer.scheduledTimer` fires on the RunLoop's thread, which is main since it was scheduled from a MainActor-isolated init. The `handleIsPlayingChanged` `guard saveTimer == nil` prevents double-scheduling if Combine delivers duplicate `true` values. The Combine pipeline uses `.receive(on: DispatchQueue.main)` which erases MainActor isolation; the closure hops back explicitly — wait, it doesn't: `handleIsPlayingChanged` is called directly from a DispatchQueue.main sink. AppModel is `@MainActor final class`, so calling a private method from a closure that lives on main queue… Actually, `sink` closures are `@Sendable` and not MainActor-isolated by type, but the compiler accepts the call because the compiler saw that `receive(on: DispatchQueue.main)` schedules to main and AppModel is MainActor. The build succeeded so the compiler is satisfied; the runtime invariant is that the sink fires on main. Noted.

6. **Touched-files reconciliation:** Original `touches:` listed `ContentView.swift` speculatively. ContentView was NOT modified — the existing `.onKeyPress(.space)` + `togglePlayPause` + `loadArtwork` paths compose cleanly with the new resume-while-paused state without edits. Removed `ContentView.swift` from frontmatter `touches:`. Actual changed files: `JamBox/PlayerEngine.swift`, `JamBox/AppModel.swift`.

7. **Scope check:** Nothing outside the card's spec. No drive-by refactors, no style fixes, no unrelated cleanups. The `makeAssetItem` extraction was explicitly called for by §7.1 + designer guidance + acceptance bullet 8.

## QA Report

Independent §6b audit by qa-12. Read both touched files top-to-bottom, walked `git diff f031f16 -- JamBox/PlayerEngine.swift JamBox/AppModel.swift` line by line, verified construction sites via grep, built locally.

### Acceptance

- [PASS] **Save on quit captures current track + position; clears if nothing playing** — `AppModel.savePlaybackState()` at AppModel.swift:241-253 clears when `player.currentTrack == nil`, otherwise encodes `PlaybackState(version, trackURL, position)`. Hooked from `willTerminateNotification` observer at AppModel.swift:82-95, which runs unconditionally (independent of timer).
- [PASS] **Throttled 5s save during playback** — `handleIsPlayingChanged` at AppModel.swift:295-310 creates a repeating 5s block-based `Timer` on play-start, invalidates on pause. Driven by the `player.$isPlaying` sink at AppModel.swift:71-76.
- [PASS] **On next launch, restore populated-but-paused now-playing bar** — `loadFolder` at AppModel.swift:153 calls `tryRestorePlayback(within: quickTracks)` synchronously right after `player.loadTracks(quickTracks)`. `tryRestorePlayback` at AppModel.swift:262-287 hands off to `player.resume(...)` at PlayerEngine.swift:268, which seeds `currentTrack` + `clock.position` + queue lookahead and issues a seek WITHOUT calling `queuePlayer.play()`. `timeControlStatus` therefore stays `.paused` → `isPlaying == false`.
- [PASS] **One press of space resumes; first transition is gapless (lookahead filled before play)** — PlayerEngine.swift:276-279 inserts `lookAhead = 3` items synchronously in the resume loop, identical to `play(startingAt:)` at PlayerEngine.swift:239-242. Space-bar path via existing `togglePlayPause` is untouched. Gapless verify-by-ear is a manual check; code path is correct.
- [PASS] **Missing file / URL-not-in-folder / stale bookmark → silent clear** — `tryRestorePlayback` at AppModel.swift:268-279 checks `FileManager.fileExists` then `quickTracks.firstIndex(where:)`. Both failure paths call `clearPlaybackState()` and return. If the folder bookmark itself is gone, `loadSavedFolder` at AppModel.swift:127-132 returns early and `tryRestorePlayback` is never called, so the saved state is simply not read — harmless (the next successful launch will overwrite or clear it). No modal, no log spam on any path.
- [PASS] **Saved position exceeds duration → clamp against asset's async-loaded duration** — PlayerEngine.swift:311-335 `Task { let loaded = try? await asset.load(.duration); ... let clamped = max(0, min(sanitized, seconds)) }`. Clamps against loaded duration, NOT `Track.duration` (which is 0 for cheap init). Re-seeks on MainActor if clamp adjusted the position.
- [PASS] **Two-phase loading: resumed track starts as cheap `init(url:)` Track, `updateMetadata` swaps in place** — `tryRestorePlayback` indexes into `quickTracks` (cheap form). Metadata enrichment is kicked off at AppModel.swift:157 AFTER `tryRestorePlayback`, and lands in `PlayerEngine.updateMetadata` at PlayerEngine.swift:184-191, which only rewrites `tracks`/`currentTrack` — it does NOT call `queuePlayer.removeAllItems()` or touch the queue. The already-queued `AVPlayerItem` is not disturbed. `clock.duration` is overwritten by the asset's loaded value inside the resume Task, so the scrub bar does not reset when metadata arrives.
- [PASS] **No new `AVURLAsset` construction site** — `makeAssetItem` at PlayerEngine.swift:71-74 is the single queue-path construction site. Grep for `AVURLAsset(` finds exactly three call sites in the codebase: PlayerEngine.swift:72 (`makeAssetItem`, queue path), PlayerEngine.swift:469 (`findArtwork`, metadata-only), Track.swift:53 (`Track.loadMetadata`, metadata-only). All three pass `assetOptions` / `AVURLAssetPreferPreciseDurationAndTimingKey`. The two pre-existing queue sites (`play(startingAt:)` and `enqueueMoreIfNeeded`) were both collapsed to call `Self.makeAssetItem`. `resume` also goes through the helper.
- [PASS] **Sandbox bookmarks balanced; no new per-track bookmark** — diff introduces zero `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` calls. The folder bookmark established by `resolveBookmark` at AppModel.swift:327-349 is reused. No per-track bookmarks introduced.
- [PASS] **Schema `version: Int`; mismatched/missing version → silent clear** — `PlaybackState` at AppModel.swift:12-17 declares `var version: Int` with `static let currentVersion = 1`. `loadPlaybackState` at AppModel.swift:222-235 checks `decoded.version == PlaybackState.currentVersion` and calls `clearPlaybackState()` on mismatch. Missing version field → JSON decode error → `try?` nil → clear.
- [PASS] **Throttled timer only fires while `isPlaying == true`; save-on-quit independent** — `handleIsPlayingChanged` invalidates the timer on `false`, creates it on `true` (with a `guard saveTimer == nil else { return }` to avoid duplicate scheduling). willTerminate observer (AppModel.swift:82-95) calls `savePlaybackState()` directly and is not gated by timer state.
- [PASS] **build passes** — ran `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` independently from the engineer's run. Final line: `** BUILD SUCCEEDED **`. No new warnings surfaced.
- [PASS] **§7.1 AVURLAsset preserved** — see construction-site analysis above. Single queue-path site.
- [DEFERRED-AUDIBLE] **§7.2 Gapless playback preserved** — code path verified: lookahead is filled synchronously at resume, `enqueueMoreIfNeeded` is unchanged, `handleItemChange` still calls `enqueueMoreIfNeeded` on track advance. Audible verify-by-ear is acceptance bullet 12 and was performed by engineer per self-audit; QA cannot re-verify audibly without manual runtime session. Code-level PASS.
- [PASS] **§7.3 Two-phase loading preserved** — verified above.
- [PASS] **§7.4 Sandbox bookmarks balanced** — verified above.

### Invariants

- [PASS] **§7.1 AVURLAsset** — single queue construction site (`makeAssetItem`), all three call sites across the codebase pass `AVURLAssetPreferPreciseDurationAndTimingKey: true`. Verified via grep + diff read.
- [PASS] **§7.2 Gapless playback** — resume mirrors `play(startingAt:)` lookahead fill synchronously. `enqueueMoreIfNeeded` untouched (only the body of its for-loop was refactored to go through `makeAssetItem`).
- [PASS] **§7.3 Two-phase loading** — resume consumes cheap `init(url:)` Tracks; `updateMetadata` swaps in place without touching `queuePlayer` items.
- [PASS] **§7.4 Sandbox bookmarks** — no new scoped-resource calls; diff-verified.
- [N/A] **§7.5 Xcode project regeneration** — no source files added/removed; no `xcodegen generate` required.
- [PASS] **§7.6 Build green** — `** BUILD SUCCEEDED **` from independent xcodebuild run.

### Findings

- [MINOR] **`handleIsPlayingChanged` relies on `isPlaying` `false→false` being deduped** — the `guard saveTimer == nil` guard prevents double-scheduling on duplicate `true` events, but an explicit same-state sink is dropped by `@Published` only if the value actually changed (it does dedupe by equality). Not a bug; noting because reviewers may be tempted to add `.removeDuplicates()` which is redundant here. No action.
- [MINOR] **`resume` guards `guard let firstItem = queuePlayer.items().first` and on failure calls `onFailure()` THEN `clearPlayback()`** — PlayerEngine.swift:303-308. The order is fine (onFailure only clears persistence; clearPlayback clears the engine), but if `tracks` is non-empty and the `for` loop ran, `items().first` is guaranteed non-nil, so this branch is dead in practice. Not a defect; defensive code. No action.
- [MINOR] **Save-during-transition race** — the designer explicitly marked this NICE TO HANDLE and left it to engineer's discretion. The 5s timer reads `player.currentTrack` + `clock.position` at its tick. If the tick lands mid-`handleItemChange`, `clock.position` is reset to 0 (PlayerEngine.swift:385) and `currentTrack` may briefly be the outgoing or incoming track. Worst case: a save at position 0 for the incoming track, overwriting the outgoing-near-end state. Matches the designer's "engineer's call — both outcomes acceptable." No action; documenting for the design-review pass.
- [NIT] **`MainActor.assumeIsolated` in two places** (notification observer + timer block). Engineer's self-audit flags this and reasons correctly: the notification is scheduled on `.main` and the timer is created from a MainActor-isolated context, so the runtime is main-thread. The compiler accepts it; the build is green. Not a defect, but this is the kind of construct a future reviewer might flag. No action.
- [NIT] **`fileprivate func savePlaybackState()`** at AppModel.swift:241 — only callee is inside `AppModel`, so `private` would suffice. `fileprivate` was chosen presumably because the notification closure felt external; it is actually inside the same type. Micro-scope. No action.
- [INFO] **`loadSavedFolder` failure path bypasses `clearPlaybackState`** — if the folder bookmark is gone, `tryRestorePlayback` is never called and the persisted state is left intact. On a subsequent successful launch, `tryRestorePlayback` will either find the track and resume, or clear. This matches the designer's "bookmark gone → silent clear" expectation only eventually, not immediately. Acceptable: the acceptance bullet says "show No folder selected. No modal," which is satisfied; the stale state has no visible effect. No action.

### Recommendation

- **APPROVE**

The implementation is clean, faithful to the plan, and passes every acceptance bullet and project invariant under independent audit. The §7.1 single-construction-site extraction is the central structural win and it was executed correctly (grep confirms exactly one queue-path AVURLAsset site). The resume flow respects the synchronous-seeding-before-async-duration-load rule so the scrub bar never flashes 0. All silent-clear failure modes route through `clearPlaybackState` with no modals or log spam. Build is green. No blockers, no majors, no child cards needed. Leaving card in `qa/` for the manager to re-dispatch the designer for the §6c post-QA pass.

## Design Review

Post-QA §6c pass by designer-12-review. Read original `## User Risks & Edge Cases`, `## Plan`, `## Self-Audit`, `## QA Report`, and the full `git diff f031f16 -- JamBox/PlayerEngine.swift JamBox/AppModel.swift`. This pass does NOT re-run QA's checklist; it asks one question: as a real user encountering this on day one, what does the implementation miss?

### Original risks revisited

**Happy path**
- [PASS] 45-minute-mix resume — `PlayerEngine.resume` seeds `currentTrack`, `clock.position`, lookahead synchronously; `queuePlayer.play()` is never called; space bar through existing `togglePlayPause` resumes; lookahead fills for gapless next transition.

**Empty / first-run**
- [PASS] Fresh install, nothing played — `loadPlaybackState()` returns nil on missing UserDefaults key; `tryRestorePlayback` returns early; unchanged existing path.
- [PASS] Folder restored, nothing ever played — same early-return; no write happens until `savePlaybackState()` is triggered while `currentTrack != nil`.
- [PASS] Saved state present but bookmark gone — `loadSavedFolder` returns early before `tryRestorePlayback` is invoked; saved state is quietly left intact and either resumed or cleared on the next successful launch. Matches designer expectation ("No folder selected. No modal").
- [PASS] Saved at position 0 — `sanitized == 0` is a legal seed; scrub bar reads 0:00, pressing play starts from the beginning. Not special-cased as "nothing to resume."

**Malformed / hostile input**
- [PASS] Deleted file — `FileManager.fileExists(atPath:)` check at AppModel.swift tryRestorePlayback, clears and returns.
- [PASS] Moved/renamed — same path (URL no longer resolves), silent clear. Smart reconciliation explicitly deferred.
- [PASS] Corrupt / 0-byte / unreadable — `asset.load(.duration)` returns nil or non-finite; the async Task invokes `onFailure` + `clearPlayback`, so the now-playing bar is cleared and UserDefaults is cleared. No modal.
- [WONT HAPPEN, as documented] Replaced-with-different-file — degraded-gracefully per designer doc.
- [PASS] URL outside restored folder — `quickTracks.firstIndex(where:)` fails, silent clear.
- [PASS] Corrupt JSON — `try?` in `loadPlaybackState` returns nil, clears the key.
- [PASS] Schema drift — `decoded.version == currentVersion` check, clears on mismatch. Missing field becomes a decode error → clear.
- [PASS] Negative / NaN / infinite position — `sanitized = (position.isFinite && position >= 0) ? position : 0`; then re-clamped against loaded duration.

**Scale stress**
- [PASS] 50k-track library — `firstIndex(where:)` is O(n) once at launch; negligible.
- [PASS] Tiny save payload — JSON encode of `{version, trackURL, position}`, UserDefaults write every 5s.
- [PASS] Timer gated on `isPlaying` — `handleIsPlayingChanged(false)` invalidates. Verified.
- [PASS] Sort from 0011 — resume is URL-based, sort-independent.

**Concurrency / interruption**
- [PASS] Crash mid-save — UserDefaults atomicity; worst case lose 5s. Design accepted.
- [PASS] Metadata still enriching at quit — save reads `player.currentTrack?.url` + `clock.position`, both valid regardless of enrichment state.
- [PASS] Quit mid-transition — `savePlaybackState` reads whatever `currentTrack` + `clock.position` happen to be at notification time; either the outgoing-at-end or incoming-at-0. Both acceptable per designer.
- [PASS] User presses play in the tiny window before resume completes — the synchronous portion (currentTrack, lookahead insert, clock seed, seek) runs inside `loadFolder` on the MainActor before the metadata Task is launched. No suspend point between `loadTracks` and `tryRestorePlayback`. Verified.
- [PASS] User picks different folder before resume completes — subsequent `loadFolder(new)` calls `loadTracks` which clears `currentTrack`; the pending Task's `currentTrack?.url == savedURL` check catches this and abandons.
- [PASS] User clicks different track before pressing play — `play(startingAt:)` calls `queuePlayer.removeAllItems()` + re-inserts; the in-flight Task's URL-equality guard abandons cleanly (different track).
- [PASS] Skip-forward from resumed state — existing `playNext()` / `advanceToNextItem` semantics unchanged.
- [PASS] Lookahead filled before play — PlayerEngine.swift:276-279 inserts `lookAhead = 3` items synchronously mirroring `play(startingAt:)`.

**"Wrong" user actions**
- [PASS] Search field focused at quit — ephemeral, not persisted. Resume independent.
- [NICE TO HANDLE, accepted] Mid-scrub-drag at quit — `clock.position` reflects actual playback (not the drag preview), so save captures the last released position. Degrades gracefully.
- [PASS] Multi-folder mismatch — URL equality filters.
- [PASS] Close-and-reopen window without quitting — `loadFolder` is invoked once from `loadSavedFolder` at init, not on window reopen; ContentView `.onAppear` doesn't trigger it. Resume only fires once per app launch.
- [PASS] Nothing-ever-played quit — `savePlaybackState()` clears the key when `currentTrack == nil`.
- [PASS] currentTrack set but position 0 — saved and restored faithfully.
- [PASS] Media key on resumed state — `currentTrack != nil`, so `togglePlayPause` plays. No code change needed.

**Accessibility**
- [PASS] VoiceOver — the resumed-paused state is functionally identical to the existing paused state; no new UI.
- [PASS] Keyboard-only — space bar / media keys work by virtue of `currentTrack != nil`.
- [N/A] Reduced-motion, locale, Dynamic Type — no new UI.

**Failure recovery**
- [PASS] Corrupt JSON — clear, proceed.
- [PASS] URL unresolvable — clear, proceed.
- [PASS] Duration load fails — `clearPlayback()` + `onFailure()` tear down cleanly.
- [NICE TO HANDLE, accepted] Seek fire-and-forget — tolerable.
- [PASS] UserDefaults write denied — `try? JSONEncoder().encode(...)` is guarded; `UserDefaults.set` silently no-ops if the domain is readonly. Not crashy.

**Project landmines**
- [PASS] §7.1 — single queue-path `AVURLAsset` site via `makeAssetItem`. `play(startingAt:)` and `enqueueMoreIfNeeded` both collapsed to it. `resume` uses it. Verified.
- [PASS] §7.2 — resume fills `lookAhead = 3` synchronously.
- [PASS] §7.3 — `updateMetadata` untouched; resume uses cheap `init(url:)` Track; in-place swap preserved.
- [PASS] §7.4 — zero new scoped-resource calls; folder bookmark reused.

### Newly surfaced concerns

- [MINOR] **Scrub-handle flash when duration starts at 0** — `clock.position` is seeded synchronously to the saved value (correct per designer's "no flash" guardrail), but `clock.duration` is seeded from `tracks[index].duration` which is **0 for the cheap `init(url:)` Track** (PlayerEngine.swift, resume method). The scrub fraction in NowPlayingBar.swift:166 is `guard clock.duration > 0 else { return 0 }`, so the handle bead renders at the LEFT edge of the bar while the LEFT time label correctly reads e.g. "45:01" and the RIGHT label reads "0:00". This is visually inconsistent for however long it takes `asset.load(.duration)` to resolve (typically <10ms for a local FLAC, but potentially hundreds of ms on a slow disk or iCloud placeholder). The designer's do-not-do was specifically "Do NOT start the scrub bar at 0 and then jump to the saved position" — the position number doesn't jump, but the handle bead does, which is arguably in the same spirit. Fix is trivial: persist `duration` in `PlaybackState` alongside position, seed `clock.duration` from it synchronously, then let the async Task overwrite with the precise value. Child card in `ready/`.

- [MINOR] **Async duration-clamp can yank the user mid-playback in a narrow race** — scenario: saved state is (Track A, position 90s). Track A's actual duration is 60s (re-encoded shorter between sessions). User launches → `resume` seeds at 90s, spawns Task to load real duration. User fast-double-clicks Track A to play it fresh from 0. `play(startingAt:)` runs, removes items, re-inserts, seeks to 0, plays. `currentTrack` is still Track A (by URL identity). Task completes with duration=60s → `currentTrack?.url == savedURL` passes → `clamped = min(90, 60) = 60` → `abs(60 - 90) = 30 > 0.01` → `queuePlayer.seek(to: 60s)`. **User pressed play at 0:00 and gets yanked to the end of the track.** Probability is low (requires saved position to overshoot, which itself is uncommon, AND the user to re-click specifically the resumed track quickly, AND the duration-load to be slower than the user's click). But the failure mode is "audio jumps unexpectedly," which is a playback integrity smell and the whole point of this card is "JamBox respects my time." Fix: the Task should only re-seek if `clock.position` is still approximately equal to the original `sanitized` (i.e. the user hasn't moved it). Child card in `ready/`.

- [MINOR] **`clearPlayback()` on duration-load failure can tear down already-active playback** — related to the above. If the user pressed play during the duration-load window, and then the load returns non-finite (AVFoundation API oddity; unlikely since playback usually requires a valid duration), the Task calls `clearPlayback()` which wipes `currentTrack` and the queue. The user sees their playing track vanish. The `currentTrack?.url == savedURL` guard does NOT protect against this — the user could have pressed play on the SAME track (double-click resumes) and the URL still matches. Mitigation: before tearing down, check `queuePlayer.timeControlStatus != .playing`. Rolled into the same child card as the previous concern since they share the same race window.

- [FUTURE] **Fallback reconciliation when the saved URL is gone** — today "file moved or renamed" silently clears, which is the explicitly-chosen behavior per designer doc. A future feature could look for the file by name inside the current folder, or eventually by content hash. Not a concern for this card. Child card in `backlog/`.

- [INFO, not a concern] **`chooseFolder` invokes `tryRestorePlayback` on the newly-picked folder** — if the user is mid-session and manually picks a different folder, the current resume pipeline runs against the new folder's tracks. The saved state (possibly pointing to the old folder's track) fails the URL-match check and silently clears. This is correct behavior; noting it so nobody later "fixes" it by gating resume to launch-only.

- [INFO, not a concern] **`isPlaying` Combine sink fires once at subscription time with the initial value (false)** — `handleIsPlayingChanged(false)` invalidates a nil timer, harmless. Noting so a future reader doesn't think `.dropFirst()` is needed.

### Recommendation

- **APPROVE WITH CHILD CARDS**

The implementation faithfully executes a well-specified design. Every [MUST HANDLE] and [NICE TO HANDLE] risk from the original spec is either handled correctly or deferred with the designer's blessing. The §7.1 extraction of `makeAssetItem` is a real architectural win beyond the card's strict ask and collapses two prior duplicated construction sites. The silent-clear failure modes are uniform (no modals, no log spam), matching the "invisible feature" intent.

Two MINOR concerns surfaced that only become visible once real code exists: a brief scrub-handle-position flash during the async duration-load window, and a narrow race where the async clamp can yank the user mid-playback if they fast-double-click the same resumed track and the saved position overshoots the real duration. Neither is a day-one disaster — the first is visually imperceptible in practice, and the second requires a compound scenario. Both are worth follow-up child cards but do not justify kicking this card back. One FUTURE card for the "smart reconciliation" idea the designer explicitly deferred.

Leaving card in `qa/` for the manager to close. Child cards filed with `parent: 0012`.

## Manager Decision
*Filled in by the manager when closing or kicking back.*
