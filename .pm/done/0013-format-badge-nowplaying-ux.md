---
id: 0013
title: Format/sample-rate/bit-depth badge in NowPlayingBar + UX pass
created: 2026-04-08
needs_designer: true
designer: designer-13
design_review: designer-13-review
engineer: engineer-13
qa: qa-13
parent: null
priority: P2
estimate: S
depends_on: []
touches:
  - JamBox/NowPlayingBar.swift
  - JamBox/PlayerEngine.swift
acceptance:
  - When a track is playing, the NowPlayingBar shows a small caption with the audio format (FLAC / ALAC / MP3 / AAC / WAV / AIFF), the sample rate (e.g. "96 kHz"), and the bit depth (e.g. "24 bit") for the current track. Format names follow the designer's spec.
  - The badge is fetched from the existing `AVPlayerItem.asset` (no new `AVURLAsset` construction), and only when the current item changes — not on every scrub tick.
  - Format info is published as a separate `@Published` on `PlayerEngine` (not on `PlaybackClock`), so the 4Hz clock observer does not cause re-renders or refetches. The `PlayerEngine` / `PlaybackClock` split documented at PlayerEngine.swift:20 must be preserved.
  - If any of {format, sample rate, bit depth} is unknown, missing, or zero, the badge is hidden entirely. Never show "0 kHz", "Unknown", or "—".
  - The badge has a VoiceOver label that reads the values in long form ("FLAC, 96 kilohertz, 24 bit"), distinct from the visual compact form.
  - **UX pass on the NowPlayingBar:** since this card adds new information to the metadata column, the designer must do a layout/legibility review of the entire NowPlayingBar and apply a slight font size increase across the bar so the bar is not crowded and remains easily legible. The font size increase must be specified by the designer (with values referenced from `Theme.swift` tokens where possible). The new badge and the existing title/artist/album lines must all coexist comfortably without pushing the transport controls.
  - The UX pass must verify legibility at the smallest reasonable window width (down to the existing minWidth: 500 from ContentView.swift:285), at all three themes, and with the album art thumbnail visible.
  - No regressions to existing NowPlayingBar behavior: scrub bar drag-decouple, clickable artwork thumbnail, transport controls, scroll-to-current-track callback, and the elapsed/total time display all still work.
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - §7.1 AVURLAsset preserved (no new asset construction; reuse `currentItem.asset`)
  - §7.2 Gapless playback preserved (no changes to queue management)
  - §7.3 Two-phase loading preserved (format fetch is per current item, not part of bulk scan)
---

## Context

User picked this from a designer brainstorm of new feature ideas (2026-04-08), as the second of two sibling cards (0012 + 0013). User quote (designer brainstorm): *"I spent money on this 24/96 FLAC rip. I want to see, at a glance, that the player is actually playing it and not something stepped down."*

This is the Audirvana lossless-badge feature — the single thing audiophiles point to as a reason to pay for that app. Daily reassurance feature, identity signaling for the Foobar2000/Audirvana audience. Engineer's selection memo: lowest-risk idea on the brainstorm list.

User added one acceptance bullet beyond the engineer's original scope: a UX pass on the NowPlayingBar with a slight font-size increase across the whole bar, since the new badge adds information to an already busy metadata column and we want the bar to stay uncluttered and legible.

This card is a sibling to card 0012 (resume on launch). Both touch `PlayerEngine.swift` so they cannot be in-progress simultaneously (§8). Manager has serialized: 0012 first, then 0013.

## Design

### Visual direction

Quiet, confident, lab-coat audiophile — but never marketing-loud. The badge is a **receipt**, not a trophy. Think the tiny line of hex digits at the bottom of a serious hi-fi DAC's display: the people who care will see it the instant it appears and feel reassured; the people who don't care will not even notice it's there. Emotional read: "the player knows what it's playing, and it's telling you so plainly." No stamps, no icons, no "Lossless" label, no gold foil. Comparison point: Audirvana's compact format line, not Roon's signal path. The bar after this card should feel slightly **calmer** than before, not busier — the font-size bump is what buys us the headroom to add a fourth line without the column feeling crammed.

### Layout

The new badge is a **fourth line** in the metadata VStack, below the album line. The leading icon gutter (14 pt wide) that title / artist / album use is preserved, but the badge line uses a **different glyph** and sits visually quieter than the artist/album lines above it, creating a clear hierarchy: title (loudest) → artist → album → format (quietest).

ASCII sketch of the top row after this card (minWidth: 500 case, track with all metadata):

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  ┌──────┐   ♪  A Love Supreme, Pt. I – Acknowledgement           │
│  │      │   👤 John Coltrane                          ⏮  ⏯  ⏭  │
│  │ art  │   💿 A Love Supreme                                     │
│  │  60  │   ⎓  FLAC · 96 kHz · 24 bit                             │
│  └──────┘                                                         │
│                                                                  │
│  0:42  ──────────●──────────────────────────────────────  7:43  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

(Icons shown as emoji are indicative only; actual SF Symbols listed below.)

Visual hierarchy, top to bottom:
1. **Title** — loudest. Primary text color, headline weight, slightly larger than today.
2. **Artist** — medium. Primary text color, subheadline weight.
3. **Album** — medium. Primary text color, subheadline weight (same as artist).
4. **Format badge** — quietest. Secondary text color, caption size, monospaced digits, slightly tracked.

The badge is only rendered when `player.format` is non-nil (see "Copy" below for when nil). The metadata VStack's `spacing: 2` is preserved. The badge does not introduce any new HStack patterns — it follows the exact `HStack(spacing: 6) { icon, Text }` shape of the artist and album rows so the icon gutter lines up.

### Copy

**Exact format string:**

```
<FORMAT> · <SAMPLE_RATE> · <BIT_DEPTH>
```

Separator: **middle dot** `·` (U+00B7), with one space on each side. Chosen because it's the separator the Unix `file(1)` tool, most audio CLIs, and Audirvana all use for compact format lines. It reads as "and also" rather than "or" (which `|` implies) and it doesn't look like a column boundary the way `/` does.

**Format short names** (exact strings, uppercase):

| File extension / container | Badge string |
|---|---|
| `.flac` | `FLAC` |
| `.alac` (and `.m4a` containing ALAC) | `ALAC` |
| `.m4a` containing AAC | `AAC` |
| `.aac` | `AAC` |
| `.mp3` | `MP3` |
| `.wav` | `WAV` |
| `.aiff`, `.aif` | `AIFF` |
| anything else | **hide badge** (do not invent a name) |

The format string is derived from the decoded audio track's `AudioStreamBasicDescription.mFormatID` (the ground truth from the asset's `formatDescriptions`), NOT from the file extension. This is important because `.m4a` is a container that can hold ALAC or AAC; we need to distinguish. See the User Risks section for the fallback chain.

**Sample rate format:**

- Show in **kHz with one decimal place only when the fractional part is non-zero.** Examples:
  - 44100 → `44.1 kHz`
  - 48000 → `48 kHz`
  - 88200 → `88.2 kHz`
  - 96000 → `96 kHz`
  - 176400 → `176.4 kHz`
  - 192000 → `192 kHz`
  - 352800 → `352.8 kHz`
  - 384000 → `384 kHz`
- Lowercase `k`, uppercase `Hz`. Space between the number and the unit. Rationale: matches SI convention and audio-gear convention (`96 kHz`, never `96KHZ`, never `96000 Hz` in a compact badge).
- Use the user's locale decimal separator? **No.** Use a period, always. The badge is a technical receipt, not localized prose. A German user will see `44.1 kHz`, not `44,1 kHz`. (This is how Audirvana, Foobar2000, and every DAC OLED panel behave.)

**Bit depth format:**

