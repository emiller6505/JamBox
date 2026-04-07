import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject var player: PlayerEngine
    @EnvironmentObject private var themeManager: ThemeManager
    @Binding var showArtwork: Bool

    // Scrub state: decouples the slider from live playback during a drag
    // so the user's finger controls the position, not the periodic observer.
    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            transportRow
            if player.currentTrack != nil {
                scrubRow
            }
        }
        .padding()
    }

    // MARK: - Transport Row

    private var transportRow: some View {
        HStack {
            if let artwork = player.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(4)
                    .overlay(PointerCursorView())
                    .onTapGesture { showArtwork = true }
            }

            VStack(alignment: .leading) {
                Text(player.currentTrack?.displayName ?? "Nothing playing")
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

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
    }

    // MARK: - Scrub Row

    private var scrubRow: some View {
        HStack(spacing: 6) {
            // Left label: running position (truncated — shows the current whole second)
            Text(formatTime(displayedPosition))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(themeManager.current.secondaryText ?? Color.secondary)
                .frame(width: 50, alignment: .trailing)

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

            Text(formatTime(player.playbackDuration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(themeManager.current.secondaryText ?? Color.secondary)
                .frame(width: 50, alignment: .leading)
        }
    }

    // MARK: - Scrub State Helpers

    /// The live playback fraction (0..1), driven by the periodic time observer.
    private var liveFraction: Double {
        guard player.playbackDuration > 0 else { return 0 }
        return player.playbackPosition / player.playbackDuration
    }

    /// The time value to display in the left timestamp.
    /// Shows the scrub target during a drag, live position otherwise.
    private var displayedPosition: TimeInterval {
        if isScrubbing {
            return scrubFraction * player.playbackDuration
        }
        return player.playbackPosition
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
