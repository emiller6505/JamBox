import SwiftUI

// MARK: - Column sort (card 0011)

/// The four user-sortable columns. Leading speaker-icon and "#" columns are
/// intentionally not sortable. `rawValue` is what's persisted to UserDefaults.
private enum SortColumn: String {
    case title, artist, album, duration
}

/// Custom `SortComparator` used with SwiftUI `Table`'s native `sortOrder`
/// binding. Carrying the column identity on the comparator itself lets us
/// (a) get the Table's free column-header-click + sort-direction indicator
/// and (b) implement the iTunes multi-key rules ("preserve album order when
/// sorting by artist", etc.) that a plain `KeyPathComparator` cannot express.
///
/// Direction toggle only flips the primary axis of each column's rules:
/// secondary (album) and tertiary (trackNumber) keys always sort ascending.
private struct TrackComparator: SortComparator, Equatable, Hashable {
    var column: SortColumn
    var order: SortOrder = .forward

    func compare(_ lhs: Track, _ rhs: Track) -> ComparisonResult {
        let result: ComparisonResult
        switch column {
        case .title:
            result = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        case .artist:
            // Primary: artist (direction-flippable).
            let primary = lhs.artist.localizedCaseInsensitiveCompare(rhs.artist)
            if primary != .orderedSame {
                // Apply direction only to the primary axis.
                return (order == .forward) ? primary : primary.reversed
            }
            // Same artist: preserve album-then-track order (always ascending).
            return Self.albumThenTrackCompare(lhs, rhs)
        case .album:
            // Primary: album (direction-flippable).
            let primary = lhs.album.localizedCaseInsensitiveCompare(rhs.album)
            if primary != .orderedSame {
                return (order == .forward) ? primary : primary.reversed
            }
            // Same album: always track-number ascending.
            return Self.trackNumberThenFilenameCompare(lhs, rhs)
        case .duration:
            if lhs.duration < rhs.duration {
                result = .orderedAscending
            } else if lhs.duration > rhs.duration {
                result = .orderedDescending
            } else {
                // Stable tiebreaker by filename (ascending).
                result = Self.filenameCompare(lhs, rhs)
            }
        }
        // title and duration: straightforward direction flip with filename
        // tiebreaker baked into the duration case above.
        return (order == .forward) ? result : result.reversed
    }

    /// Secondary sort used under an artist group: album ascending (case-insensitive),
    /// then track number ascending (nil last), then filename ascending for stability.
    private static func albumThenTrackCompare(_ lhs: Track, _ rhs: Track) -> ComparisonResult {
        let byAlbum = lhs.album.localizedCaseInsensitiveCompare(rhs.album)
        if byAlbum != .orderedSame { return byAlbum }
        return trackNumberThenFilenameCompare(lhs, rhs)
    }

    /// Track-number ascending with nil last, then filename ascending.
    private static func trackNumberThenFilenameCompare(_ lhs: Track, _ rhs: Track) -> ComparisonResult {
        switch (lhs.trackNumber, rhs.trackNumber) {
        case let (l?, r?):
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        case (nil, _?):
            return .orderedDescending // nil sorts last under ascending
        case (_?, nil):
            return .orderedAscending
        case (nil, nil):
            break
        }
        return filenameCompare(lhs, rhs)
    }

