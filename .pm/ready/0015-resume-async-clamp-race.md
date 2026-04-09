---
id: 0015
title: Guard async duration-clamp in resume against mid-playback yank
created: 2026-04-08
needs_designer: true
designer: null
design_review: null
engineer: null
qa: null
parent: 0012
priority: P3
estimate: S
depends_on: []
touches:
  - JamBox/PlayerEngine.swift
acceptance:
  - `PlayerEngine.resume(...)`'s async duration-load Task does NOT re-seek or tear down playback if the user has already moved on. Specifically, the Task must verify — in addition to the existing `currentTrack?.url == savedURL` check — that `clock.position` is still approximately equal to the original seeded `sanitized` value (within e.g. 1.0s tolerance) before issuing a clamp re-seek. If the user seeked, pressed play and advanced, or otherwise moved the position, the Task abandons its re-seek.
  - The async `clearPlayback()` failure path (triggered when the asset reports non-finite / ≤0 duration) must NOT tear down currentTrack if `queuePlayer.timeControlStatus == .playing`. If playback is actively running, the duration must have been valid enough for AVFoundation to start it; trust the live state and abandon the teardown silently.
  - Scenario test (manual or unit): saved state is (Track A, position 90s) where Track A's actual duration is 60s. User launches, sees Track A paused at 0:45/0:00 or similar, immediately double-clicks Track A in the table (fresh play from 0). Expected: track plays from 0:00 uninterrupted. Regression would be: track jumps to 0:60 / end-of-track after the async Task resolves.
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
  - §7.1 AVURLAsset preserved
  - §7.2 Gapless playback preserved
---

## Context

Spawned by the §6c design review of card 0012 (resume playback position on launch). The current `PlayerEngine.resume` implementation spawns an async Task to load the asset's real duration and, if the saved position overshoots, clamps and re-seeks. The Task guards with `currentTrack?.url == savedURL` — which catches "user clicked a different track" — but NOT "user clicked the SAME track to play it fresh." In that case the URL identity still matches, and the Task will issue a re-seek to the clamped value, yanking the user from 0:00 to near the end of the track.

Probability is low (requires saved position to already exceed real duration, which itself is uncommon — it only happens when the file was re-encoded shorter between sessions — AND requires the user to fast-double-click the resumed track before the duration load finishes). But the failure mode is a playback integrity violation: "I pressed play and the audio jumped." Card 0012's whole thesis is "JamBox respects my time," so this deserves a fix.

Secondary concern in the same window: if the async Task's duration load returns non-finite (an AVFoundation API oddity, extremely rare since playback usually requires valid duration), `clearPlayback()` is called which rips `currentTrack` and the queue away. If the user has already pressed play by that moment, they lose their audio silently. Guard with `timeControlStatus != .playing`.

## Design
*Fill in: no visual change. This is a guard-clause tightening in the resume async Task.*

## User Risks & Edge Cases
*Fill in. Key scenarios to walk: user doesn't touch the app (happy path, clamp still runs); user double-clicks the same track (new scenario, must not yank); user double-clicks a different track (existing guard catches it); user scrubs before the Task finishes (position moved, new guard catches it); user presses play and lets it play for 1s before the Task resolves (position moved forward by 1s, new guard catches it).*

## Plan
*Fill in during engineer plan mode.*

## Log
- 2026-04-08 — filed by designer-12-review as a child card of 0012 during post-QA design review

## Self-Audit

## QA Report

## Design Review

## Manager Decision
