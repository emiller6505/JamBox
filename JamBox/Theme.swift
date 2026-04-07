import SwiftUI

/// Visual theme for the app. Light is the default.
enum Theme: String, CaseIterable, Identifiable {
    case light, dark, candy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .candy: return "Candy"
        }
    }

    /// The color scheme to apply to system controls (sliders, table chrome, etc.).
    /// `nil` means inherit the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .candy: return .dark   // dark scheme so light text/system controls are visible on the bright background
        }
    }

    /// The window background view. Returns a `some View` so a theme can use
    /// any background — solid color, gradient, image, etc.
    @ViewBuilder
    var backgroundView: some View {
        switch self {
        case .light:
            Color.clear
        case .dark:
            Color(red: 0.118, green: 0.118, blue: 0.118)   // VSCode editor #1E1E1E
        case .candy:
            // Vibrant three-stop gradient: hot pink → deep purple → cyan
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.12, blue: 0.56),  // hot pink #FF1F8F (top)
                    Color(red: 0.55, green: 0.10, blue: 0.55),  // deep purple #8C198C (middle)
                    Color(red: 0.25, green: 0.71, blue: 1.00)   // electric cyan #3FB5FF (bottom)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// The accent color used for the play indicator, slider, focus rings, etc.
    var accent: Color {
        switch self {
        case .light: return .accentColor
        case .dark: return Color(red: 0.0, green: 0.478, blue: 0.8)       // VSCode blue #007ACC
        case .candy: return Color(red: 1.0, green: 0.89, blue: 0.30)      // lemon yellow #FFE34D
        }
    }

    /// The color used for secondary text (timestamps, "Nothing playing", etc.).
    /// `nil` means use SwiftUI's `.secondary` semantic color.
    var secondaryText: Color? {
        switch self {
        case .light, .dark: return nil
        case .candy: return Color.white.opacity(0.7)
        }
    }

    /// Primary text color for track titles, artist, etc.
    /// Candy uses pure white for max contrast against the gradient.
    var primaryText: Color {
        switch self {
        case .light, .dark: return .primary
        case .candy: return .white
        }
    }

    /// Override tint applied to the Table specifically, used to recolor the
    /// system row selection highlight without affecting other accents (scrub
    /// bar, play indicator, etc.). `nil` means inherit the parent tint.
    var tableTintOverride: Color? {
        switch self {
        case .light, .dark: return nil
        case .candy: return .white
        }
    }

    /// Whether the Table should draw alternating row backgrounds. Disabled for
    /// candy so the gradient background shows through cleanly.
    var alternatingRowBackgrounds: AlternatingRowBackgroundBehavior {
        self == .candy ? .disabled : .enabled
    }

    /// Background for chrome strips (now playing bar). Returns AnyShapeStyle so
    /// themes can use a Color, Material, gradient, etc.
    var chromeBackground: AnyShapeStyle {
        switch self {
        case .light, .dark: return AnyShapeStyle(Color.clear)
        case .candy: return AnyShapeStyle(Color.white.opacity(0.12))
        }
    }

    /// Whether the window's titlebar should be transparent so the background
    /// view shows through to the top edge.
    var transparentTitleBar: Bool {
        self == .candy
    }
}

/// Owns the current theme and persists it across launches.
@MainActor
final class ThemeManager: ObservableObject {
    @AppStorage("theme") private var stored: String = Theme.light.rawValue

    var current: Theme {
        get { Theme(rawValue: stored) ?? .light }
        set {
            objectWillChange.send()
            stored = newValue.rawValue
        }
    }
}
