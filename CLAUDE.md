# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

JamBox is a minimalist macOS music player with gapless audio playback as a first-class priority. Built with Swift and SwiftUI, targeting macOS 14.0+.

## Build Commands

```bash
# Build
xcodebuild -project JamBox.xcodeproj -scheme JamBox build

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/JamBox-*/Build/Products/Debug/JamBox.app

# Run with stdout visible (for debug prints)
~/Library/Developer/Xcode/DerivedData/JamBox-*/Build/Products/Debug/JamBox.app/Contents/MacOS/JamBox

# Regenerate Xcode project after adding/removing files (requires xcodegen)
xcodegen generate
```

## Architecture

- **ContentView** (`ContentView.swift`) — Main window. Track list via `Table` with double-click-to-play (AppKit bridge via `TableDoubleClick.swift`). Album art overlay as a `ZStack` layer. Folder management with security-scoped bookmarks.
- **NowPlayingBar** (`NowPlayingBar.swift`) — Extracted transport controls + scrub bar. Drag-decouple pattern: local `@State isScrubbing` / `scrubFraction` decouple the slider from live playback during drags. Clickable artwork thumbnail with `PointerCursorView` overlay for cursor.
- **PlayerEngine** (`PlayerEngine.swift`) — `ObservableObject` wrapping `AVQueuePlayer`. Bounded queue (3 items lookahead). Periodic time observer at 4Hz for scrub bar. `timeControlStatus` KVO as source of truth for play/pause. Per-folder artwork cache.
- **FileScanner** (`FileScanner.swift`) — Two-phase: fast filesystem scan (`scanFolder`), then async metadata enrichment (`loadMetadata`) with bounded concurrency (8 parallel via `withTaskGroup`).
- **Track** (`Track.swift`) — `Identifiable` struct. Lightweight `init(url:)` for quick display, async `loadMetadata(url:)` for full metadata from multiple formats (common, Vorbis, ID3, iTunes).
- **TableDoubleClick** (`TableDoubleClick.swift`) — `NSViewRepresentable` that finds the `NSTableView` backing SwiftUI's `Table` and wires its `doubleAction`.

## Critical: AVURLAsset Options

**All `AVURLAsset` creation MUST use `AVURLAssetPreferPreciseDurationAndTimingKey: true`.** Without this, FLAC files with inaccurate STREAMINFO headers report wrong durations and play 2-5+ seconds past their stated end. This also causes `FigFilePlayer err=-12864` errors. Never use `AVPlayerItem(url:)` — always create an `AVURLAsset` with the options first, then `AVPlayerItem(asset:)`.

## Key Patterns

- **Two-phase loading:** UI shows filenames immediately via `loadTracks`, metadata loads in background, then `updateMetadata` swaps enriched tracks in-place without disrupting active playback.
- **Gapless playback** via `AVQueuePlayer` with 3-item lookahead. `enqueueMoreIfNeeded()` tops up the queue as tracks advance.
- **Vorbis metadata fallback:** AVFoundation's `commonMetadata` is empty for FLAC. Code checks format-specific metadata under `vorb/` identifiers (e.g. `vorb/TITLE`).
- **Artwork resolution:** embedded metadata → folder images with known names (cover, folder, album, front) → any image in folder. Cached per-folder.
- **Security-scoped bookmarks** persist folder access across launches. Balanced `start/stopAccessingSecurityScopedResource` calls.
- **Scrub bar drag-decouple:** During drag, slider reads/writes local `scrubFraction`. On release, `player.seek(to:)` then re-couples to live position.

## Project Configuration

- `project.yml` — XcodeGen spec. Run `xcodegen generate` after adding/removing source files.
- `JamBox/JamBox.entitlements` — App sandbox: read-only user-selected files, app-scoped bookmarks.
- Bundle ID: `com.jambox.app`
- Supported audio formats: mp3, m4a, flac, aiff, aif, wav, alac, aac.
