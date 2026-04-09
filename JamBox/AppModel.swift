import AppKit
import Combine
import Foundation

/// Persisted playback state (card 0012: resume on launch).
///
/// Intentionally tiny: a single track URL + position in seconds. The `version`
/// field exists so future schema changes can be detected — any decode that
/// lands on a version != `currentVersion` is treated as "no saved state" and
/// silently cleared. That's cheaper than writing a migration path for a
/// feature where "forget and start fresh" is an acceptable failure mode.
private struct PlaybackState: Codable {
    static let currentVersion = 1
    var version: Int
    var trackURL: URL
    var position: TimeInterval
}

/// Owns everything that needs to survive across window close/reopen:
/// the player engine, the folder watcher, the security-scoped folder URL,
/// and the loading/rescan logic.
///
/// SwiftUI's `@StateObject` in a View only persists for that view's lifetime.
/// On macOS, closing a window destroys the view hierarchy, which would also
/// destroy any state owned by the view. By owning all of this here and
/// exposing it as a top-level `@StateObject` in `JamBoxApp`, the player keeps
/// playing through window close, and the UI is restored when the window
/// reopens.
@MainActor
final class AppModel: ObservableObject {
    /// The player engine. Exposed as a `let` since its identity never changes —
    /// it's the same instance for the entire app lifetime. SwiftUI views observe
    /// it directly via `@EnvironmentObject<PlayerEngine>` so its `@Published`
    /// updates trigger renders without going through AppModel.
    let player = PlayerEngine()

    /// Bridges the player to macOS media keys, Control Center, and the lock
    /// screen. Held as a strong reference so its observers stay alive.
    private let mediaKeys: MediaKeyController

    /// True while the initial filesystem scan or metadata enrichment is running.
    @Published var isLoading = false

    /// The folder currently being watched. nil if no folder has been chosen.
    @Published private(set) var watchedFolderURL: URL?

    private let folderWatcher = FolderWatcher()
    private var activeScopedURL: URL?
    private var rescanTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private let bookmarkKey = "musicFolderBookmark"
    private let playbackStateKey = "jambox.playback.state"

    /// Throttled save timer (card 0012). Only ticks while `player.isPlaying`
    /// is true. Recreated on each play→pause→play cycle.
    private var saveTimer: Timer?
    private let saveTimerInterval: TimeInterval = 5

    init() {
        self.mediaKeys = MediaKeyController(player: player)
        folderWatcher.onChange = { [weak self] in
            DispatchQueue.main.async { self?.scheduleRescan() }
        }

        // Card 0012: throttled save while playing. When playback starts we
        // schedule a repeating 5s timer that persists current position; when
        // it pauses (or stops) we invalidate it. The save-on-quit path (below)
        // runs unconditionally regardless of timer state.
        player.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.handleIsPlayingChanged(isPlaying)
            }
            .store(in: &cancellables)

