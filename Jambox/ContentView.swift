import SwiftUI

struct ContentView: View {
    @StateObject private var player = PlayerEngine()
    @AppStorage("musicFolderBookmark") private var bookmarkData: Data = Data()
    @State private var selection: Track.ID?
    @State private var isLoading = false
    @State private var activeScopedURL: URL?
    @State private var showArtwork = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Track list (or empty/loading state)
                if player.tracks.isEmpty && !isLoading {
                    VStack {
                        Spacer()
                        Text("No folder selected")
                            .foregroundStyle(.secondary)
                        Button("Choose Folder") {
                            chooseFolder()
                        }
                        .padding(.top, 8)
                        Spacer()
                    }
                } else if isLoading && player.tracks.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Scanning...")
                        Spacer()
                    }
                } else {
                    Table(player.tracks, selection: $selection) {
                        TableColumn("") { (track: Track) in
                            if track.id == player.currentTrack?.id {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .width(20)

                        TableColumn("#") { (track: Track) in
                            Text(track.trackNumberString)
                                .monospacedDigit()
                        }
                        .width(min: 30, ideal: 35, max: 50)

                        TableColumn("Title") { (track: Track) in
                            Text(track.displayName)
                        }
                        .width(min: 100, ideal: 250)

                        TableColumn("Artist") { (track: Track) in
                            Text(track.artist)
                        }
                        .width(min: 80, ideal: 180)

                        TableColumn("Album") { (track: Track) in
                            Text(track.album)
                        }
                        .width(min: 80, ideal: 180)

                        TableColumn("Duration") { (track: Track) in
                            Text(track.durationString)
                                .monospacedDigit()
                        }
                        .width(min: 50, ideal: 60, max: 80)
                    }
                    .onTableDoubleClick { row in
                        guard row < player.tracks.count else { return }
                        player.play(startingAt: row)
                    }
                }

                // Album art overlay
                if showArtwork, let artwork = player.currentArtwork {
                    Color.black.opacity(0.85)
                        .overlay {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(32)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button(action: { showArtwork = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                        }
                        .onTapGesture { showArtwork = false }
                        .transition(.opacity)
                }
            }

            Divider()

            NowPlayingBar(player: player, showArtwork: $showArtwork)
        }
        .toolbar {
            ToolbarItem {
                Button("Change Folder") {
                    chooseFolder()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 300)
        .onAppear {
            loadSavedFolder()
        }
        .onChange(of: player.currentArtwork == nil) { _, isNil in
            if isNil { showArtwork = false }
        }
        .onKeyPress(.space) {
            player.togglePlayPause()
            return .handled
        }
        .onKeyPress(.escape) {
            if showArtwork {
                showArtwork = false
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            guard let id = selection,
                  let index = player.tracks.firstIndex(where: { $0.id == id })
            else { return .ignored }
            player.play(startingAt: index)
            return .handled
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your music folder"

        if panel.runModal() == .OK, let url = panel.url {
            // Release previous security-scoped access before switching
            activeScopedURL?.stopAccessingSecurityScopedResource()
            activeScopedURL = nil
            saveBookmark(for: url)
            loadFolder(url)
        }
    }

    private func loadSavedFolder() {
        guard !bookmarkData.isEmpty else { return }
        guard let url = resolveBookmark() else { return }
        loadFolder(url)
    }

    private func loadFolder(_ url: URL) {
        isLoading = true
        selection = nil
        showArtwork = false
        // Quick scan: filenames only, fast, shows list immediately
        let quickTracks = FileScanner.scanFolder(url)
        player.loadTracks(quickTracks)

        // Then load metadata in background and swap in without disturbing playback
        Task {
            let enriched = await FileScanner.loadMetadata(for: quickTracks)
            await MainActor.run {
                player.updateMetadata(enriched)
                isLoading = false
            }
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
            bookmarkData = data
        } catch {
            print("[Jambox] Failed to save bookmark: \(error)")
        }
    }

    private func resolveBookmark() -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                print("[Jambox] Failed to access security-scoped resource")
                return nil
            }
            activeScopedURL = url
            // If the bookmark is stale (e.g. folder was renamed), refresh it
            if isStale {
                saveBookmark(for: url)
            }
            return url
        } catch {
            print("[Jambox] Failed to resolve bookmark: \(error)")
            return nil
        }
    }
}
