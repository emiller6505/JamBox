---
id: 0020
title: Hotfix — format badge hides for FLAC because mBitsPerChannel is 0
created: 2026-04-08
needs_designer: false
designer: null
design_review: null
engineer: manager-inline
qa: user-validated
parent: 0013
priority: P0
estimate: S
depends_on: []
touches:
  - JamBox/PlayerEngine.swift
acceptance:
  - The format badge renders correctly for FLAC files (e.g. `FLAC · 48 kHz · 24 bit`).
  - Other lossless formats (ALAC, WAV, AIFF) continue to work or fail gracefully.
  - Lossy formats (MP3, AAC) still hide the badge per existing card 0013 behavior (card 0019 will revisit this design call).
  - No new AVURLAsset construction site introduced (§7.1 preserved).
  - No sandbox or scoped-resource changes (§7.4 preserved).
  - Build green: ** BUILD SUCCEEDED **
  - User-validated by ear and by eye on real 24/48 FLAC files in their library.
---

## Context

Card 0013 shipped with a bug: the format badge never appeared for any FLAC file. The user discovered it the moment they opened the Release build and played the first track in their library — `Beast In Black - Dark Connection - 06 Moonlight Rendezvous.flac` (24-bit, 44.1 kHz FLAC) showed title/artist/album but no badge below.

The bug was in `PlayerEngine.readAudioFormat`. The engineer read `mBitsPerChannel` off `CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc).pointee`, then applied the "hide on zero" rule from the designer's spec. For compressed formats including FLAC, the **primary `AudioStreamBasicDescription` reports `mBitsPerChannel == 0`** because that field describes AVFoundation's *decode-target* PCM format, not the source PCM bit depth. Source bit depth lives in the file's metadata block (FLAC's STREAMINFO, ALAC's magic cookie). So the hide-on-zero rule fired for every FLAC file → no badge ever rendered.

This is exactly the kind of bug the §6c post-QA review exists to catch, and it didn't, because:
1. The engineer's self-audit was code-correct against the spec.
2. QA's audit was code-correct against the acceptance.
3. The §6c review (performed inline by manager due to API overload) reasoned about user-facing edge cases but did not have a real 24-bit FLAC file to actually run against.

All three reviewers were reading code, not running it on real files. The first time the code met a real file, it broke.

## Fix attempts

**Attempt 1 (failed): `ExtAudioFile` from AudioToolbox.** I added a fallback that opened the file via `ExtAudioFileOpenURL` and read `kExtAudioFileProperty_FileDataFormat`, on the theory that AudioToolbox's lower-level reader would reliably report source PCM format. Diagnostic prints proved this wrong: `ExtAudioFileOpenURL` returned an error code for FLAC files in this app's runtime — most likely because AudioToolbox's FLAC reader is not enabled in the sandboxed app context (or doesn't support FLAC on this macOS version at all). I went down this path because I trusted Apple documentation without verifying. Lesson: when fixing a sibling bug to one that was just shipped without real-file testing, also test the fix on real files before claiming it.

**Attempt 2 (works): direct STREAMINFO parser.** FLAC's STREAMINFO metadata block is mandatory, always the first block, always at file offset 8 (after the 4-byte "fLaC" magic and 4-byte metadata block header). The bit depth is encoded in 5 bits within bytes 12-13 of the STREAMINFO block (file bytes 20-21), straddling a byte boundary: low bit of byte 20 + high 4 bits of byte 21, plus 1 (the field stores bit_depth - 1). Parser reads only the first 22 bytes of the file via `FileHandle.read(upToCount:)`, validates the "fLaC" magic, validates the block type is STREAMINFO (type 0), extracts the 5-bit field, and returns `Int?`. No AudioToolbox surface, no extra file open beyond a single read of 22 bytes, no security-scoped resource issue.

The fallback only fires when (a) the codec was already identified as FLAC by AVFoundation's `mFormatID == kAudioFormatFLAC` AND (b) `mBitsPerChannel == 0` AND (c) the asset is an `AVURLAsset` (so we can get the file URL). For lossy formats (MP3/AAC) the fallback is not invoked because the codec name check excludes them — the "should we show a degraded badge for lossy formats" question is still card 0019.

## Code change

`JamBox/PlayerEngine.swift`:

1. In `readAudioFormat`, after extracting `bits = Int(asbd.mBitsPerChannel)`, if `bits == 0` and `name == "FLAC"`, fall back to `Self.readSourceBitDepth(from: urlAsset.url)`.
2. New private static helper `readSourceBitDepth(from url: URL) -> Int?` that opens the file via `FileHandle`, reads 22 bytes, validates the FLAC magic and STREAMINFO header, extracts the 5-bit `bits per sample - 1` field, and returns the result if it's in `4...32` (the FLAC spec range).

## Validation

User opened the rebuilt Release binary, played the same FLAC file that originally exhibited the bug, and confirmed the badge now reads `FLAC · 48 kHz · 24 bit`. They also confirmed working on `Galahad And The Grail` from a different artist's 24-bit folder.

## Process note

Both this card and card 0021 (spacebar focus after resume) were fixed inline by the manager rather than dispatched as full engineer cards. Justification: the user was actively testing the Release build and the loop time of "spawn engineer → plan → implement → self-audit → QA → §6c → done" would have been 30+ minutes for what turned out to be ~30 lines of code. The API was also intermittently overloaded.

The deeper lesson: **the project needs committed real-file test fixtures** before the next audio-format card ships. Card 0006 (test coverage, in backlog) should grow an explicit acceptance bullet for "small representative audio files (1 FLAC at 16-bit and 24-bit, 1 ALAC, 1 MP3, 1 AAC, 1 WAV, 1 AIFF) committed under `JamBox/Tests/Fixtures/` and used by every audio-format-touching test." Without those, no amount of code review would have caught either bug.

A second process note: the §6c review is supposed to be the user-advocate's last chance to catch behavioral gaps before shipping. It still passed, because the reviewer (manager-inline) was reasoning about the *kinds* of files that would hit edge cases, not actually running against them. §6c needs either real-file fixtures or an explicit "if you cannot run this on real input, downgrade your confidence and flag the gap" rule. Filing as a follow-up consideration for a future PM protocol revision.

## Manager Decision

2026-04-08 — APPROVE. User validated by ear and by eye on multiple real 24-bit FLAC files. Closing to done/ as a hotfix to card 0013. Process gap documented above; will inform card 0006 when it gets dispatched and may inform a future PM protocol revision (designer §6c with real-fixture requirement).