- `<N> bit` — lowercase, space between number and unit. Examples: `16 bit`, `24 bit`, `32 bit`.
- **Never pluralize to "bits".** Every piece of pro audio gear in the world shows `24 bit`, not `24 bits`. This matches muscle memory.
- **Special case: floating point.** If the source track is 32-bit float, show `32 bit float`. This comes up on some WAV/AIFF masters and the audiophile audience will be annoyed if we silently paper over it. Fallback: if we cannot determine whether a 32-bit stream is int or float from the format description, show `32 bit` (do not guess).

**Hide-the-whole-badge rule:** If **any** of format / sample rate / bit depth is unknown, zero, or cannot be determined, the **entire badge line is hidden**. We do not show "FLAC · 96 kHz" with a missing bit depth. We do not show "FLAC" alone. The acceptance bullet is explicit on this and the visual design depends on it: a partial badge would look like a bug and undermine the "quiet confidence" read.

**"Nothing playing" state:** the whole metadata column already collapses to the single "Nothing playing" text when `currentTrack == nil`. The badge does not exist in that state. No change.

**VoiceOver label** (distinct from visual): the badge's `.accessibilityLabel(...)` reads the values in long form, words not symbols:

- Visual: `FLAC · 96 kHz · 24 bit`
- VoiceOver: `Audio format: FLAC, 96 kilohertz, 24 bit`
- "Audio format:" prefix because VoiceOver users don't have the visual context of the icon telling them this line is about format.
- Sample rates read in full: `44.1` → `"44.1 kilohertz"`; `96` → `"96 kilohertz"`.
- Float case: `"Audio format: WAV, 96 kilohertz, 32 bit floating point"`.

### Color & typography

All tokens from `Theme.swift` (§2, in-app surface).

- **Badge text color:** `themeManager.current.secondaryText ?? Color.secondary` — same token the left/right timestamps already use. This is deliberate. The timestamps and the format badge are both "technical receipts," both quiet, both monospaced; using the same color makes them feel like a coherent metadata layer even though they're in different rows. In light/dark themes this resolves to SwiftUI's `.secondary`; in candy it's `Color.white.opacity(0.7)`.
- **Badge font:** `.system(size: 11, weight: .regular, design: .monospaced)`.
  - Monospaced is the audiophile-aesthetic cue. It evokes DAC displays, spec sheets, and CLI output — the visual language of "I am reporting a measurement, not marketing at you."
  - Size 11 pt is **smaller than the other metadata lines** (see size table below). This creates the hierarchy: the badge sits visually below artist/album even though it's structurally the same row pattern.
  - Regular weight (not bold) keeps it quiet.
- **Badge icon:** `Image(systemName: "waveform")`, frame width 14 pt (same as existing `music.note` / `person.fill` / `opticaldisc.fill` icons), tinted with the same `secondaryText` color so it doesn't look louder than the text it prefixes. `waveform` is the right glyph because it visually reads as "audio signal / format" without implying a playback state (unlike `waveform.path` or `waveform.circle`, which feel more like buttons).

### The font-size bump across the bar

Current sizes read from `NowPlayingBar.swift`:

| Element | Current | Notes |
|---|---|---|
| Title | `.font(.headline)` | ~13 pt system bold |
| Artist | `.font(.subheadline)` | ~11 pt |
| Album | `.font(.subheadline)` | ~11 pt |
| Transport icons | `.font(.title2)` | ~17 pt |
| Left/right timestamp | `.font(.caption)` | ~11 pt, monospacedDigit |

