import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selection: Track.ID?
    @State private var showArtwork = false

    var body: some View {
        VStack(spacing: 0) {
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
                    .scrollContentBackground(.hidden)
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
                    appModel.chooseFolder()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 300)
        .background { themeManager.current.backgroundView }
        .tint(themeManager.current.accent)
        .preferredColorScheme(themeManager.current.colorScheme)
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
}
