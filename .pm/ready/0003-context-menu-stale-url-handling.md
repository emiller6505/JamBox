---
id: 0003
title: Handle stale or unreachable track URLs in row context menu
created: 2026-04-06
engineer: null
qa: null
parent: 0001
priority: P3
estimate: S
depends_on: []
touches:
  - JamBox/ContentView.swift
acceptance:
  - "Show in Finder" on a track whose underlying file no longer exists (deleted, ejected drive, disconnected network volume) does not crash and gives the user some feedback (e.g. NSAlert, beep, or disabled menu item) instead of silently no-opping.
  - "Play" on a stale or unreachable URL does not crash the player and either skips the track gracefully or surfaces an error to the user.
  - Behavior is consistent for non-local URLs (e.g. network volumes, smb://) — at minimum, no crash; ideally a graceful "file not available" path.
  - No regression to the happy path verified in card 0001 (right-click → Play / Show in Finder on a present, local file still works identically).
  - Build passes cleanly: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - AVURLAssetPreferPreciseDurationAndTimingKey invariant still holds on any AVURLAsset construction touched.
  - Gapless playback unchanged.
---

## Context

Spawned from the QA audit of card 0001 (right-click context menu on song
rows). The v1 implementation in 0001 happily hands `track.url` to
`NSWorkspace.shared.activateFileViewerSelecting` and `player.play(startingAt:)`
without checking whether the underlying file is still present and reachable.

For a music app whose library follows external folders (often on USB drives,
NAS shares, or other removable/network volumes), this is a realistic failure
mode: the user scans a folder, ejects the drive, and then right-clicks a row.
Today this silently no-ops for "Show in Finder" and would feed a dead URL to
`AVQueuePlayer` for "Play".

This is intentionally a P3 because the v1 card explicitly did not require
handling it, and the failure mode is non-destructive (no crash observed
statically — but runtime behavior with a dead URL in the queue player has
not been verified).

QA findings reference:
- [MINOR] Stale or invalid `track.url` not handled.
- [NIT] Non-local / disconnected-volume URLs not specifically considered.

## Plan
*Filled in by the engineer during plan mode.*

## Log
- 2026-04-06 — qa-01 created child card from 0001 audit findings

## Self-Audit
*Filled in by the engineer before handing off to QA.*

## QA Report
*Filled in by the QA agent.*

## Manager Decision
*Filled in by the manager when closing or kicking back.*
