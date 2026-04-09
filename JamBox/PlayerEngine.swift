import AppKit
import AVFoundation
import Combine

/// High-frequency playback time state, isolated into its own ObservableObject
/// so that 4Hz updates from the periodic time observer do NOT trigger
/// re-renders of views that observe `PlayerEngine` itself.
///
/// SwiftUI subscribes to an entire ObservableObject's `objectWillChange`
/// publisher, which fires for any `@Published` write — even ones the
/// observing view doesn't actually read. If `playbackPosition` lived on
/// `PlayerEngine`, every `ContentView` body re-eval would happen 4 times
/// per second, churning the song-table `NSTableView` and racing with
/// in-progress mouse clicks (the "every third click fails" bug, card 0002).
///
/// Only `NowPlayingBar` and `MediaKeyController` need these high-frequency
/// values; both observe this clock directly via `@ObservedObject` /
/// `$position` Combine subscription.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

@MainActor
final class PlayerEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: Track?
    @Published var currentArtwork: NSImage?
    @Published var tracks: [Track] = []

    /// High-frequency playback time. See `PlaybackClock` doc above.
    /// Exposed as `let` (non-`@Published`) so that subscribers to
    /// `PlayerEngine` do NOT see clock ticks. Views that need the live
    /// position observe `clock` directly.
    let clock = PlaybackClock()

    private var queuePlayer = AVQueuePlayer()
    private var cancellables = Set<AnyCancellable>()
    private var currentIndex: Int?

    /// Per-folder artwork cache, bounded LRU. Folders that haven't been
    /// touched recently get evicted so the cache cannot grow without bound.
    /// `nil` values are cached too (negative cache: "this folder has no art")
    /// so we don't re-scan a folder that we already know has nothing.
    /// Cap is intentionally small — playback is sequential, so the working
    /// set is "current album + the next few," and 8 is plenty for that.
    private var artworkCache: [URL: NSImage?] = [:]
    private var artworkCacheOrder: [URL] = []
    private static let artworkCacheLimit = 8

    private var timeObserverToken: Any?

    /// How many items to keep buffered ahead in the queue.
    private let lookAhead = 3

    /// Asset options used for all AVURLAsset creation.
    /// PreferPreciseDurationAndTiming forces AVFoundation to scan the actual
    /// audio data for timing rather than trusting the container header.
    /// Without this, FLAC files with inaccurate STREAMINFO headers report
    /// wrong durations and play past their stated end.
    private static let assetOptions: [String: Any] = [
        AVURLAssetPreferPreciseDurationAndTimingKey: true
    ]

    init() {
        queuePlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlaying = (status == .playing)
            }
            .store(in: &cancellables)

        queuePlayer.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.handleItemChange(item)
            }
            .store(in: &cancellables)

        let interval = CMTime(value: 1, timescale: 4)
        timeObserverToken = queuePlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            // Writes go to the isolated clock, NOT to PlayerEngine itself,
            // so observers of PlayerEngine (e.g. ContentView) don't re-render
            // 4 times per second. See PlaybackClock doc.
            self.clock.position = time.seconds.isFinite ? time.seconds : 0

            if let item = self.queuePlayer.currentItem {
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 {
                    self.clock.duration = dur
                    return
                }
            }
            self.clock.duration = self.currentTrack?.duration ?? 0
        }
    }

    deinit {
        if let token = timeObserverToken {
            queuePlayer.removeTimeObserver(token)
        }
    }

    // MARK: - Public API

    func loadTracks(_ newTracks: [Track]) {
        queuePlayer.removeAllItems()
        tracks = newTracks
        currentTrack = nil
        currentIndex = nil
        currentArtwork = nil
        artworkCache.removeAll()
        artworkCacheOrder.removeAll()
        clock.position = 0
        clock.duration = 0
    }

    /// Reorder `tracks` to match `newOrder` without disrupting playback.
    /// Caller guarantees `newOrder` is a permutation of the current `tracks`
    /// (same set of URLs, just in a different order). Used by the column-sort
    /// feature (card 0011): sorting drives the playback queue, so the visible
    /// sort order must match `player.tracks` itself.
    ///
    /// Behavior:
    /// - No-op if `newOrder` already matches `tracks` by id sequence.
    /// - `tracks` is reassigned to `newOrder`.
    /// - `currentIndex` is recomputed by URL match (mirrors `updateMetadata`
    ///   and `applyTrackDiff`), so the currently-playing track's index moves
    ///   with it.
    /// - The AVQueuePlayer's currently-playing item (index 0 in `items()`) is
    ///   left untouched. Any already-enqueued lookahead items AFTER it are
    ///   removed, then `enqueueMoreIfNeeded()` refills from the new position.
    ///   This preserves gapless playback of the current track while ensuring
    ///   the next-up track reflects the new sort order.
    func reorderTracks(to newOrder: [Track]) {
        // No-op guard: avoid an infinite loop when a SwiftUI .onChange
        // observer calls us with the same sequence we already have.
        if newOrder.count == tracks.count,
           zip(newOrder, tracks).allSatisfy({ $0.id == $1.id }) {
            return
        }

        let currentURL = currentTrack?.url
        tracks = newOrder

        guard let url = currentURL,
              let newIndex = tracks.firstIndex(where: { $0.url == url }) else {
            // Nothing playing — nothing more to do. No queue items to prune.
            return
        }

        currentIndex = newIndex

        // Prune stale lookahead items (everything after the currently-playing
        // item). `items()` returns the queue in play order with the current
        // item at index 0. Removing items beyond index 0 does not interrupt
        // the current item per AVQueuePlayer semantics.
        let queued = queuePlayer.items()
        if queued.count > 1 {
            for stale in queued.dropFirst() {
                queuePlayer.remove(stale)
            }
        }

        // Refill the lookahead from the new index + 1.
        enqueueMoreIfNeeded()
    }

    func updateMetadata(_ enrichedTracks: [Track]) {
        let lookup = Dictionary(enrichedTracks.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        tracks = tracks.map { lookup[$0.id] ?? $0 }

        if let current = currentTrack, let enriched = lookup[current.id] {
            currentTrack = enriched
        }
    }

    /// Apply a set of added/removed tracks without disrupting current playback.
    /// Used by the folder watcher when files appear or disappear.
    /// - Removed tracks are dropped from the array. If the currently playing
    ///   track is removed, playback is paused and cleared.
    /// - Added tracks are merged in and the list is re-sorted by filename
    ///   (matching FileScanner.scanFolder's order).
    /// - currentIndex is recomputed from the (still valid) currentTrack URL.
    /// - The AVQueuePlayer's queued items are NOT touched, so audio keeps playing.
    func applyTrackDiff(added: [Track], removedURLs: Set<URL>) {
        let currentURL = currentTrack?.url

        // If the playing track was removed, stop playback first
        if let url = currentURL, removedURLs.contains(url) {
            queuePlayer.removeAllItems()
            currentTrack = nil
            currentIndex = nil
            currentArtwork = nil
            clock.position = 0
            clock.duration = 0
        }

        // Build the new track list: drop removed, add new, re-sort.
        // Sort by filename (not displayName) so the order stays consistent
        // with FileScanner.scanFolder, which sorts before metadata is loaded.
        // displayName changes from filename to metadata title after enrichment,
        // so sorting by it would scramble the list every time we apply a diff.
        var next = tracks.filter { !removedURLs.contains($0.url) }
        next.append(contentsOf: added)
        next.sort {
            $0.url.deletingPathExtension().lastPathComponent
                .localizedCaseInsensitiveCompare($1.url.deletingPathExtension().lastPathComponent)
                == .orderedAscending
        }
        tracks = next

        // Recompute currentIndex by URL match (if still playing something)
        if let url = currentURL, !removedURLs.contains(url) {
            currentIndex = tracks.firstIndex { $0.url == url }
        }
    }

    func play(startingAt index: Int) {
        guard index >= 0, index < tracks.count else { return }
        queuePlayer.removeAllItems()
        currentIndex = index

        let end = min(index + lookAhead, tracks.count)
        for track in tracks[index..<end] {
            let asset = AVURLAsset(url: track.url, options: Self.assetOptions)
            queuePlayer.insert(AVPlayerItem(asset: asset), after: nil)
        }

        currentTrack = tracks[index]
        clock.position = 0
        clock.duration = tracks[index].duration
        loadArtwork(for: tracks[index])
        queuePlayer.play()
    }

    func togglePlayPause() {
        if queuePlayer.timeControlStatus == .playing {
            queuePlayer.pause()
        } else if currentTrack != nil {
            queuePlayer.play()
        }
    }

    func skipForward() {
        queuePlayer.advanceToNextItem()
    }

    func skipBackward() {
        guard let index = currentIndex else { return }

        let currentTime = queuePlayer.currentTime().seconds
        if !currentTime.isFinite || currentTime > 3 || index == 0 {
            queuePlayer.seek(to: .zero)
        } else {
            play(startingAt: index - 1)
        }
    }

    func seek(to fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        let target = clamped * clock.duration
        guard target.isFinite, clock.duration > 0 else { return }

        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        queuePlayer.seek(to: cmTime)
    }

    // MARK: - Private

    private func handleItemChange(_ item: AVPlayerItem?) {
        clock.position = 0

        guard let item = item else {
            currentTrack = nil
            currentIndex = nil
            currentArtwork = nil
            clock.duration = 0
            return
        }

        if let matched = tracks.firstIndex(where: {
            ($0.url as NSURL) == (item.asset as? AVURLAsset)?.url as NSURL?
        }) {
            currentIndex = matched
            currentTrack = tracks[matched]
            clock.duration = tracks[matched].duration
            loadArtwork(for: tracks[matched])
            enqueueMoreIfNeeded()
        }
    }

    private func enqueueMoreIfNeeded() {
        guard let index = currentIndex else { return }

        let queuedCount = queuePlayer.items().count
        let lastEnqueued = index + queuedCount - 1
        let desired = index + lookAhead

        for i in (lastEnqueued + 1)..<min(desired, tracks.count) {
            let asset = AVURLAsset(url: tracks[i].url, options: Self.assetOptions)
            queuePlayer.insert(AVPlayerItem(asset: asset), after: nil)
        }
    }

    // MARK: - Artwork

    private static let artworkFilenames = ["cover", "folder", "album", "front", "artwork", "art"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "bmp", "tiff"]

    private func loadArtwork(for track: Track) {
        let folder = track.url.deletingLastPathComponent()

        if let cached = artworkCache[folder] {
            touchArtworkCache(folder)
            currentArtwork = cached
            return
        }

        Task {
            let image = await Self.findArtwork(for: track.url)
            await MainActor.run {
                self.insertArtworkCache(folder, image: image)
                if self.currentTrack?.id == track.id {
                    self.currentArtwork = image
                }
            }
        }
    }

    /// Mark a folder as most-recently-used in the LRU order.
    private func touchArtworkCache(_ folder: URL) {
        if let idx = artworkCacheOrder.firstIndex(of: folder) {
            artworkCacheOrder.remove(at: idx)
        }
        artworkCacheOrder.append(folder)
    }

    /// Insert a new entry into the bounded LRU artwork cache, evicting the
    /// least-recently-used entry if the cache is full.
    private func insertArtworkCache(_ folder: URL, image: NSImage?) {
        if artworkCache[folder] != nil {
            // Already present (race: two loads kicked off simultaneously).
            // Refresh order but don't bump count.
            touchArtworkCache(folder)
            return
        }
        artworkCache[folder] = image
        artworkCacheOrder.append(folder)
        while artworkCacheOrder.count > Self.artworkCacheLimit {
            let evict = artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: evict)
        }
    }

    private static func findArtwork(for trackURL: URL) async -> NSImage? {
        let asset = AVURLAsset(url: trackURL, options: assetOptions)
        if let common = try? await asset.load(.commonMetadata) {
            let artworkItems = AVMetadataItem.metadataItems(
                from: common,
                filteredByIdentifier: .commonIdentifierArtwork
            )
            if let data = try? await artworkItems.first?.load(.dataValue),
               let image = NSImage(data: data) {
                return downscale(image)
            }
        }

        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let items = try? await asset.loadMetadata(for: format) {
                    for item in items {
                        if item.identifier == .commonIdentifierArtwork,
                           let data = try? await item.load(.dataValue),
                           let image = NSImage(data: data) {
                            return downscale(image)
                        }
                    }
                }
            }
        }

        let folder = trackURL.deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        let imageFiles = contents.filter { imageExtensions.contains($0.pathExtension.lowercased()) }

        for name in artworkFilenames {
            if let match = imageFiles.first(where: {
                $0.deletingPathExtension().lastPathComponent.lowercased() == name
            }) {
                return NSImage(contentsOf: match).flatMap(downscale)
            }
        }

        return imageFiles.first.flatMap { NSImage(contentsOf: $0) }.flatMap(downscale)
    }

    /// Downscale an `NSImage` so its longest side is at most
    /// `maxArtworkDimension` points. Albums commonly embed 2000–3000 px
    /// artwork; we display it in a 60 px thumbnail and a fit-to-window
    /// overlay, so anything beyond ~1024 px is wasted decoded bitmap memory.
    /// Returns the original image untouched if it's already small enough.
    /// Always returns a non-nil result given a non-nil input.
    private static let maxArtworkDimension: CGFloat = 1024

    private static func downscale(_ image: NSImage) -> NSImage {
        let original = image.size
        let longest = max(original.width, original.height)
        guard longest > maxArtworkDimension, original.width > 0, original.height > 0 else {
            return image
        }

        let scale = maxArtworkDimension / longest
        let newSize = NSSize(
            width: floor(original.width * scale),
            height: floor(original.height * scale)
        )

        let pixelW = Int(newSize.width)
        let pixelH = Int(newSize.height)
        guard pixelW > 0, pixelH > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelW,
                pixelsHigh: pixelH,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              )
        else { return image }

        rep.size = newSize
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        context.flushGraphics()

        let scaled = NSImage(size: newSize)
        scaled.addRepresentation(rep)
        return scaled
    }
}
