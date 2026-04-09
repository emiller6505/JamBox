---
id: 0017
title: Extend format badge whitelist to µ-law / a-law codecs
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
acceptance:
  - The format badge whitelist in `readAudioFormat` (PlayerEngine.swift) is extended to recognize `kAudioFormatULaw` and `kAudioFormatALaw`, displaying as `"µ-law"` and `"a-law"` respectively (or designer-decided strings).
  - Files using these codecs that previously hid the badge entirely now show a meaningful badge.
  - `bitDepth` for µ-law/a-law is conventionally 8 bits — verify what AVFoundation reports and pick a sensible display.
  - All hide-on-missing rules from card 0013 still apply.
  - build passes
---

## Context

Filed by manager-inline §6c review of card 0013 (format badge). µ-law and a-law are rare codecs (mostly old phone recordings or .au files) but exist in the wild. The card 0013 implementation correctly hides the badge for unrecognized codecs, which means a user with a folder of these files sees no badge for any of them. This is a P3 nice-to-have — file only if a user reports it.
