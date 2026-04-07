import AppKit
import AVFoundation
import Combine

final class PlayerEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: Track?
    @Published var currentArtwork: NSImage?
    @Published var tracks: [Track] = []
    @Published var playbackPosition: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0

    private var queuePlayer = AVQueuePlayer()
    private var cancellables = Set<AnyCancellable>()
    private var currentIndex: Int?
    private var artworkCache: [URL: NSImage?] = [:]
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
            self.playbackPosition = time.seconds.isFinite ? time.seconds : 0

            if let item = self.queuePlayer.currentItem {
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 {
                    self.playbackDuration = dur
                    return
                }
            }
            self.playbackDuration = self.currentTrack?.duration ?? 0
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
        playbackPosition = 0
        playbackDuration = 0
    }

    func updateMetadata(_ enrichedTracks: [Track]) {
        let lookup = Dictionary(enrichedTracks.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        tracks = tracks.map { lookup[$0.id] ?? $0 }

        if let current = currentTrack, let enriched = lookup[current.id] {
            currentTrack = enriched
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
        playbackPosition = 0
        playbackDuration = tracks[index].duration
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
        let target = clamped * playbackDuration
        guard target.isFinite, playbackDuration > 0 else { return }

        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        queuePlayer.seek(to: cmTime)
    }

    // MARK: - Private

    private func handleItemChange(_ item: AVPlayerItem?) {
        playbackPosition = 0

        guard let item = item else {
            currentTrack = nil
            currentIndex = nil
            currentArtwork = nil
            playbackDuration = 0
            return
        }

        if let matched = tracks.firstIndex(where: {
            ($0.url as NSURL) == (item.asset as? AVURLAsset)?.url as NSURL?
        }) {
            currentIndex = matched
            currentTrack = tracks[matched]
            playbackDuration = tracks[matched].duration
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
            currentArtwork = cached
            return
        }

        Task {
            let image = await Self.findArtwork(for: track.url)
            await MainActor.run {
                self.artworkCache[folder] = image
                if self.currentTrack?.id == track.id {
                    self.currentArtwork = image
                }
            }
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
                return image
            }
        }

        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let items = try? await asset.loadMetadata(for: format) {
                    for item in items {
                        if item.identifier == .commonIdentifierArtwork,
                           let data = try? await item.load(.dataValue),
                           let image = NSImage(data: data) {
                            return image
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
                return NSImage(contentsOf: match)
            }
        }

        return imageFiles.first.flatMap { NSImage(contentsOf: $0) }
    }
}
