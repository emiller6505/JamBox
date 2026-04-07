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
            // Vibrant gradient pulled from the logo: hot pink → deep purple → cyan
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
        case .candy: return Color(red: 1.0, green: 0.42, blue: 0.21)      // bright orange #FF6B35
        }
    }

    /// The color used for secondary text (timestamps, "Nothing playing", etc.).
    /// `nil` means use SwiftUI's `.secondary` semantic color.
    var secondaryText: Color? {
        switch self {
        case .light, .dark: return nil
        case .candy: return Color(red: 1.0, green: 0.88, blue: 0.51)      // candy yellow #FFE082
        }
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
