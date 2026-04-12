import SwiftUI

/// A 0%–150% volume slider with a notch at 100%, endpoint labels,
/// double-click-to-reset, and a tooltip during drag.
///
/// Design rationale (card volume):
/// - Range 0.0–1.5 maps to 0%–150%. Default is 1.0 (100%).
/// - A visual notch at the 2/3 position marks "normal" 100%.
/// - Double-clicking anywhere on the slider resets to 100%.
/// - A floating tooltip tracks the cursor during drag, showing "XX%".
/// - 0% / 150% labels sit outside the slider on each end.
struct VolumeSlider: View {
    @Binding var volume: Float
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var isDragging = false
    @State private var dragVolume: Float = 1.0
    @State private var lastClickTime: Date = .distantPast

    /// The volume value to display (drag value while dragging, live otherwise).
    private var displayVolume: Float {
        isDragging ? dragVolume : volume
    }

    /// Fraction 0–1 within the slider track for a given volume (0–1.5).
    private func fraction(for vol: Float) -> CGFloat {
        CGFloat(min(max(vol, 0), 1.5) / 1.5)
    }

    var body: some View {
        HStack(spacing: 4) {
            speakerIcon
            Text("0%")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(themeManager.current.secondaryText ?? Color.secondary)
            sliderTrack
            Text("150%")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(themeManager.current.secondaryText ?? Color.secondary)
        }
        .frame(width: 160)
    }

    // MARK: - Speaker icon

    private var speakerIcon: some View {
        let name: String
        if displayVolume < 0.001 {
            name = "speaker.slash.fill"
        } else if displayVolume <= 0.5 {
            name = "speaker.wave.1.fill"
        } else if displayVolume <= 1.0 {
            name = "speaker.wave.2.fill"
        } else {
            name = "speaker.wave.3.fill"
        }
        return Image(systemName: name)
            .font(.system(size: 12))
            .foregroundStyle(themeManager.current.secondaryText ?? Color.secondary)
            .frame(width: 16)
    }

    // MARK: - Custom slider track

    private var sliderTrack: some View {
        GeometryReader { geo in
            let trackHeight: CGFloat = 4
            let thumbSize: CGFloat = 14
            let trackWidth = geo.size.width
            let midY = geo.size.height / 2

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(themeManager.current.secondaryText?.opacity(0.25) ?? Color.secondary.opacity(0.25))
                    .frame(height: trackHeight)
                    .position(x: trackWidth / 2, y: midY)

                // Filled portion
                Capsule()
                    .fill(themeManager.current.accent)
                    .frame(width: trackWidth * fraction(for: displayVolume), height: trackHeight)
                    .position(x: trackWidth * fraction(for: displayVolume) / 2, y: midY)

                // Notch at 100% (2/3 position)
                Rectangle()
                    .fill(themeManager.current.secondaryText ?? Color.secondary)
                    .frame(width: 1, height: 10)
                    .position(x: trackWidth * (2.0 / 3.0), y: midY)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: trackWidth * fraction(for: displayVolume), y: midY)

                // Tooltip during drag
                if isDragging {
                    Text("\(Int(round(dragVolume * 100)))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        )
                        .position(
                            x: trackWidth * fraction(for: dragVolume),
                            y: midY - 18
                        )
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            // Detect double-click: two mousedowns within 300ms.
                            let now = Date()
                            if now.timeIntervalSince(lastClickTime) < 0.3 {
                                // Double-click → reset to 100%, abort drag.
                                volume = 1.0
                                lastClickTime = .distantPast
                                return
                            }
                            lastClickTime = now
                            isDragging = true
                            dragVolume = volume
                        }
                        let frac = min(max(value.location.x / trackWidth, 0), 1)
                        dragVolume = Float(frac) * 1.5
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        volume = dragVolume
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }
}