        // Card 0012: save on quit. `willTerminateNotification` fires once on
        // the main thread during app termination; by then the user's intent
        // is final, so we write unconditionally — even if playback is paused —
        // so the next launch can resume the last-shown track.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification-center closure isn't MainActor-isolated at the
            // type-system level even though the `.main` queue guarantees we
            // *are* on the main thread. Hop explicitly so the compiler is
            // satisfied and the MainActor-isolated `savePlaybackState` call
            // is legal.
            MainActor.assumeIsolated {
                self?.savePlaybackState()
            }
        }

        loadSavedFolder()
    }
    // No deinit: AppModel is owned by JamBoxApp as a top-level @StateObject,
    // so it lives for the entire app process. Cleanup happens in chooseFolder()
    // before switching folders.

    // MARK: - Folder Selection

    /// Show the system folder picker. If the user selects a folder, switch
    /// to it and start watching.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your music folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Release previous security-scoped access and watcher before switching
        folderWatcher.stop()
        activeScopedURL?.stopAccessingSecurityScopedResource()
        activeScopedURL = nil

        saveBookmark(for: url)
        loadFolder(url)
    }

    /// Restore the last-used folder from a saved security-scoped bookmark.
    /// Called automatically on app launch.
    private func loadSavedFolder() {
        let data = UserDefaults.standard.data(forKey: bookmarkKey) ?? Data()
        guard !data.isEmpty else { return }
        guard let url = resolveBookmark(from: data) else { return }
        loadFolder(url)
    }

    private func loadFolder(_ url: URL) {
        // Cancel any in-flight enrichment from a previous folder. Without this,
        // a stale enrichment task would land on the wrong tracks list when
        // the user switches folders mid-scan.
        metadataTask?.cancel()

        isLoading = true
        watchedFolderURL = url

        // Quick scan: filenames only, fast, shows list immediately
        let quickTracks = FileScanner.scanFolder(url)
        player.loadTracks(quickTracks)

        // Card 0012: attempt to restore the last playback position. This MUST
        // run synchronously on the same MainActor tick as `loadTracks` so the
        // now-playing bar is populated before any user input (space bar, media
        // key, double-click) can land. The async duration-clamp inside
        // `player.resume` is fine — by the time it suspends, `currentTrack`
        // and `clock.position` are already seeded.
        tryRestorePlayback(within: quickTracks)

        // Enrich metadata in the background. Store the task so we can cancel it
        // if the user switches folders before it completes.
        metadataTask = Task { [weak self] in
            let enriched = await FileScanner.loadMetadata(for: quickTracks)
            if Task.isCancelled { return }
            guard let self else { return }
            self.player.updateMetadata(enriched)
            self.isLoading = false
        }

        folderWatcher.start(watching: url)
    }

    // MARK: - Filesystem Watching

    /// Debounced rescan: cancel any pending rescan, wait 500ms, then rescan.
    /// This coalesces bursts of FSEvents (e.g. during a multi-file copy).
    private func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            await self?.performRescan()
        }
    }

    /// Run a fresh scan, diff against current tracks, apply changes,
    /// then enrich any new tracks with metadata.
    /// Checks Task.isCancelled at every await point so a newer rescan can
    /// preempt an in-flight one cleanly.
    private func performRescan() async {
        guard let url = watchedFolderURL else { return }
        if Task.isCancelled { return }

        let freshTracks = await Task.detached(priority: .utility) {
            FileScanner.scanFolder(url)
        }.value
        if Task.isCancelled { return }

        let currentURLs = Set(player.tracks.map { $0.url })
        let freshURLs = Set(freshTracks.map { $0.url })

        let addedURLs = freshURLs.subtracting(currentURLs)
        let removedURLs = currentURLs.subtracting(freshURLs)

        if addedURLs.isEmpty && removedURLs.isEmpty { return }

        let added = freshTracks.filter { addedURLs.contains($0.url) }

        if Task.isCancelled { return }
        player.applyTrackDiff(added: added, removedURLs: removedURLs)

        // Enrich the newly added tracks with metadata in the background
        if !added.isEmpty {
            if Task.isCancelled { return }
            let enriched = await FileScanner.loadMetadata(for: added)
            if Task.isCancelled { return }
            player.updateMetadata(enriched)
        }
    }

    // MARK: - Playback State Persistence (card 0012)

    /// Read the saved playback state. Returns nil (and silently clears the
    /// persisted blob) on any of: missing data, decode failure, schema
    /// version mismatch. The caller treats nil as "nothing to resume" and
    /// does not surface an error — the resume feature is invisible by design.
    private func loadPlaybackState() -> PlaybackState? {
        guard let data = UserDefaults.standard.data(forKey: playbackStateKey) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(PlaybackState.self, from: data) else {
            clearPlaybackState()
            return nil
        }
        guard decoded.version == PlaybackState.currentVersion else {
            clearPlaybackState()
            return nil
        }
        return decoded
    }

    /// Snapshot the currently-playing track + live position and write it to
    /// UserDefaults. If nothing is playing, the saved state is cleared — we
    /// don't keep a stale entry around. Called by the throttled 5s timer
    /// (while playing) and by the willTerminate handler (unconditionally).
    fileprivate func savePlaybackState() {
        guard let track = player.currentTrack else {
            clearPlaybackState()
            return
        }
        let state = PlaybackState(
            version: PlaybackState.currentVersion,
            trackURL: track.url,
            position: player.clock.position
        )
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(encoded, forKey: playbackStateKey)
    }

    private func clearPlaybackState() {
        UserDefaults.standard.removeObject(forKey: playbackStateKey)
    }

    /// Attempt the silent-resume flow. All failure modes are intentionally
    /// quiet: missing file, URL not in the restored folder, schema drift,
    /// decode error → clear persisted state and return. No modal, no log.
    private func tryRestorePlayback(within quickTracks: [Track]) {
        guard let saved = loadPlaybackState() else { return }

        // File-still-exists check. We do NOT try to find the file by name
        // inside the folder — "track identity by content hash" is a future
        // feature. If the exact URL is gone, give up silently.
        guard FileManager.default.fileExists(atPath: saved.trackURL.path) else {
            clearPlaybackState()
            return
        }

        // URL must match a track in the current folder. If the user switched
        // folders between sessions (or manually poked the bookmark), the
        // saved URL may still exist on disk but won't be in `quickTracks`.
        guard let index = quickTracks.firstIndex(where: { $0.url == saved.trackURL }) else {
            clearPlaybackState()
            return
        }

        // Hand off to the engine. `resume` seeds `currentTrack` + `clock`
        // synchronously, then asynchronously validates duration and calls
        // `onFailure` if the asset is unresumable.
        player.resume(trackIndex: index, position: saved.position) { [weak self] in
            self?.clearPlaybackState()
        }
    }

    /// Start/stop the throttled save timer in response to play/pause.
    /// The 5s cadence is a compromise between "don't lose more than a few
    /// seconds on a hard crash" and "don't hammer UserDefaults." The timer
    /// is intentionally NOT running while playback is paused — there's
    /// nothing to capture, and the willTerminate handler covers the final
    /// paused state on quit.
    private func handleIsPlayingChanged(_ isPlaying: Bool) {
        if isPlaying {
            guard saveTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: saveTimerInterval, repeats: true) { [weak self] _ in
                // Block-based timer hops to the RunLoop's thread (main, here)
                // and invokes our MainActor-isolated save directly.
                MainActor.assumeIsolated {
                    self?.savePlaybackState()
                }
            }
            saveTimer = timer
        } else {
            saveTimer?.invalidate()
            saveTimer = nil
        }
    }

    // MARK: - Security-Scoped Bookmarks

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            print("[JamBox] Failed to save bookmark: \(error)")
        }
    }

    private func resolveBookmark(from data: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                print("[JamBox] Failed to access security-scoped resource")
                return nil
            }
            activeScopedURL = url
            if isStale {
                saveBookmark(for: url)
            }
            return url
        } catch {
            print("[JamBox] Failed to resolve bookmark: \(error)")
            return nil
        }
    }
}