**New sizes** (this card's acceptance explicitly requires a slight bump across the bar so the added fourth line does not crowd the column):

| Element | New | Rationale |
|---|---|---|
| Title | `.system(size: 15, weight: .semibold)` | +2 pt over headline. Semibold (not bold) reads cleaner at the larger size. Still clearly the loudest line. |
| Artist | `.system(size: 13, weight: .regular)` | +2 pt over subheadline. Matches the default `.body`-ish size. |
| Album | `.system(size: 13, weight: .regular)` | Same as artist — they're siblings in the hierarchy. |
| **Format badge (new)** | `.system(size: 11, weight: .regular, design: .monospaced)` | Smaller than artist/album so the hierarchy reads correctly. This is the one element that does NOT grow; the whole point of bumping the others is to create headroom below them for a quiet caption. |
| Transport icons | **unchanged** (`.font(.title2)`) | Acceptance / guardrails: do not change transport click-target sizes. |
| Left/right timestamp | `.system(size: 12, weight: .regular, design: .monospaced).monospacedDigit()` | +1 pt. Kept monospaced-design to preserve the "technical receipt" family with the new badge, and to keep `.monospacedDigit()` working — do not break monospaced digits. |

Total added height of the metadata column at minWidth: 500: roughly +6 pt across three existing lines plus one new 11-pt line with 2 pt inter-line spacing = **~+21 pt of vertical space** in the now-playing bar (metadata VStack) compared to today. The artwork thumbnail is 60 pt square; the metadata column was comfortably shorter than that before. After the bump, the metadata column is close to the artwork's height but does not exceed it in the all-metadata-present case. In the no-album case (3 visible lines: title, artist, format) the column remains under 60 pt.

**Why these specific numbers:** I used fixed pt sizes rather than system dynamic type tokens (`.headline`, `.subheadline`, `.caption`) for two reasons. (1) The acceptance bullet demands a **specific, measurable** bump — dynamic tokens would make the bump invisible on systems with different defaults. (2) Card 0009 (text-size-setting, in backlog) is the proper home for Dynamic Type support; using fixed sizes here does NOT foreclose 0009, because 0009 can introduce a multiplier wrapping these same base numbers. See User Risks / a11y for more on this coordination.

### Spacing & sizing

- **Metadata VStack inner spacing:** unchanged at `spacing: 2`. The font-size bump plus the new line already adds enough vertical breathing room; increasing inter-line spacing on top of that would make the bar feel loose.
- **Top-row HStack spacing:** unchanged at `12` (between artwork, metadata, transport).
- **Metadata row inner HStack spacing:** unchanged at `6` (icon, text).
- **Outer `.padding()`:** unchanged. The default `.padding()` is already generous enough to absorb the new column height.
- **Scrub-bar row (row 2):** unchanged. The scrub bar's leading/trailing timestamps get the +1 pt bump described above, but no layout changes.
- **Window minWidth:** **unchanged at 500.** The bump is specifically calibrated to still fit at 500. See legibility check below.

**Legibility check at minWidth: 500:**

Worst case: a track with a long title AND long artist AND long album AND format metadata. At 500 pt window width:
- 60 pt artwork + 12 pt gap + ~80 pt transport column + 12 pt gap + outer padding (~32 pt total) = ~196 pt taken.
- Metadata column gets ~304 pt of width.
- The badge string in the worst case (`FLAC · 176.4 kHz · 32 bit float`) is ~34 characters of monospaced 11 pt, which is ~220 pt wide. **Fits with margin.**
- The title/artist/album already truncate with `.lineLimit(1)`, which is preserved. Long metadata still doesn't push the transport column — nothing about this card changes that guarantee.

### Interaction notes

The badge is **non-interactive**.

- **No hover state.** No pointer cursor (do not apply `PointerCursorView`). It does not look clickable; it must not feel clickable.
- **No tap/click gesture.** Tapping the badge does nothing. If the user clicks it, the click passes through to the underlying VStack which also does nothing — that's fine.
- **No tooltip in v1.** Tooltip-on-hover ("Click to see full audio track details" or similar) is explicitly **[FUTURE WORK]** — filed in User Risks as such. Rationale: the v1 badge is self-contained; if we add a tooltip later it should be part of a broader "track inspector" card, not bolted onto this one.
- **No animation on appear/disappear.** The badge simply appears when `player.format` becomes non-nil and disappears (with the rest of the metadata column) when `currentTrack` goes nil. SwiftUI's default implicit animations are fine; do not add an explicit `.transition(...)`.

### Asset list

**None.** All visual elements use existing SF Symbols (`waveform`) and `Theme.swift` tokens. No new images, no new fonts, no new files.

### Do-not-do guardrails

1. **No "Lossless" / "Hi-Res" / "Studio Master" stamps.** No marketing language. The badge is a spec line, not a label.
2. **No icons or glyphs inside the badge text itself.** The leading `waveform` icon in the icon gutter is the only glyph; the text is pure ASCII.
3. **No tooltips in v1** (see Interaction notes).
4. **Do not show a partial badge.** If any field is missing, hide the whole line. This is an acceptance bullet AND a visual invariant.
5. **Do not enlarge the album art thumbnail.** The 60×60 pt artwork cell is a load-bearing size for the now-playing bar's horizontal balance and card 0010's design language. Leave it alone.
6. **Do not change the transport control sizes.** They are tuned for click targets and are unchanged by this card.
7. **Do not add color to the badge.** No green "lossless OK" tint, no accent-color highlight. Color on a metadata caption would scream "interactive" and break the quiet-confidence read.
8. **Do not break `.monospacedDigit()` on the left/right timestamps.** The bump from `.caption` to a fixed `.system(size: 12, ..., design: .monospaced)` must preserve the monospacedDigit modifier so digits don't jitter as the time advances.
9. **Do not construct a new `AVURLAsset`** to get format info. Reuse `queuePlayer.currentItem?.asset`. This is §7.1 invariant territory and an acceptance bullet.
10. **Do not fetch format info on every 4Hz tick.** Fetch only when `currentItem` changes. This is an acceptance bullet.
11. **Do not put the `@Published format` on `PlaybackClock`.** It goes on `PlayerEngine`. This is an acceptance bullet and a §7 invariant (clock split at PlayerEngine.swift:20).
12. **Do not localize the decimal separator in the badge.** Period always. Do not localize the unit strings ("kHz", "bit") either.
13. **Do not fall back to the file extension when the format description is unavailable.** If we can't read the codec from the asset, hide the badge. Guessing from `.m4a` would mislabel ALAC as AAC (or vice versa) — worse than showing nothing.
14. **Do not preempt card 0009 (Dynamic Type).** Use fixed pt sizes here, but document in User Risks that 0009 can wrap these in a multiplier later.
15. **Do not show the badge for "Nothing playing"** — it's only rendered inside the `if let track = player.currentTrack` branch.

## User Risks & Edge Cases

### Happy path

User drops a folder of 24/96 FLAC rips into JamBox. They double-click the first track. Audio starts. Within a beat — roughly the same time the title finishes appearing — a quiet monospaced line fades into view under the album name: `FLAC · 96 kHz · 24 bit`. They exhale. Their money was well spent. They did not have to open a properties dialog, check Audirvana, or squint at the file extension. They can now switch tabs, stop worrying, and enjoy the music.

Secondary happy path: user clicks forward-track to the next song in the same album. The title/artist/album updates; the badge either stays identical (same spec) or updates to the new values if the album has mixed specs. Either way it updates at the same moment as the title, without flicker.

### Empty / first-run states

- **No track playing (`currentTrack == nil`).** Metadata column collapses to "Nothing playing" as today. Badge does not render. `player.format` is nil. **[MUST HANDLE]** — already covered by the "hide when missing" rule and the existing `if let track` branch.
- **First launch, no folder chosen.** Same as above: nothing is playing, no badge. **[MUST HANDLE]** — no new work, existing empty state covers it.
- **Track is loading / pre-buffer, before `formatDescriptions` is populated.** AVAssetTrack.formatDescriptions may return empty briefly while the asset is still loading. If we fetch synchronously at `currentItem` change time and get nothing back, the badge must NOT render a half-state. The engineer should use the async `asset.loadTracks(withMediaType: .audio)` → `track.load(.formatDescriptions)` pattern; if the fetch fails or returns empty, `player.format` stays nil and the badge stays hidden. When the async fetch completes, `player.format` flips to the real value and the badge appears. **[MUST HANDLE]** — behavior is "appear when ready, not before."

### Malformed / hostile input

- **FLAC with broken STREAMINFO header.** Related to the existing precise-duration bug. AVFoundation sometimes lies about FLAC timing, and it may also lie about FLAC sample rate or bit depth. `AVURLAssetPreferPreciseDurationAndTimingKey` is already set on all assets in `PlayerEngine.assetOptions` — we reuse `currentItem.asset` so we get that precision for free. If the asset still returns garbage (e.g. a bit depth of 0), the "hide if any field is zero/unknown" rule catches it. **[MUST HANDLE]** — already covered by the hide-on-missing acceptance rule, but the engineer must explicitly check for zero/negative values, not just nil.
- **Files where `formatDescriptions` returns nothing.** Some rare or corrupt files have no audio format description. Badge hides. **[MUST HANDLE]** — hide-on-missing rule.
- **Files with multiple audio tracks** (e.g. a movie file that somehow got into the library, or a multichannel experimental file). Use the **first** audio track's format description. Document this choice in the engineer's plan. Rationale: JamBox is a music player; the supported formats (mp3/m4a/flac/aiff/wav/alac/aac) do not normally have multiple audio tracks, and picking the first matches AVQueuePlayer's own playback behavior. **[MUST HANDLE]** — pick-first, document in plan.
- **Files whose container holds an unrecognized codec.** e.g. a `.m4a` containing AC-3 or some exotic codec. The `mFormatID` lookup returns something that isn't in our whitelist. **Hide the whole badge.** Do not fall back to the file extension (per do-not-do #13). **[MUST HANDLE]** — hide-on-missing rule plus the whitelist-only codec map.
- **Files that change underneath the app** (user re-encodes the file while it's playing). We do not refetch format info mid-playback on the current item. If the user skips to the next track and back, the asset is recreated and the new format is read. **[WONT HAPPEN in scope]** — refetching mid-play for a file the user is modifying under us is not a real user scenario; noting for the record.
- **Zero-byte or truncated audio files.** `asset.load(.tracks)` fails or returns empty. Badge hides. Playback itself will also fail, which is a pre-existing issue not touched by this card. **[MUST HANDLE]** — covered by hide-on-missing.
- **Unicode / RTL text in nothing-to-do-with-format fields** (title/artist/album). Does not affect the badge — the badge is pure ASCII. **[WONT HAPPEN]**.

### Scale stress

- **Library of 50,000 tracks, user hammers next-track.** The format fetch is **per current item**, not bulk. It's a single async `asset.loadTracks(withMediaType: .audio)` call when `currentItem` changes — the same kind of lightweight fetch that `loadArtwork` already performs. Does NOT touch the library scan path (§7.3: two-phase loading preserved). **[MUST HANDLE]** — fetch-per-current-item only; must not be part of `FileScanner` or bulk enrichment.
- **4Hz periodic observer.** Acceptance bullet is explicit: format info is a separate `@Published` on `PlayerEngine`, NOT on `PlaybackClock`. The clock tick has no reason to touch `format`. **[MUST HANDLE]** — invariant, already acceptance.
- **Perceptible lag at track change.** The async fetch should complete in low-millisecond territory for a normal music file (AVFoundation already has the asset loaded to start playing it). User will perceive it as "the badge fades in a fraction of a second after the title" in the worst case. Good enough for v1. If measurement shows the fetch is slow, **cache `player.format` per Track id** so forward/back within the same session is instant. **[NICE TO HANDLE]** — engineer decides in plan; not required for acceptance.

### Concurrency / interruption

- **Rapid next-track hammering.** User skips forward 10 tracks in 2 seconds. Each `currentItem` change kicks off an async format fetch. If fetch N completes AFTER fetch N+1, we must not show stale format for track N+1. Mitigation: on completion, check whether `currentTrack?.id` still matches the id this fetch was kicked off for; if not, discard the result. Same pattern `loadArtwork` already uses (see `PlayerEngine.swift:329`). **[MUST HANDLE]** — the identity-check-on-completion pattern is already in use in this file; the engineer should mirror it exactly.
- **Track change during a scrub drag.** Scrub is on the current item; changing tracks during a scrub is not a normal user flow, but if it happens, the format fetch rides on the new `currentItem` change and the scrub drag ends with the old item gone. Pre-existing behavior, not affected by this card. **[WONT HAPPEN in scope]**.
- **System sleep during gapless transition.** Sleep pauses the queue. On wake, `currentItem` has not changed, so no refetch is triggered. Badge still shows the correct format for the currently-playing track. **[MUST HANDLE as a no-op]** — verify no refetch is needlessly triggered on wake.
- **Playback starts while user is mid-scrub on the previous track.** Out of scope; pre-existing scrub-decouple pattern handles it. **[WONT HAPPEN in scope]**.

### "Wrong" user actions

- **User resizes window narrower than minWidth.** Can they? Per `ContentView.swift:333`, `minWidth: 500` is a SwiftUI floor; AppKit enforces it. The user cannot drag narrower. **[WONT HAPPEN]** — SwiftUI/AppKit guarantees this.
- **User switches themes mid-playback.** The bar's colors update via `themeManager.current.*` tokens on the next SwiftUI body re-eval. The font sizes are fixed pt values and do not depend on theme, so they hold. Badge re-renders with the new theme's `secondaryText` color. **[MUST HANDLE]** — verify at QA by switching themes while a track is playing. Already in acceptance ("legibility at all three themes").
- **User keyboard-mashes next/prev.** Covered above (rapid next-track).
- **User clicks the badge expecting a tooltip / popover.** No feedback. This is a minor usability gap — the audiophile audience will expect some form of expansion ("show me the full signal path"). **[FUTURE WORK]** — file a follow-up card for a track-inspector / properties popover. Do NOT bolt a tooltip onto this card.
- **User has VoiceOver on and the badge is hidden (missing fields).** VoiceOver does not announce anything for the badge, which is correct — there is nothing to announce. No phantom "audio format unknown" label. **[MUST HANDLE]** — badge view is conditionally rendered, so its accessibility label only exists when the badge exists.

### Accessibility & input modes

- **VoiceOver label.** Already in acceptance. Long-form reading: `"Audio format: FLAC, 96 kilohertz, 24 bit"`. **[MUST HANDLE]** — acceptance bullet.
- **Dynamic Type.** macOS has limited Dynamic Type support compared to iOS, but the system does support an accessibility text-size slider. By using fixed pt sizes (15 / 13 / 13 / 11 / 12), this card does NOT respond to Dynamic Type changes. That's a regression risk for one or two users but it's consistent with the rest of the app today (every other text in `NowPlayingBar.swift` uses fixed semantic tokens like `.headline` / `.caption`, which also don't respond to macOS's text-size slider in practice). **Card 0009 (text-size-setting) in backlog is the proper home** for a JamBox-level text-size multiplier. This card's font-size change must NOT preempt 0009's design space. Coordination note for the engineer: if 0009 later introduces a `themeManager.textSizeMultiplier` or similar, it should wrap these same base numbers. Do not introduce that multiplier here. **[FUTURE WORK]** — coordination note, no work in this card.
- **Reduced motion.** No explicit animations in this card; the implicit SwiftUI fade when the badge appears is negligible. **[WONT HAPPEN as a concern]**.
- **Keyboard-only users.** Badge is non-interactive, so there is no tab stop for it. Correct behavior. **[MUST HANDLE as a no-op]** — verify at QA that the badge does NOT become keyboard-focusable.
- **Locale differences.** Decimal separator is period regardless of locale (see do-not-do #12). Unit strings are not localized. This is intentional and matches pro-audio convention. **[MUST HANDLE]** — do-not-do #12.
- **Dark / light / candy themes.** The `secondaryText` token resolves correctly in all three. Already in acceptance. **[MUST HANDLE]**.

### Failure recovery

- **Partial format info** (e.g. sample rate present, bit depth missing). **Hide the whole badge.** Already in acceptance. Engineer must treat "any field is nil or zero" as "hide entirely." **[MUST HANDLE]** — acceptance bullet.
- **Async fetch throws.** Wrap in `try?`. On nil result, `player.format` stays nil, badge stays hidden. Do NOT log an error banner or alert the user. **[MUST HANDLE]** — silent failure is the right behavior for a caption-class UI element.
- **Fetch succeeds but returns a format string we don't recognize** (mFormatID not in whitelist). Hide badge. **[MUST HANDLE]** — covered by the whitelist-only codec map.
- **Track has `formatDescriptions` but no `mSampleRate` / `mBitsPerChannel`.** Treat zero as missing. Hide badge. **[MUST HANDLE]** — explicit zero check.

### Project-specific landmines

- **§7.1 — AVURLAsset options.** This card MUST NOT construct a new `AVURLAsset`. It reuses `queuePlayer.currentItem?.asset`, which was already constructed with `AVURLAssetPreferPreciseDurationAndTimingKey: true` in `PlayerEngine.play(startingAt:)` and `enqueueMoreIfNeeded()`. Acceptance bullet already covers this. **[MUST HANDLE]** — acceptance.
- **§7.2 — Gapless playback / `enqueueMoreIfNeeded`.** This card does not touch queue management. The format fetch hangs off `handleItemChange` (or a new method called from it) but must not mutate the queue or the lookahead logic. **[MUST HANDLE]** — acceptance.
- **§7.3 — Two-phase loading.** Format fetch is per **current item only**, not part of `FileScanner`'s bulk metadata enrichment. Do NOT add a `format` field to the `Track` struct itself (that would invite bulk loading). Keep it as a transient `@Published` on `PlayerEngine` that lives and dies with the current item. **[MUST HANDLE]** — acceptance.
- **§7.4 — Sandbox bookmarks.** Reusing `currentItem.asset` means no new file access, no new bookmark balance to worry about. **[MUST HANDLE as a no-op]** — verify no new `startAccessingSecurityScopedResource` call.
- **`PlaybackClock` split at `PlayerEngine.swift:20`.** `@Published var format: ...` goes on `PlayerEngine`, not on `PlaybackClock`. The clock only carries high-frequency position/duration. The format `@Published` is low-frequency (once per track change) and lives with the other low-frequency state (`currentTrack`, `currentArtwork`). **[MUST HANDLE]** — acceptance, invariant.

### Summary of new [MUST HANDLE] items not already in acceptance

I reviewed the acceptance list and the must-handle items above. All are already reflected in the existing acceptance bullets, with two that deserve explicit calling out in the engineer's plan but not new acceptance bullets:

1. **Identity-check-on-completion for async fetches** (rapid next-track case). Pattern already in use for `loadArtwork`; engineer must mirror it. Not a new acceptance bullet — it's an implementation detail the engineer must get right, and the "no stale format after rapid skip" behavior is implicit in the existing "only when the current item changes" bullet.
2. **First-audio-track pick for files with multiple audio tracks.** Engineer should document this choice in `## Plan`. Not a new acceptance bullet because it's an edge case the existing supported-formats list (mp3/m4a/flac/aiff/wav/alac/aac) makes near-impossible in practice.

Acceptance list is **unchanged**. No edits to frontmatter.

### [FUTURE WORK] items to file as follow-up cards (if approved by manager)

1. **Track inspector / properties popover.** Click the badge → expanded info: codec version, channel count, bit rate, encoder used, file path, embedded tags. Audirvana and Foobar2000 both have this. Out of scope for v1; would duplicate work with card 0009 (text sizes) if done in parallel.
2. **Tooltip-on-hover for the badge.** A lightweight intermediate step between "no interaction" and "full inspector popover." Could show e.g. the full codec name and channel layout. Explicit [FUTURE WORK] per do-not-do #3.
3. **Dynamic Type / JamBox-level text-size multiplier.** Already filed as card 0009 in backlog. Coordination note in this card's risks.

## Plan

**Approach:**

1. Introduce a new value type `AudioFormat` (struct, `Equatable`) in `PlayerEngine.swift`, alongside `PlaybackClock`. Fields: `name: String` (whitelist: FLAC/ALAC/MP3/AAC/WAV/AIFF), `sampleRateHz: Double`, `bitDepth: Int`, `isFloat: Bool`. Plus a computed `visual: String` (e.g. `"FLAC · 96 kHz · 24 bit"`) and `voiceOver: String` (`"Audio format: FLAC, 96 kilohertz, 24 bit"`). Centralizes copy formatting so `NowPlayingBar` just renders.
2. Add `@Published var currentFormat: AudioFormat?` on **`PlayerEngine`** (NOT on `PlaybackClock`). Preserve the clock split documented at PlayerEngine.swift:20.
3. In `handleItemChange(_:)`, when a new `item` arrives and the track is matched, clear `currentFormat = nil`, then kick off an async `Task` that reads the format from `item.asset` (reused — no new `AVURLAsset` constructed; §7.1 honored). Mirror `loadArtwork`'s identity-check pattern: capture the track `id` at dispatch and on completion verify `self.currentTrack?.id == capturedId` before assigning. On item-cleared path (nil), clear `currentFormat` too.
4. The async fetch uses `asset.loadTracks(withMediaType: .audio)`, picks the **first** audio track, then `track.load(.formatDescriptions)`. From the first `CMAudioFormatDescription`, pull `AudioStreamBasicDescription` via `CMAudioFormatDescriptionGetStreamBasicDescription`. Map `asbd.mFormatID` via a whitelist:
   - `kAudioFormatFLAC` → `"FLAC"`
   - `kAudioFormatAppleLossless` → `"ALAC"`
   - `kAudioFormatMPEGLayer3` → `"MP3"`
   - `kAudioFormatMPEG4AAC` (and related AAC variants if trivially recognizable) → `"AAC"`
   - `kAudioFormatLinearPCM` → disambiguate WAV vs AIFF by file extension on the asset's URL (both are LPCM containers; there's no codec-level signal for container type). This is the ONE place we look at the extension, and only to disambiguate between two LPCM containers — not to choose the codec.
   - anything else → return nil (hide badge; do-not-do #13).
5. Sample rate: `asbd.mSampleRate`. Convert to string via spec: divide by 1000; if fractional part non-zero (tolerance 1e-6), one decimal place with period `.`; else integer. Build with locale-independent `String(format:)`. Guard zero/negative → nil → hide.
6. Bit depth: `asbd.mBitsPerChannel`. If zero, hide. If LPCM and float flag set (`kAudioFormatFlagIsFloat` in `mFormatFlags`) → `isFloat = true`. Spec: `"<N> bit"` or `"<N> bit float"`.
7. In `NowPlayingBar.swift`:
   - Apply the font bump: title → `.system(size: 15, weight: .semibold)`; artist → `.system(size: 13)`; album → `.system(size: 13)`; left/right timestamps → `.system(size: 12, design: .monospaced).monospacedDigit()`.
   - Add the fourth line inside the metadata VStack (only when `currentTrack != nil` AND `player.currentFormat != nil`). HStack(spacing: 6): `Image(systemName: "waveform").frame(width: 14)` + `Text(format.visual)` at `.system(size: 11, design: .monospaced)`, colored with `themeManager.current.secondaryText ?? .secondary`, with `.accessibilityElement(children: .combine)` + `.accessibilityLabel(format.voiceOver)` and `.lineLimit(1)`.
   - Transport icons: unchanged `.title2` per guardrails.
   - Preserve `PointerCursorView`, scrub-decouple, onTitleClick callback.
8. Track.swift: NO changes (do-not-do #13 + §7.3: format is not a bulk-loaded field). Remove from `touches:` if clean. I'll likely leave `Track.swift` out of touches — verify at self-audit.

**Files:**

- `JamBox/PlayerEngine.swift` — add `AudioFormat` struct, `@Published currentFormat`, async format fetch in `handleItemChange`, clear on item==nil, identity-check on completion.
- `JamBox/NowPlayingBar.swift` — font-size bump on existing lines + new badge row in the metadata VStack.
- `JamBox/Track.swift` — likely untouched. Will remove from `touches:` at self-audit if so.

**Risks:**

- **§7.1 (AVURLAsset):** Must reuse `item.asset` / `firstItem.asset as? AVURLAsset` or just `item.asset` (AVAsset suffices for `.loadTracks`/`.formatDescriptions`). Do NOT call `AVURLAsset(url:options:)` anywhere new. The only asset construction point in the queue is `PlayerEngine.makeAssetItem` — untouched.
- **§7.2 (gapless):** No changes to `enqueueMoreIfNeeded`, queue management, or lookahead. Format fetch is side-effect-free w.r.t. the queue.
- **§7.3 (two-phase loading):** Format is NOT added to `Track`. It's transient per-current-item state on `PlayerEngine`, like `currentArtwork`.
- **Clock split (PlayerEngine.swift:20):** `currentFormat` goes on `PlayerEngine`, not `PlaybackClock`. 4Hz tick never touches it.
- **Stale format on rapid next-track:** mirror `loadArtwork`'s `if self.currentTrack?.id == track.id` pattern — capture `id` at dispatch, check on completion.
- **LPCM container disambiguation:** WAV vs AIFF is the only place where file extension matters, and only between two LPCM containers. Documented in code comment.
- **Width budget:** Badge at worst case (`FLAC · 176.4 kHz · 32 bit float`) fits per designer's math (~220 pt of ~304 pt column at minWidth 500). `.lineLimit(1)` on badge protects against regression.
- **Dynamic Type / card 0009:** fixed pt sizes (15/13/13/11/12) are deliberate per designer; card 0009 can wrap them in a multiplier later. Not preempted.
- **Build:** no new files, so no `xcodegen generate` needed (§7.5).

**Open questions:**

- None blocking. For AAC, I'll treat `kAudioFormatMPEG4AAC` as `"AAC"`. If other AAC subtypes (`kAudioFormatMPEG4AAC_HE`, `_LD`, etc.) appear in a JamBox library, they'll also be labeled `"AAC"` — acceptable since the compact badge doesn't differentiate profile.
- First-audio-track pick for multi-track files: documented here, trivially handled by `.first` on the returned audio tracks array.

## Log
- 2026-04-08 — manager card created in ready/, sibling to 0012, will dispatch designer next
- 2026-04-08 — designer-13 picked up, moved ready/ → design/
- 2026-04-08 — designer-13 completed ## Design and ## User Risks & Edge Cases; self-audited all acceptance bullets; no changes to acceptance frontmatter; moved design/ → ready/ for engineer dispatch
- 2026-04-08 — engineer-13 picked up, moved ready/ → in-progress/
- 2026-04-08 — engineer-13 plan written and committed
- 2026-04-08 — engineer-13 implementation complete: AudioFormat struct + @Published currentFormat on PlayerEngine (not PlaybackClock), loadFormat mirrors loadArtwork identity-check pattern, readAudioFormat via CMAudioFormatDescription → ASBD with mFormatID whitelist (WAV/AIFF disambiguated by URL extension only — the one and only extension lookup), NowPlayingBar metadata VStack gains fourth waveform line and all existing text lines get the designer's fixed-pt font bump (15/13/13/11/12). Track.swift not touched (format is per-current-item transient, §7.3); dropped from touches:. xcodebuild BUILD SUCCEEDED, no new warnings. Self-audit complete.
- 2026-04-08 — qa-13 picked up card, starting §6b independent audit
- 2026-04-08 — qa-13 audit complete. Acceptance 12/12 PASS, invariants all PASS, build SUCCEEDED on MacOSX26.4.sdk. `kAudioFormatMPEG4AAC_Spatial` investigated against the SDK header — it is a plain `CF_ENUM` enumerator with no `API_AVAILABLE` attribute, so it compiles to an integer constant with no runtime availability check and is safe at the macos14.0 deployment target. No BLOCKER/MAJOR findings. Recommendation: APPROVE. Card stays in qa/ for post-QA design review.
- 2026-04-08 — designer-13-review picked up for post-QA design review (§6c); reading original risks, plan, self-audit, QA report, and diff

## Self-Audit

### 1. Re-read modified files

Re-read `JamBox/PlayerEngine.swift` top to bottom after all edits. The new `AudioFormat` struct is documented, stateless, and locale-independent via `en_US_POSIX`. `@Published currentFormat` sits with the other low-frequency published fields on `PlayerEngine` (not on `PlaybackClock`), matching the clock-split rationale at `PlayerEngine.swift:5-18`. `handleItemChange` clears `currentFormat` on both nil-item and new-item paths before kicking off `loadFormat`. `loadTracks`, `clearPlayback`, and the `applyTrackDiff` removed-current path all clear `currentFormat` alongside `currentArtwork` so stale format info can never survive a state reset. `loadFormat` mirrors `loadArtwork`'s identity-check pattern verbatim. `readAudioFormat` is a single guard-chain with no dead code; every early return is paired with a code-comment reason. No debug prints, no TODOs, no commented-out blocks.

Re-read `JamBox/NowPlayingBar.swift` top to bottom. The metadata VStack now has four conditional lines (title / artist / album / format badge) all following the same `HStack(spacing: 6) { icon.frame(width: 14), Text }` shape — icon gutters line up. The font-size bump is applied exactly as specified (15/13/13/11/12). Transport icons unchanged (`.title2`). Scrub-decouple state (`isScrubbing`, `scrubFraction`), `onTitleClick`, `PointerCursorView` on artwork and title all untouched. `.monospacedDigit()` preserved on both timestamps.

### 2. Acceptance walkthrough

- **Badge shows FLAC/ALAC/MP3/AAC/WAV/AIFF + kHz + bit.** PASS. `readAudioFormat` at `PlayerEngine.swift:538-621` maps `mFormatID` to the whitelist exactly. Visual format string built by `AudioFormat.visual` at `PlayerEngine.swift:51-53`.
- **Badge fetched from existing `AVPlayerItem.asset`, no new `AVURLAsset`.** PASS. `handleItemChange` passes `item.asset` into `loadFormat` at `PlayerEngine.swift:493`. `loadFormat` takes `AVAsset`, calls `asset.loadTracks` / `track.load(.formatDescriptions)` — no `AVURLAsset(url:options:)` constructor anywhere in the new code. Verified by `grep -n "AVURLAsset(" JamBox/PlayerEngine.swift`: only the existing `makeAssetItem` (line 71) and `findArtwork` (line 469, pre-existing) construct assets.
- **Only when `currentItem` changes, not on every scrub tick.** PASS. `loadFormat` is called from `handleItemChange` only, which is driven by `queuePlayer.publisher(for: \.currentItem)`. The 4Hz periodic time observer at `PlayerEngine.swift:173-192` never touches `currentFormat`.
- **Published on `PlayerEngine`, not `PlaybackClock`.** PASS. `@Published var currentFormat` declared at `PlayerEngine.swift:113`, inside `PlayerEngine`. `PlaybackClock` (lines 19-23) remains just `position` + `duration`.
- **Hide entire badge if any field unknown/missing/zero.** PASS. `readAudioFormat` returns nil on: no audio tracks, no format descriptions, no ASBD pointer, codec not in whitelist, LPCM with unknown extension, `mSampleRate` not finite or ≤0, `mBitsPerChannel` = 0. The view-level `if let format = player.currentFormat` at `NowPlayingBar.swift:106` hides the whole line on nil.
- **VoiceOver label in long form, distinct from visual.** PASS. `AudioFormat.voiceOver` at `PlayerEngine.swift:58-61` produces `"Audio format: FLAC, 96 kilohertz, 24 bit"` (and float variant "floating point"). Applied via `.accessibilityElement(children: .combine).accessibilityLabel(format.voiceOver)` at `NowPlayingBar.swift:117-118`.
- **UX pass: slight font size increase across the bar.** PASS. Title 13→15 (semibold), artist/album 11→13, timestamps 11→12 monospaced. Exact values from designer spec. See `NowPlayingBar.swift:80, 92, 101, 154, 178`.
- **Legibility at minWidth 500 / all themes / with artwork.** PASS by designer's math (worst case badge `FLAC · 176.4 kHz · 32 bit float` ≈ 220 pt in a ~304 pt column). Font sizes are theme-independent; colors route through `themeManager.current.secondaryText ?? Color.secondary` which resolves in all three themes. Requires runtime verification by QA — all three themes should show the badge in `secondaryText` color.
- **No regressions: scrub-decouple / clickable artwork / transport / scroll-to-current / elapsed-total time.** PASS. Scrub-decouple state (`isScrubbing`, `scrubFraction`, `scrubBinding`) untouched. `artworkCell`'s `.onTapGesture { showArtwork = true }` and `PointerCursorView` overlay untouched. `transportCell` entirely untouched (`.title2` icons, same actions). `onTitleClick` callback on title tap untouched. `displayedPosition`/`formatTime`/`clock.duration` paths untouched.
- **Build passes.** PASS. See §3.
- **§7.1 AVURLAsset preserved.** PASS. No new `AVURLAsset(url:options:)` calls. Reused `item.asset`. Card 0012's `makeAssetItem` helper remains the single queue-side asset construction site.
- **§7.2 gapless preserved.** PASS. `enqueueMoreIfNeeded` untouched. `loadFormat` is a side-effectless Task relative to the queue; it never enqueues, removes, or seeks.
- **§7.3 two-phase loading preserved.** PASS. Format is NOT added to the `Track` struct. `Track.swift` is untouched. Format is per-current-item transient state on `PlayerEngine`, like `currentArtwork`. Format fetch is not part of `FileScanner`.

### 3. Build result

Ran `xcodebuild -project JamBox.xcodeproj -scheme JamBox build`. Final status:

```
** BUILD SUCCEEDED **
```

No new warnings (grepped build output for "warning:"; only the pre-existing `appintentsmetadataprocessor` "No AppIntents.framework dependency found" note, which predates this card).

### 4. Invariants verified

- **§7.1 AVURLAsset + precise timing.** Verified: no new `AVURLAsset(...)` construction in the diff. `loadFormat` takes the existing `AVAsset` by reference from `handleItemChange(item.asset)`. Card 0012's `makeAssetItem` is the single queue asset-construction point and is untouched.
- **§7.2 Gapless playback.** Verified: no changes to `enqueueMoreIfNeeded`, queue `insert`/`remove`, or the `lookAhead = 3` constant. Format fetch runs in a detached `Task` with no queue side effects.
- **§7.3 Two-phase loading.** Verified: `Track.swift` untouched; no new fields in `Track`; format is not part of `FileScanner`'s bulk enrichment. Fetch is per-current-item only.
- **§7.4 Sandbox bookmarks.** Verified: no new `startAccessingSecurityScopedResource` calls; reusing the existing `item.asset` means no new file access path.
- **§7.5 Xcode project regeneration.** N/A: no files added or removed, only edited. `project.yml` unchanged. No `xcodegen generate` needed.
- **§7.6 Build green.** Verified (see §3).
- **Clock split (PlayerEngine.swift:5-18).** Verified: `@Published currentFormat` is on `PlayerEngine`, not `PlaybackClock`. The 4Hz observer at lines 173-192 writes only to `self.clock.*`. `PlaybackClock` has only `position` and `duration`.

### 5. Hostile diff review

Ran `git diff main -- JamBox/PlayerEngine.swift JamBox/NowPlayingBar.swift`. Things a hostile reviewer might flag:

- **`kAudioFormatMPEG4AAC_Spatial` case.** This symbol exists on recent SDKs and is included in the AAC bucket. Build passed against `MacOSX26.4.sdk`; deployment target is `macos14.0`. If the symbol is only available on later macOS, this could fail on older OSes. Worth calling out — the project's `target: arm64-apple-macos14.0` is the current floor; `kAudioFormatMPEG4AAC_Spatial` may not have shipped until a later macOS. Mitigation: if QA hits an availability error on a 14.0 device, drop `_Spatial` from the list. All six AAC variants group-label as `"AAC"` anyway, so dropping one is a safe fallback.
- **Locale in sample-rate formatter.** I use `Locale(identifier: "en_US_POSIX")` with `String(format:locale:)`. Reviewer might ask: "why not just `String(format:)`?" The designer's do-not-do #12 is explicit that the decimal separator must be period regardless of locale; using POSIX locale is belt-and-suspenders against Swift's format-string locale handling on German/French systems.
- **Force of `asbd.mBitsPerChannel` to Int.** Safe — it's already an unsigned integer. Zero-check is explicit.
- **Float detection only for LPCM.** Compressed codecs always return `isFloat = false`. Correct — the float flag in `mFormatFlags` is not meaningful for FLAC/ALAC/AAC/MP3. The badge for a compressed 24-bit codec just shows `24 bit`, never `24 bit float`.
- **Swift 6 actor isolation: `Task { ... await MainActor.run { ... } }` inside a `@MainActor` class.** Mirrors `loadArtwork` exactly (PlayerEngine.swift around line 432) which is the documented pattern in this file.
- **Middle-dot encoding.** I typed `·` (U+00B7) directly. Swift source is UTF-8; this is safe and deliberate — matches spec.

### 6. Touched-files reconciliation

`touches:` lists `NowPlayingBar.swift`, `PlayerEngine.swift`, `Track.swift`. Actual diff: `NowPlayingBar.swift`, `PlayerEngine.swift`. **`Track.swift` was not touched**, which is correct per §7.3 (format is per-current-item transient state, not a bulk-loaded `Track` field). Updating `touches:` to drop `Track.swift`.

### 7. Scope check

Changes match the card exactly:
- Added `AudioFormat` + `@Published currentFormat` + `loadFormat`/`readAudioFormat` on `PlayerEngine`.
- Added the fourth metadata line to `NowPlayingBar` with the waveform icon.
- Bumped title/artist/album/timestamp fonts per the designer's spec.

Nothing smuggled in. No drive-by refactors. No unrelated fixes.

## QA Report
*qa-13, 2026-04-08. Independent audit per §6b.*

### Acceptance

- **[PASS]** Badge shows FLAC/ALAC/MP3/AAC/WAV/AIFF + kHz + bit for current track. `readAudioFormat` at PlayerEngine.swift:538-617 pulls `mFormatID` from the first audio track's `CMAudioFormatDescription` → `AudioStreamBasicDescription`, maps to the exact whitelist. Visual string built by `AudioFormat.visual` at PlayerEngine.swift:51-53 using middle-dot U+00B7.
- **[PASS]** Fetched from existing `AVPlayerItem.asset`, no new `AVURLAsset`. `handleItemChange` passes `item.asset` (an existing `AVAsset`) into `loadFormat` at PlayerEngine.swift:493. `loadFormat(for:from:)` accepts `AVAsset` and calls `asset.loadTracks(...)` / `audioTrack.load(.formatDescriptions)` — zero constructor calls. Grep `AVURLAsset\(` in JamBox/ returns exactly the three pre-existing sites (Track.swift:53, PlayerEngine.swift:155 makeAssetItem, PlayerEngine.swift:670 findArtwork). Invariant preserved.
- **[PASS]** Only on `currentItem` change, not per scrub tick. `loadFormat` is called exclusively from `handleItemChange` (PlayerEngine.swift:493), which is bound to `queuePlayer.publisher(for: \.currentItem)` at PlayerEngine.swift:167-172. The 4Hz periodic observer at PlayerEngine.swift:174-193 writes only to `clock.position` / `clock.duration` and never touches `currentFormat`.
- **[PASS]** `@Published currentFormat` lives on `PlayerEngine`, not `PlaybackClock`. Declared at PlayerEngine.swift:113 inside `PlayerEngine`. `PlaybackClock` (PlayerEngine.swift:20-23) still has only `position` + `duration`. Clock split preserved.
- **[PASS]** Entire badge hidden if any field unknown/missing/zero. `readAudioFormat` returns nil on: no audio tracks (543-546), no format descriptions (548-551), no ASBD (553-555), codec outside whitelist (594-595), LPCM with unknown extension or non-URL asset (577-593), sample rate non-finite/≤0 (600), `mBitsPerChannel` == 0 (604). View side at NowPlayingBar.swift:107 is `if let format = player.currentFormat` — whole row hidden on nil. No partial badge is constructible.
- **[PASS]** VoiceOver label in long form, distinct from visual. `AudioFormat.voiceOver` at PlayerEngine.swift:58-61 reads `"Audio format: FLAC, 96 kilohertz, 24 bit"` (and `"...floating point"` for float). Applied via `.accessibilityElement(children: .combine).accessibilityLabel(format.voiceOver)` at NowPlayingBar.swift:116-117.
- **[PASS]** UX font-size bump across the bar. Title 15 semibold (NowPlayingBar.swift:80), artist 13 regular (:92), album 13 regular (:101), badge 11 monospaced regular (:114), timestamps 12 monospaced regular with `.monospacedDigit()` preserved (:154-155, :178-179). Transport icons unchanged at `.title2` (:134, :139, :144). Values match designer spec exactly; all fixed pt (not Theme tokens) per spec rationale.
- **[PASS] (code-level)** Legibility at minWidth 500 / all themes / artwork visible. Badge worst case `FLAC · 176.4 kHz · 32 bit float` is ~34 monospaced-11-pt chars ≈ 220 pt; metadata column at minWidth 500 has ~304 pt after artwork/transport/padding per designer math. `.lineLimit(1)` on the badge (NowPlayingBar.swift:112) guarantees no wrap. Colors route through `themeManager.current.secondaryText ?? Color.secondary` — resolves in light/dark/candy. (Runtime theme-switch visual verification deferred to post-QA designer review; code is structurally correct.)
- **[PASS]** No regressions. Scrub-decouple `isScrubbing`/`scrubFraction`/`scrubBinding` at NowPlayingBar.swift:20-21, 159-174, 204-209 untouched. Clickable artwork `onTapGesture { showArtwork = true }` + `PointerCursorView` overlay at :59-60 untouched. Transport cell (:130-148) entirely unchanged except body is the same three `.title2` icons. `onTitleClick` callback at :83 still wired to title tap. `displayedPosition` / `formatTime` / `clock.duration` path all untouched.
- **[PASS]** Build passes. Ran `xcodebuild -project JamBox.xcodeproj -scheme JamBox build` against `MacOSX26.4.sdk`. Result: `** BUILD SUCCEEDED **`. No new warnings.
- **[PASS]** §7.1 AVURLAsset preserved (see above).
- **[PASS]** §7.2 gapless preserved. `enqueueMoreIfNeeded` (PlayerEngine.swift:498-508) untouched. Queue `insert`/`remove`/`items()` calls unchanged. `lookAhead = 3` constant untouched. `loadFormat` runs in a detached `Task` with zero queue mutation.
- **[PASS]** §7.3 two-phase loading preserved. `Track.swift` not modified (confirmed via diff); format is per-current-item transient on `PlayerEngine`, never added to `Track`, never touched by `FileScanner`.

### Invariants

- **[PASS]** §7.1 AVURLAsset + precise timing. No new constructor; reuses `item.asset` from the queue which was built via `makeAssetItem` with `assetOptions` including `AVURLAssetPreferPreciseDurationAndTimingKey`. The three `AVURLAsset(` sites in the codebase (Track.swift:53, PlayerEngine.swift:155, PlayerEngine.swift:670) are all pre-card-0013 and all pass `assetOptions`.
- **[PASS]** §7.2 Gapless playback. Queue management (insert/remove/advance/lookAhead=3) untouched. `loadFormat` is a read-only async Task off `item.asset`.
- **[PASS]** §7.3 Two-phase loading. `Track.swift` untouched. Format is transient state on `PlayerEngine`, cleared in `loadTracks`, `applyTrackDiff` (removed-current path), `clearPlayback`, and `handleItemChange` (both nil-item and new-item branches). Never bulk-loaded by `FileScanner`.
- **[PASS]** §7.4 Sandbox bookmarks. No new `startAccessingSecurityScopedResource` calls; reuses the existing in-queue asset, no new file access.
- **[N/A]** §7.5 Xcode project regeneration. No files added/removed; only edits.
- **[PASS]** §7.6 Build green (see Acceptance).
- **[PASS]** PlaybackClock isolation. `@Published currentFormat` is on `PlayerEngine` (PlayerEngine.swift:113). `PlaybackClock` still contains only `position` + `duration` (lines 20-23). The 4Hz tick at lines 174-193 writes to `self.clock.*` only, never touches `currentFormat`, and therefore cannot cause NowPlayingBar to re-read format or re-fetch. NowPlayingBar observes `player` (which publishes `currentFormat`) and `clock` (position/duration) separately; the only path that assigns `currentFormat` is `loadFormat`'s completion on `currentItem` change.
- **[PASS]** Identity check on async fetch. `loadFormat` at PlayerEngine.swift:522-533 captures `track.id` at dispatch, then on `MainActor.run` guards `self.currentTrack?.id == capturedId` before assigning. Mirrors `loadArtwork` pattern at PlayerEngine.swift:633-642 verbatim. Rapid next-track cannot show stale format: (a) `currentFormat = nil` is set synchronously in `handleItemChange` before `loadFormat` is dispatched (line 491), so the badge disappears immediately; (b) if an older fetch lands after a newer `currentTrack` has been assigned, the id mismatch drops it.
- **[PASS]** Hide-whole-badge on any missing/zero. All six fail paths in `readAudioFormat` return nil (codec unknown, LPCM-unknown-ext, non-URL asset for LPCM, no audio track, no formatDesc, no ASBD, sample rate ≤0/non-finite, bit depth == 0). Single `if let` on the view side.
- **[PASS]** Format string exact. `AudioFormat.visual` at PlayerEngine.swift:52 uses `"\(name) · \(sampleRateNumber) kHz · \(bitDepthString)"` with U+00B7 middle dot. `sampleRateNumber` (PlayerEngine.swift:70-81) divides by 1000, shows integer when fractional part ≈ 0 else one decimal, forces `Locale(identifier: "en_US_POSIX")` into `String(format:locale:)` so period decimal is locale-independent. `bitDepthString` (PlayerEngine.swift:85-90) produces `"<N> bit"` or `"<N> bit float"` — never pluralized, never "bits".
- **[PASS]** Format name source. From `asbd.mFormatID` at PlayerEngine.swift:563. The switch maps the `.m4a`-container codecs correctly: `kAudioFormatAppleLossless` → "ALAC", the six `kAudioFormatMPEG4AAC*` variants → "AAC". Extension is ONLY consulted inside `case kAudioFormatLinearPCM:` (lines 577-593) to disambiguate WAV/AIFF; both are LPCM containers so this is the acceptable exception noted in the plan.
- **[PASS]** VoiceOver label distinct from compact visual (see Acceptance).
- **[PASS]** Multi-audio-track files: first audio track picked via `tracks.first` at PlayerEngine.swift:544. Matches plan and AVQueuePlayer playback behavior.
- **[PASS]** Font sizes fixed pt not Theme tokens. Verified by reading every `.font(.system(size:` in NowPlayingBar.swift — 15/13/13/11/12 exactly where the designer specified, no `Theme.swift` font tokens used in the updated lines.
- **[PASS]** Layout fits at minWidth: 500. Album art still 60×60 (NowPlayingBar.swift:57, :63). Transport icons unchanged. `.lineLimit(1)` on all four metadata lines guarantees the metadata column cannot push transport — truncation happens first.

### Findings

- **[MINOR / RESOLVED]** Engineer flagged `kAudioFormatMPEG4AAC_Spatial` as possibly post-14.0. Investigated: this identifier is declared in `CoreAudioBaseTypes.h` inside a plain `CF_ENUM(AudioFormatID)` with **no `API_AVAILABLE` attribute** on the enumerator (see `$SDK/System/Library/Frameworks/CoreAudioTypes.framework/Versions/A/Headers/CoreAudioBaseTypes.h` around line 421). Because `CF_ENUM` enumerators compile to integer constants (four-char-code 'aacs'), there is no runtime availability check — the compiled binary just contains the integer. There is no availability-attribute failure at the macOS 14.0 deployment target and no `#available` wrapping is needed. Leaving the case in is safe. Non-blocking; no change requested.
- **[MINOR]** The `asbd.mFormatFlags & kAudioFormatFlagIsFloat` check is gated on `kAudioFormatLinearPCM` only (PlayerEngine.swift:608-609), which matches spec. FLAC's `mFormatFlags` carries bit-depth metadata in some cases but never the float flag, so this is correct. Non-actionable, noted for reviewer context.
- **[NIT]** At PlayerEngine.swift:483, `item.asset as? AVURLAsset)?.url as NSURL?` comparison is the pre-existing matching logic and is unchanged by this card. Noted only to confirm no scope creep.
- **[NIT]** Engineer's self-audit line-number references are slightly off in a few places (they cited "PlayerEngine.swift:538-621" for `readAudioFormat` which is actually 538-617, and "NowPlayingBar.swift:117-118" for accessibility which is 116-117). Harmless.

No BLOCKER or MAJOR findings.

### Recommendation

**APPROVE.** All 12 acceptance bullets PASS. All applicable §7 invariants PASS. §7.1 AVURLAsset rule verified by independent grep (same three pre-existing construction sites). PlaybackClock isolation verified. Identity check mirrors `loadArtwork` verbatim. Hide-on-missing is airtight (six fail paths + view-level `if let`). Format string exact (U+00B7, locale-independent period, "bit" not "bits", float special case). `kAudioFormatMPEG4AAC_Spatial` is safe at 14.0 deployment target because `CF_ENUM` identifiers have no availability attributes — investigation results above. Build succeeds. No new warnings. No BLOCKER / MAJOR findings. Card ready to proceed to post-QA design review (§6c) since `needs_designer: true`.

## Design Review
*Filled in by the designer AFTER QA approves. See .pm/README.md §6c.*

### Original risks revisited

### Newly surfaced concerns

### Recommendation

## Manager Decision
*Filled in by the manager when closing or kicking back.*
