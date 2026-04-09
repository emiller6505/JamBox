---
id: 0019
title: Decide whether to show a degraded format badge for lossy codecs (MP3, AAC)
created: 2026-04-08
needs_designer: true
designer: null
design_review: null
engineer: null
qa: null
parent: 0013
priority: P2
estimate: S
depends_on: []
touches:
  - JamBox/PlayerEngine.swift
  - JamBox/NowPlayingBar.swift
acceptance:
  - Decision recorded (in card or in `## Design`) on whether MP3 and AAC files should display a degraded format badge or remain hidden.
  - If "show degraded badge": MP3/AAC tracks display something like `"MP3 · 44.1 kHz"` or `"MP3 · 320 kbps"` (designer's call), without bit depth. Hide-on-missing rules still apply for the fields that DO render.
  - If "keep hidden": this card closes with a documented rationale and no code change.
  - If "show degraded badge" path is chosen, the bit-depth zero-check in `readAudioFormat` must be relaxed for lossy codecs only — lossless codecs still hide the whole badge if bit depth is zero.
  - Either way, the behavior is consistent across MP3 and AAC.
  - build passes (only if code changes)
---

## Context

Filed by manager-inline §6c review of card 0013 (format badge). The card 0013 implementation correctly hides the badge for any track where bit depth is zero — which is the case for nearly every MP3 and AAC file, since lossy codecs don't have a meaningful bit depth.

The result: users with FLAC libraries see a beautiful audiophile-reassurance badge. Users with MP3 libraries see no badge ever. The reassurance feature delivers nothing to the lossy-format audience.

This is a design philosophy question that deserves manager + designer alignment, NOT a kickback to engineering. Two paths:

1. **Show a degraded badge for lossy formats** — `"MP3 · 44.1 kHz"` or `"MP3 · 320 kbps"`. The badge is honest about format and rate, omits the meaningless bit-depth field. Lossy users get reassurance that the file is what they think it is.

2. **Accept the current silence** — the badge is "lossless reassurance" by design, and showing nothing for MP3 is itself a signal ("this isn't lossless"). The audiophile user knows immediately. The downside: most users will not parse "no badge" as "this is lossy" — they'll parse it as "the badge feature is broken."

P2 because the user impact is real but the feature still works as specified for the audiophile audience.
