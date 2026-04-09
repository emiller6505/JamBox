---
id: 0016
title: Reconcile saved resume track by name or content hash when URL is gone
created: 2026-04-08
needs_designer: true
designer: null
design_review: null
engineer: null
qa: null
parent: 0012
priority: P3
estimate: M
depends_on: []
touches:
  - JamBox/AppModel.swift
acceptance:
  - If the saved resume track's URL no longer resolves (file moved or renamed), JamBox attempts to find the same track inside the currently-loaded folder by a stable identity (filename match and/or content hash). If found, the resume flow proceeds against the found track; if not, silently clear as today.
  - The reconciliation strategy is documented in the card's ## Design section and matches the project's quiet-UX tone — no modals, no banners, no "Did you mean…?" prompts.
  - False-positive protection: if the reconciliation finds a track that is plausibly but not certainly the same (e.g. same filename, different content), the safer default is silent clear rather than resume-at-wrong-spot.
  - build passes: xcodebuild -project JamBox.xcodeproj -scheme JamBox build
---

## Context

Spawned by the §6c design review of card 0012. The designer doc for 0012 explicitly deferred this: *"we intentionally do NOT try to find the file by name in the folder; that's a future feature ('track identity by content hash')."* This is that future card. Parked in backlog because it's not urgent — the current silent-clear behavior is defensible and matches what most mainstream players do. Promote to ready only if user feedback indicates that lost resume state from file moves is a real pain point.

Design work to do on this card: study how iTunes / Apple Music / Audirvana / Foobar2000 handle library reconciliation after the user reorganizes their folder. Decide between (a) filename-only match, (b) content hash (expensive to compute at scan time), (c) a hybrid (filename match confirmed by a small content fingerprint). Consider the performance cost at load time — we currently do a fast filesystem scan and async metadata enrichment; adding a hash pass would need to be opt-in or lazy.

## Design

## User Risks & Edge Cases

## Plan

## Log
- 2026-04-08 — filed by designer-12-review as a future-work child card of 0012

## Self-Audit

## QA Report

## Design Review

## Manager Decision
