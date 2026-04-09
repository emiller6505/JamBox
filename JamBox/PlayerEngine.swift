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

/// Immutable value describing the audio format of the currently-playing
/// track — codec name, sample rate, bit depth, and whether the PCM is
/// floating point. Built from the current `AVPlayerItem.asset`'s first
/// audio track's `CMAudioFormatDescription` → `AudioStreamBasicDescription`,
/// never from the file extension (the .m4a container can hold either ALAC
/// or AAC, so we need the codec-level truth).
///
/// Lives on `PlayerEngine` as `@Published var currentFormat: AudioFormat?`,
/// NOT on `PlaybackClock`, so the 4Hz clock observer does not cause
/// re-renders or refetches. See `PlaybackClock` doc above.
///
/// Card 0013 — format badge in NowPlayingBar.
struct AudioFormat: Equatable {
    /// Whitelisted codec short name: "FLAC", "ALAC", "MP3", "AAC", "WAV", "AIFF".
    let name: String
    /// Sample rate in Hz (e.g. 96000).
    let sampleRateHz: Double
    /// Bits per sample (e.g. 24).
    let bitDepth: Int
    /// True iff the stream is LPCM float (e.g. 32-bit float WAV).
    let isFloat: Bool

    /// Compact visual badge string.
    /// Middle-dot separator (U+00B7), period decimals regardless of locale,
    /// lowercase-k kHz, `24 bit` not `24 bits`, special-case `32 bit float`.
    /// Example: `"FLAC · 96 kHz · 24 bit"`.
    var visual: String {
        "\(name) · \(sampleRateNumber) kHz · \(bitDepthString)"
    }

    /// Long-form VoiceOver label, distinct from the compact visual.
    /// Example: `"Audio format: FLAC, 96 kilohertz, 24 bit"`.
    /// Float case: `"Audio format: WAV, 96 kilohertz, 32 bit floating point"`.
    var voiceOver: String {
        let depth = isFloat ? "\(bitDepth) bit floating point" : "\(bitDepth) bit"
        return "Audio format: \(name), \(sampleRateNumber) kilohertz, \(depth)"
    }

    /// Sample rate number (no unit) per designer spec:
    /// - Divide by 1000.
    /// - If the result has a non-zero fractional part, show one decimal
    ///   (e.g. 44100 → "44.1", 176400 → "176.4").
    /// - Else show an integer (e.g. 48000 → "48", 96000 → "96").
    /// - Always period decimal, never locale-dependent comma. This is a
    ///   technical receipt, not localized prose.
    private var sampleRateNumber: String {
        let kHz = sampleRateHz / 1000.0
        // Round to one decimal place for comparison.
        let rounded1 = (kHz * 10).rounded() / 10
        let isInteger = abs(rounded1 - rounded1.rounded()) < 1e-6
        let locale = Locale(identifier: "en_US_POSIX")
        if isInteger {
            return String(format: "%.0f", locale: locale, rounded1)
        } else {
            return String(format: "%.1f", locale: locale, rounded1)
        }
    }

    /// Bit depth formatted per designer spec: `"24 bit"`, or `"32 bit float"`
    /// for LPCM floating-point streams. Never pluralized to "bits".
    private var bitDepthString: String {
        if isFloat {
            return "\(bitDepth) bit float"
        }
        return "\(bitDepth) bit"
    }
}

