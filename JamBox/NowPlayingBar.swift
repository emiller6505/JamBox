import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject var player: PlayerEngine
    /// High-frequency time state lives on its own ObservableObject so that
    /// 4Hz scrub-bar updates don't trigger re-renders of any view that
    /// observes `player` itself (notably `ContentView`, which would otherwise
    /// re-render its `Table` 4 times per second and race with mouse clicks —
    /// see card 0002 and `PlaybackClock` doc in `PlayerEngine.swift`).
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject private var themeManager: ThemeManager
    @Binding var showArtwork: Bool

    /// Called when the user clicks the song title in the bar.
    /// ContentView uses this to scroll the table to that track and highlight it.
    var onTitleClick: ((Track) -> Void)? = nil

    // Scrub state: decouples the slider from live playback during a drag
    // so the user's finger controls the position, not the periodic observer.
    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: artwork, metadata, transport controls
            HStack(spacing: 12) {
                artworkCell
                metadataCell
                transportCell
            }

            // Row 2: scrub bar — timestamps sit naturally adjacent to the slider
            // so there's no dead space between the slider end and the timestamp.
            // Both rows still align at the leading edge (artwork left == left
            // timestamp left) and the trailing edge (transport right == right
            // timestamp right) because each row is padded by the same amount.
            if player.currentTrack != nil {
                HStack(spacing: 6) {
                    leftTimestampCell
                    sliderCell
                    rightTimestampCell
                }
            }
        }
        .padding()
        .background(themeManager.current.chromeBackground)
    }

    // MARK: - Top row cells

    @ViewBuilder
    private var artworkCell: some View {
        if let artwork = player.currentArtwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .cornerRadius(4)
                .overlay(PointerCursorView())
                .onTapGesture { showArtwork = true }
        } else {
            // Placeholder so the column has a consistent width even with no track.
            Color.clear.frame(width: 60, height: 60)
        }
    }

    @ViewBuilder
    private var metadataCell: some View {
        if let track = player.currentTrack {
            // Font sizes are intentionally fixed pt (not Theme tokens) per
            // card 0013 design spec. Card 0009 (Dynamic Type) in backlog is
            // the proper home for a JamBox-level text-size multiplier; it
            // can wrap these base numbers in a multiplier later without
            // reinventing the hierarchy.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .frame(width: 14)
                    Text(track.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .overlay(PointerCursorView())
                        .onTapGesture { onTitleClick?(track) }
                }
                if !track.artist.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .frame(width: 14)
                        Text(track.artist)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .regular))
                }
                if !track.album.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "opticaldisc.fill")
                            .frame(width: 14)
                        Text(track.album)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .regular))
                }
                // Format badge — card 0013. Hide entire line unless every
                // field is known (per "hide-the-whole-badge" rule from the
                // design spec). Quietest line in the hierarchy: secondary
                // color, 11 pt monospaced, waveform glyph in the gutter.
                if let format = player.currentFormat {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .frame(width: 14)
                        Text(format.visual)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(themeManager.current.secondaryText ?? Color.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(format.voiceOver)
                }
            }
            .foregroundStyle(themeManager.current.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Nothing playing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(themeManager.current.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transportCell: some View {
        HStack(spacing: 8) {
            Button(action: { player.skipBackward() }) {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }

            Button(action: { player.togglePlayPause() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            Button(action: { player.skipForward() }) {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom row (scrub) cells

    private var leftTimestampCell: some View {
        Text(formatTime(displayedPosition))
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(themeManager.current.secondaryText ?? Color.secondary)
    }

    private var sliderCell: some View {
        Slider(
            value: scrubBinding,
            in: 0...1
        ) { editing in
            if editing {
                isScrubbing = true
                scrubFraction = liveFraction
            } else {
                guard isScrubbing else { return } // guard against duplicate onEditingChanged
                player.seek(to: scrubFraction)
                isScrubbing = false
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rightTimestampCell: some View {
        Text(formatTime(clock.duration))
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(themeManager.current.secondaryText ?? Color.secondary)
    }

    // MARK: - Scrub State Helpers

    /// The live playback fraction (0..1), driven by the periodic time observer.
    private var liveFraction: Double {
        guard clock.duration > 0 else { return 0 }
        return clock.position / clock.duration
    }

    /// The time value to display in the left timestamp.
    /// Shows the scrub target during a drag, live position otherwise.
    private var displayedPosition: TimeInterval {
        if isScrubbing {
            return scrubFraction * clock.duration
        }
        return clock.position
    }

    /// A binding that reads from the live position when idle,
    /// but reads/writes the local scrub fraction during a drag.
    /// The setter only fires on user interaction — SwiftUI does not
    /// call it when the getter's value changes from the timer.
    private var scrubBinding: Binding<Double> {
        Binding(
            get: { isScrubbing ? scrubFraction : liveFraction },
            set: { scrubFraction = $0 }
        )
    }

    // MARK: - Time Formatting

    /// Formats a running position as M:SS (truncated — shows current whole second).
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// A transparent NSView overlay that sets a pointing-hand cursor via cursor rects.
/// Used as an .overlay() on clickable elements. The cursor rect is managed by
/// AppKit's window server, so it won't flicker like SwiftUI's onHover approach.
private struct PointerCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TrackingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private class TrackingView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
