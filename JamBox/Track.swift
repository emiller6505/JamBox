import AVFoundation
import Foundation

struct Track: Identifiable {
    let id: URL
    let url: URL
    let displayName: String
    let artist: String
    let album: String
    let trackNumber: Int?
    let duration: TimeInterval

    var durationString: String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var trackNumberString: String {
        trackNumber.map { String($0) } ?? ""
    }

    /// Quick init with just a URL — metadata fields are empty.
    /// Used as a first pass so the UI can show filenames immediately.
    init(url: URL) {
        self.id = url
        self.url = url
        self.displayName = url.deletingPathExtension().lastPathComponent
        self.artist = ""
        self.album = ""
        self.trackNumber = nil
        self.duration = 0
    }

    /// Full init with pre-loaded metadata.
    init(url: URL, displayName: String, artist: String, album: String, trackNumber: Int?, duration: TimeInterval) {
        self.id = url
        self.url = url
        self.displayName = displayName
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.duration = duration
    }

    /// Async factory that reads metadata using non-deprecated APIs.
    private static let assetOptions: [String: Any] = [
        AVURLAssetPreferPreciseDurationAndTimingKey: true
    ]

    static func loadMetadata(url: URL) async -> Track {
        let asset = AVURLAsset(url: url, options: assetOptions)

        // Load duration and metadata concurrently
        async let durationResult = asset.load(.duration)
        async let metadataResult = loadAllMetadata(asset: asset)

        let cmTime = (try? await durationResult) ?? .zero
        let duration = cmTime.seconds.isFinite ? cmTime.seconds : 0
        let meta = await metadataResult

        let title = meta.title ?? url.deletingPathExtension().lastPathComponent

        return Track(
            url: url,
            displayName: title,
            artist: meta.artist ?? "",
            album: meta.album ?? "",
            trackNumber: meta.trackNumber,
            duration: duration
        )
    }

    private struct Metadata {
        var title: String?
        var artist: String?
        var album: String?
        var trackNumber: Int?
    }

    private static func loadAllMetadata(asset: AVURLAsset) async -> Metadata {
        var meta = Metadata()

        // Load available formats, then load metadata for each
        guard let formats = try? await asset.load(.availableMetadataFormats) else {
            return meta
        }

        var allItems: [AVMetadataItem] = []
        for format in formats {
            if let items = try? await asset.loadMetadata(for: format) {
                allItems.append(contentsOf: items)
            }
        }

        // Also load common metadata
        if let common = try? await asset.load(.commonMetadata) {
            allItems.append(contentsOf: common)
        }

        // Title
        if let val = await findString(in: allItems, for: .commonIdentifierTitle) {
            meta.title = val
        } else {
            meta.title = await findVorbis(in: allItems, key: "TITLE")
        }

        // Artist
        if let val = await findString(in: allItems, for: .commonIdentifierArtist) {
            meta.artist = val
        } else {
            meta.artist = await findVorbis(in: allItems, key: "ARTIST")
        }

        // Album
        if let val = await findString(in: allItems, for: .commonIdentifierAlbumName) {
            meta.album = val
        } else {
            meta.album = await findVorbis(in: allItems, key: "ALBUM")
        }

        // Track number
        if let numStr = await findVorbis(in: allItems, key: "TRACKNUMBER"),
           let num = Int(numStr) {
            meta.trackNumber = num
        } else if let trackItem = AVMetadataItem.metadataItems(
            from: allItems,
            filteredByIdentifier: .id3MetadataTrackNumber
        ).first ?? AVMetadataItem.metadataItems(
            from: allItems,
            filteredByIdentifier: .iTunesMetadataTrackNumber
        ).first {
            meta.trackNumber = (try? await trackItem.load(.numberValue))?.intValue
        }

        return meta
    }

    private static func findString(
        in items: [AVMetadataItem],
        for identifier: AVMetadataIdentifier
    ) async -> String? {
        guard let item = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: identifier
        ).first else { return nil }
        return try? await item.load(.stringValue)
    }

    private static func findVorbis(in items: [AVMetadataItem], key: String) async -> String? {
        let target = "vorb/\(key)"
        guard let item = items.first(where: { $0.identifier?.rawValue == target }) else { return nil }
        return try? await item.load(.stringValue)
    }
}
