---
id: 0018
title: Display channel count in format badge or inspector
created: 2026-04-08
needs_designer: true
designer: null
design_review: null
engineer: null
qa: null
parent: 0013
priority: P3
estimate: S
depends_on: []
touches:
  - JamBox/PlayerEngine.swift
  - JamBox/NowPlayingBar.swift
acceptance:
  - Channel count for the currently-playing track is exposed somewhere in the NowPlayingBar (badge, inspector popover, or accessibility-only).
  - Common channel layouts displayed sensibly: mono, stereo, 5.1, 7.1.
  - Localization story for channel-count strings is decided (English-only is acceptable for v1).
  - Hide if channel count is unknown or zero.
  - build passes
---

## Context

Filed by manager-inline §6c review of card 0013. The format badge currently shows codec + sample rate + bit depth, but not channel count. A 5.1 surround mix and a stereo mix render identically. Designer deliberately deferred this to keep the badge from getting crowded. May be a good fit for a future track inspector popover (separate card) rather than the badge itself.
