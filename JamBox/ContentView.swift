import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selection: Track.ID?
    @State private var showArtwork = false
    @State private var scrollTargetRow: Int?
    @State private var searchQuery: String = ""
    @FocusState private var searchFieldFocused: Bool

    /// Tracks visible after applying the search query. Filter is a
    /// case-insensitive substring match across title (displayName),
    /// artist, and album. Empty / whitespace query is a no-op.
    /// Important: this is for *display only*. `player.tracks` and the
    /// playback queue are never mutated by search.
    private var filteredTracks: [Track] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return player.tracks }
        return player.tracks.filter { track in
            track.displayName.lowercased().contains(q)
                || track.artist.lowercased().contains(q)
                || track.album.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top chrome: search field pinned to the right. Hidden when
            // there are no tracks so it doesn't float over the empty state.
            if !player.tracks.isEmpty {
                HStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($searchFieldFocused)
                        .onExitCommand {
                            searchQuery = ""
                            searchFieldFocused = false
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // Hidden Cmd-F shortcut to focus the search field. Placed as a
            // zero-size button so its keyboardShortcut is registered window-wide
            // without affecting layout.
            Button("") { searchFieldFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

            ZStack {
                // Track list (or empty/loading state)
                if player.tracks.isEmpty && !appModel.isLoading {
                    VStack {
                        Spacer()
                        Text("No folder selected")
                            .foregroundStyle(.secondary)
                        Button("Choose Folder") {
                            appModel.chooseFolder()
                        }
                        .padding(.top, 8)
                        Spacer()
                    }
                } else if appModel.isLoading && player.tracks.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Scanning...")
                        Spacer()
                    }
                } else {
                    Table(filteredTracks, selection: $selection) {
                        TableColumn("") { (track: Track) in
                            cell {
                                if track.id == player.currentTrack?.id {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(themeManager.current.accent)
                                }
                            }
                        }
                        .width(20)

                        TableColumn("#") { (track: Track) in
                            cell {
                                Text(track.trackNumberString)
                                    .monospacedDigit()
                            }
                        }
                        .width(min: 30, ideal: 35, max: 50)

                        TableColumn("Title") { (track: Track) in
                            cell {
                                Text(track.displayName)
                            }
                        }
                        .width(min: 100, ideal: 250)

                        TableColumn("Artist") { (track: Track) in
                            cell {
                                Text(track.artist)
                            }
                        }
                        .width(min: 80, ideal: 180)

                        TableColumn("Album") { (track: Track) in
                            cell {
                                Text(track.album)
                            }
                        }
                        .width(min: 80, ideal: 180)

                        TableColumn("Duration") { (track: Track) in
                            cell {
                                Text(track.durationString)
                                    .monospacedDigit()
                            }
                        }
                        .width(min: 50, ideal: 60, max: 80)
                    }
                    .onTableDoubleClick { row in
                        // `row` is an index into the filtered view. Translate
                        // it back to an index into `player.tracks` so the
                        // playback queue (which mirrors `player.tracks`) starts
                        // at the right position.
                        let visible = filteredTracks
                        guard row < visible.count else { return }
                        let id = visible[row].id
                        guard let trueIndex = player.tracks.firstIndex(where: { $0.id == id }) else { return }
                        player.play(startingAt: trueIndex)
                    }
                    .contextMenu(forSelectionType: Track.ID.self) { ids in
                        // v1: operate on a single row (the right-clicked row).
                        // AppKit's NSTableView selects the right-clicked row
                        // before the menu fires if it wasn't already selected,
                        // so `ids` reflects that. If multiple rows are selected
                        // we intentionally act on the first one.
                        if let id = ids.first,
                           let index = player.tracks.firstIndex(where: { $0.id == id }) {
                            let track = player.tracks[index]
                            Button("Play") {
                                player.play(startingAt: index)
                            }
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([track.url])
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .alternatingRowBackgrounds(themeManager.current.alternatingRowBackgrounds)
                    .tint(themeManager.current.tableTintOverride ?? themeManager.current.accent)
                    .onTableScroll(rowIndex: $scrollTargetRow)
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

            NowPlayingBar(player: player, clock: player.clock, showArtwork: $showArtwork) { track in
                selection = track.id
                if let row = player.tracks.firstIndex(where: { $0.id == track.id }) {
                    scrollTargetRow = row
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Change Folder") {
                    appModel.chooseFolder()
                }
            }
        }
        .toolbarBackground(
            themeManager.current.transparentTitleBar ? .hidden : .automatic,
            for: .windowToolbar
        )
        .frame(minWidth: 500, minHeight: 300)
        .background {
            themeManager.current.backgroundView
                .ignoresSafeArea()
        }
        .tint(themeManager.current.accent)
        .preferredColorScheme(themeManager.current.colorScheme)
        .windowChrome(for: themeManager.current)
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

    /// Applies the theme's primary text color to a cell's content. Used for
    /// every Table cell — `foregroundStyle` doesn't reliably propagate from
    /// the Table view down to cell content, so we apply it per-cell.
    @ViewBuilder
    private func cell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(themeManager.current.primaryText)
    }
}
