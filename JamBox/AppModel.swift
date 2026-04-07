import AppKit
import Combine
import Foundation

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

    init() {
        self.mediaKeys = MediaKeyController(player: player)
        folderWatcher.onChange = { [weak self] in
            DispatchQueue.main.async { self?.scheduleRescan() }
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