    private static func filenameCompare(_ lhs: Track, _ rhs: Track) -> ComparisonResult {
        lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

/// UserDefaults keys for sort persistence (card 0011).
private enum SortDefaults {
    static let columnKey = "jambox.sort.column"
    static let directionKey = "jambox.sort.direction"
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selection: Track.ID?
    @State private var showArtwork = false
    @State private var scrollTargetRow: Int?
    @State private var searchQuery: String = ""
    @FocusState private var searchFieldFocused: Bool

    /// Active sort comparators for the Table's native `sortOrder` binding.
    /// Empty array = no sort (file order from FileScanner). On first launch
    /// with no saved state, this stays empty. Restored from UserDefaults in
    /// `.onAppear`. See card 0011.
    @State private var sortOrder: [TrackComparator] = []

    /// `player.tracks` after the current sort has been applied. This is the
    /// canonical sorted order that gets handed to `player.reorderTracks` so
    /// the playback queue matches the display. When `sortOrder` is empty,
    /// this is just `player.tracks` unchanged.
    private var sortedBase: [Track] {
        guard !sortOrder.isEmpty else { return player.tracks }
        return player.tracks.sorted(using: sortOrder)
    }

    /// Tracks visible after applying sort and then the search query. Filter
    /// is a case-insensitive substring match across title (displayName),
    /// artist, and album. Empty / whitespace query is a no-op.
    /// Important: the filter itself is display-only; the playback queue is
    /// driven by `player.tracks` (which is kept in `sortedBase` order via
    /// `player.reorderTracks`).
    private var filteredTracks: [Track] {
        let base = sortedBase
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { track in
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
                        .foregroundStyle(themeManager.current.secondaryText ?? .secondary)
                    TextField("Search", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(themeManager.current.searchFieldBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(themeManager.current.searchFieldBorder, lineWidth: 1)
                        )
                        .foregroundStyle(themeManager.current.primaryText)
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
                    Table(filteredTracks, selection: $selection, sortOrder: $sortOrder) {
                        // Speaker icon and track-number columns are intentionally
                        // non-sortable per acceptance. They use the value-less
                        // TableColumn initializer so no sort affordance appears.
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

                        // Sortable columns use the (title, value:content:)
                        // initializer so SwiftUI wires the header click and
                        // sort-direction indicator automatically. The `value:`
                        // argument is a TrackComparator carrying our column tag;
                        // the Table sorts `filteredTracks` via this comparator
                        // and publishes the new sortOrder through the binding.
                        TableColumn("Title", sortUsing: TrackComparator(column: .title)) { (track: Track) in
                            cell {
                                Text(track.displayName)
                            }
                        }
                        .width(min: 100, ideal: 250)

                        TableColumn("Artist", sortUsing: TrackComparator(column: .artist)) { (track: Track) in
                            cell {
                                Text(track.artist)
                            }
                        }
                        .width(min: 80, ideal: 180)

                        TableColumn("Album", sortUsing: TrackComparator(column: .album)) { (track: Track) in
                            cell {
                                Text(track.album)
                            }
                        }
                        .width(min: 80, ideal: 180)

                        TableColumn("Duration", sortUsing: TrackComparator(column: .duration)) { (track: Track) in
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
        .onAppear {
            // Restore persisted sort (card 0011). If none saved, stays empty
            // and the table shows file order — matches pre-0011 behavior.
            if sortOrder.isEmpty, let restored = Self.loadPersistedSort() {
                sortOrder = [restored]
                // If tracks are already loaded (e.g. folder restored from
                // bookmark before the view appeared), apply the sort to the
                // player immediately so the queue matches the display.
                if !player.tracks.isEmpty {
                    player.reorderTracks(to: player.tracks.sorted(using: sortOrder))
                }
            }
        }
        .onChange(of: sortOrder) { _, newOrder in
            // User clicked a column header (or we restored state). Persist
            // the new selection and drive the player queue to match the
            // visible order. When `newOrder` is empty (edge case — SwiftUI
            // doesn't currently clear it via clicks, but be defensive) we
            // clear persisted state and leave player.tracks untouched.
            if let first = newOrder.first {
                Self.persistSort(first)
                player.reorderTracks(to: player.tracks.sorted(using: newOrder))
            } else {
                Self.clearPersistedSort()
            }
        }
        .onChange(of: player.tracks) { _, _ in
            // Metadata enrichment (two-phase loading) and folder-watcher
            // diffs mutate `player.tracks` in place. Re-apply the current
            // sort so the display and queue stay consistent. `reorderTracks`
            // is a no-op when the id sequence already matches, which breaks
            // the observer loop it would otherwise cause.
            guard !sortOrder.isEmpty else { return }
            player.reorderTracks(to: player.tracks.sorted(using: sortOrder))
        }
        .onKeyPress(.space) {
            // Don't hijack spacebar while the user is typing in the search
            // field — they're trying to type a literal space, not toggle
            // playback.
            if searchFieldFocused { return .ignored }
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

    // MARK: - Sort persistence (card 0011)

    /// Load the persisted column + direction from UserDefaults.
    /// Returns `nil` when no valid state is stored — first launch, or after
    /// `clearPersistedSort()`. Invalid / unknown values are treated as nil.
    private static func loadPersistedSort() -> TrackComparator? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: SortDefaults.columnKey),
              let column = SortColumn(rawValue: raw) else {
            return nil
        }
        let dirRaw = defaults.string(forKey: SortDefaults.directionKey) ?? "asc"
        let order: SortOrder = (dirRaw == "desc") ? .reverse : .forward
        return TrackComparator(column: column, order: order)
    }

    /// Persist the primary comparator. Only the first entry of the
    /// sortOrder binding is stored — the Table's sortOrder is a single-key
    /// array in practice.
    private static func persistSort(_ comparator: TrackComparator) {
        let defaults = UserDefaults.standard
        defaults.set(comparator.column.rawValue, forKey: SortDefaults.columnKey)
        defaults.set(comparator.order == .reverse ? "desc" : "asc",
                     forKey: SortDefaults.directionKey)
    }

    private static func clearPersistedSort() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SortDefaults.columnKey)
        defaults.removeObject(forKey: SortDefaults.directionKey)
    }
}
