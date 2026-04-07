import Foundation

enum FileScanner {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "flac", "aiff", "aif", "wav", "alac", "aac"
    ]

    /// Quick scan: returns tracks with filenames only (no metadata).
    /// Runs fast because it only touches the filesystem, not audio files.
    static func scanFolder(_ folder: URL) -> [Track] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var tracks: [Track] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                tracks.append(Track(url: fileURL))
            }
        }

        tracks.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return tracks
    }

    /// Load metadata for all tracks asynchronously with bounded concurrency.
    /// Limits to 8 concurrent reads to avoid memory spikes on large libraries.
    static func loadMetadata(for tracks: [Track]) async -> [Track] {
        let maxConcurrency = 8

        return await withTaskGroup(of: Track.self) { group in
            var iterator = tracks.makeIterator()
            var loaded: [Track] = []
            loaded.reserveCapacity(tracks.count)

            // Seed the group with up to maxConcurrency tasks
            for _ in 0..<maxConcurrency {
                guard let track = iterator.next() else { break }
                group.addTask { await Track.loadMetadata(url: track.url) }
            }

            // As each finishes, start the next one
            for await result in group {
                loaded.append(result)
                if let track = iterator.next() {
                    group.addTask { await Track.loadMetadata(url: track.url) }
                }
            }

            loaded.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return loaded
        } // withTaskGroup
    }
}