@MainActor
final class PlayerEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: Track?
    @Published var currentArtwork: NSImage?
    @Published var tracks: [Track] = []

    /// Audio format of the currently-playing track (codec + sample rate +
    /// bit depth). `nil` when nothing is playing OR when any field cannot
    /// be determined — the badge in `NowPlayingBar` is hidden in both cases.
    ///
    /// Populated asynchronously from `handleItemChange(_:)` by reading the
    /// existing `AVPlayerItem.asset`'s first audio track's format description.
    /// We do NOT construct a new `AVURLAsset` here (§7.1) — we reuse the one
    /// already in the playback queue. Fetches are identity-checked on
    /// completion so rapid next-track spam can't show stale format info.
    ///
    /// Lives on `PlayerEngine`, not `PlaybackClock`, so the 4Hz clock tick
    /// never invalidates format. See `PlaybackClock` doc above.
    /// Card 0013.
    @Published var currentFormat: AudioFormat?

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

    /// The ONE place `AVURLAsset` + `AVPlayerItem` get constructed for the
    /// playback queue. Every code path that enqueues audio (initial play,
    /// lookahead top-up, resume-on-launch) goes through this helper so the
    /// `assetOptions` — specifically `AVURLAssetPreferPreciseDurationAndTimingKey`
    /// — can never be forgotten. See README §7.1.
    private static func makeAssetItem(for url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: assetOptions)
        return AVPlayerItem(asset: asset)
    }

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
        currentFormat = nil
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
            currentFormat = nil
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
            queuePlayer.insert(Self.makeAssetItem(for: track.url), after: nil)
        }

        currentTrack = tracks[index]
        clock.position = 0
        clock.duration = tracks[index].duration
        loadArtwork(for: tracks[index])
        queuePlayer.play()
    }

    /// Seed the player at `trackIndex` paused at `position` (card 0012).
    ///
    /// Mirrors `play(startingAt:)` structurally — same single asset-construction
    /// path via `makeAssetItem`, same synchronous lookahead fill — but:
    /// (a) does NOT call `queuePlayer.play()` (state stays `.paused`),
    /// (b) `clock.position` is seeded to `position` before the seek so the
    ///     scrub bar never flashes 0 (no "start at 0 then jump" frame),
    /// (c) after queue + UI are seeded synchronously, an async Task loads
    ///     the first asset's real duration, clamps the saved position, and
    ///     re-seeks if the saved value exceeded the real duration. If the
    ///     asset fails to load its duration at all the track is unresumable:
    ///     `onFailure` is invoked on the MainActor so the caller can clear
    ///     its persisted state.
    ///
    /// §7.2: all `lookAhead` items are inserted synchronously before this
    /// function returns, so the first track→next transition after the user
    /// presses play is gapless.
    func resume(trackIndex index: Int, position: TimeInterval, onFailure: @escaping @MainActor () -> Void) {
        guard index >= 0, index < tracks.count else {
            onFailure()
            return
        }
        queuePlayer.removeAllItems()
        currentIndex = index

        let end = min(index + lookAhead, tracks.count)
        for track in tracks[index..<end] {
            queuePlayer.insert(Self.makeAssetItem(for: track.url), after: nil)
        }

        // Sanitize the saved position. Real clamp to duration happens after
        // the asset loads its duration below; for now just ensure we seed a
        // finite non-negative value so the scrub bar is stable.
        let sanitized = (position.isFinite && position >= 0) ? position : 0

        currentTrack = tracks[index]
        clock.position = sanitized
        // Track.duration is 0 for cheap init(url:) tracks — seed from it
        // anyway; the async duration-load below will overwrite it with the
        // real value once AVFoundation has parsed the container.
        clock.duration = tracks[index].duration
        loadArtwork(for: tracks[index])

        // Seek to the seeded position immediately so currentTime() reflects
        // it even though we're paused. Fire-and-forget; if it fails the user
        // just lands at 0 for that track, which is tolerable.
        let cmTime = CMTime(seconds: sanitized, preferredTimescale: 600)
        queuePlayer.seek(to: cmTime)

        // Asynchronously load the real duration, clamp if the saved position
        // overshoots, and tear down on load failure (acceptance bullet 6 +
        // "duration load fails → silent clear").
        guard let firstItem = queuePlayer.items().first else {
            // Shouldn't happen — we just inserted at least one — but be safe.
            onFailure()
            clearPlayback()
            return
        }
        let asset = firstItem.asset
        let savedURL = tracks[index].url
        Task { [weak self] in
            let loaded = try? await asset.load(.duration)
            let seconds = loaded?.seconds ?? .nan
            await MainActor.run {
                guard let self else { return }
                // If the user already moved on (different track queued, or
                // playback cleared), abandon.
                guard self.currentTrack?.url == savedURL else { return }

                if !seconds.isFinite || seconds <= 0 {
                    // Unresumable — silent teardown.
                    self.clearPlayback()
                    onFailure()
                    return
                }

                self.clock.duration = seconds
                let clamped = max(0, min(sanitized, seconds))
                if abs(clamped - sanitized) > 0.01 {
                    self.clock.position = clamped
                    let newTime = CMTime(seconds: clamped, preferredTimescale: 600)
                    self.queuePlayer.seek(to: newTime)
                }
            }
        }
    }

    /// Tear down current playback without touching the `tracks` list.
    /// Used by resume failure paths (card 0012) to return the engine to a
    /// "nothing playing" state while keeping the loaded folder intact.
    func clearPlayback() {
        queuePlayer.removeAllItems()
        currentTrack = nil
        currentIndex = nil
        currentArtwork = nil
        currentFormat = nil
        clock.position = 0
        clock.duration = 0
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
            currentFormat = nil
            clock.duration = 0
            return
        }

        if let matched = tracks.firstIndex(where: {
            ($0.url as NSURL) == (item.asset as? AVURLAsset)?.url as NSURL?
        }) {
            currentIndex = matched
            currentTrack = tracks[matched]
            clock.duration = tracks[matched].duration
            // Clear stale format immediately so a fast visual glance never
            // shows the previous track's spec. `loadFormat` re-populates it
            // asynchronously, with an identity check on completion.
            currentFormat = nil
            loadArtwork(for: tracks[matched])
            loadFormat(for: tracks[matched], from: item.asset)
            enqueueMoreIfNeeded()
        }
    }

    private func enqueueMoreIfNeeded() {
        guard let index = currentIndex else { return }

        let queuedCount = queuePlayer.items().count
        let lastEnqueued = index + queuedCount - 1
        let desired = index + lookAhead

        for i in (lastEnqueued + 1)..<min(desired, tracks.count) {
            queuePlayer.insert(Self.makeAssetItem(for: tracks[i].url), after: nil)
        }
    }

    // MARK: - Audio format (card 0013)

    /// Asynchronously read the current item's audio format (codec + sample
    /// rate + bit depth) from the existing `AVAsset` already in the playback
    /// queue. We do NOT construct a new `AVURLAsset` (§7.1). If any field is
    /// missing/zero or the codec is outside the whitelist, `currentFormat`
    /// stays nil and the badge is hidden — silent failure is the right
    /// behavior for a caption-class UI element.
    ///
    /// Mirrors the identity-check pattern used by `loadArtwork`: we capture
    /// the track id at dispatch, and on completion only assign if the user
    /// hasn't already moved on to a different track (rapid next-track spam).
    private func loadFormat(for track: Track, from asset: AVAsset) {
        let capturedId = track.id
        Task {
            let format = await Self.readAudioFormat(from: asset)
            await MainActor.run {
                // Identity check: if the user has already skipped ahead,
                // discard this stale result instead of flashing old info.
                guard self.currentTrack?.id == capturedId else { return }
                self.currentFormat = format
            }
        }
    }

    /// Pull an `AudioFormat` out of the asset's first audio track.
    /// Returns nil if anything is missing, zero, or outside the codec
    /// whitelist (hide-the-whole-badge rule — never show a partial badge).
    private static func readAudioFormat(from asset: AVAsset) async -> AudioFormat? {
        // First audio track — JamBox is a music player and the supported
        // formats (mp3/m4a/flac/aiff/wav/alac/aac) don't normally have
        // multiple audio tracks, but if they do we pick the first, which
        // matches AVQueuePlayer's own playback behavior.
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              let audioTrack = tracks.first else {
            return nil
        }

        guard let formatDescriptions = try? await audioTrack.load(.formatDescriptions),
              let formatDesc = formatDescriptions.first else {
            return nil
        }

        guard let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let asbd = asbdPointer.pointee

        // Map mFormatID → short codec name. WAV/AIFF are both LPCM, so we
        // disambiguate those two by file extension — the ONLY place this
        // card looks at the extension, and only to distinguish between two
        // LPCM containers (never to choose the codec itself).
        let name: String
        switch asbd.mFormatID {
        case kAudioFormatFLAC:
            name = "FLAC"
        case kAudioFormatAppleLossless:
            name = "ALAC"
        case kAudioFormatMPEGLayer3:
            name = "MP3"
        case kAudioFormatMPEG4AAC,
             kAudioFormatMPEG4AAC_HE,
             kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD,
             kAudioFormatMPEG4AAC_ELD,
             kAudioFormatMPEG4AAC_Spatial:
            name = "AAC"
        case kAudioFormatLinearPCM:
            // LPCM container disambiguation via the asset's URL extension.
            // `.wav` and `.aiff`/`.aif` both hold LPCM; there's no codec-
            // level signal for the container type.
            if let urlAsset = asset as? AVURLAsset {
                let ext = urlAsset.url.pathExtension.lowercased()
                switch ext {
                case "wav":
                    name = "WAV"
                case "aiff", "aif":
                    name = "AIFF"
                default:
                    return nil
                }
            } else {
                return nil
            }
        default:
            return nil
        }

        // Sample rate — treat zero / non-finite as missing → hide badge.
        let sampleRate = asbd.mSampleRate
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }

        // Bit depth — zero means AVFoundation couldn't determine it, hide.
        let bits = Int(asbd.mBitsPerChannel)
        guard bits > 0 else { return nil }

        // Float flag is only meaningful for LPCM. For compressed codecs
        // (FLAC, ALAC, AAC, MP3) it's always false.
        let isFloat = (asbd.mFormatID == kAudioFormatLinearPCM)
            && (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0

        return AudioFormat(
            name: name,
            sampleRateHz: sampleRate,
            bitDepth: bits,
            isFloat: isFloat
        )
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
