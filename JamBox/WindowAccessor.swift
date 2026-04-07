import AppKit
import SwiftUI

/// A view modifier that grabs the enclosing NSWindow and applies theme-aware
/// titlebar transparency. SwiftUI has no native API for this on macOS, so we
/// reach into NSWindow.
struct WindowChromeModifier: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        content.background {
            WindowAccessor(theme: theme)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Apply theme-aware window chrome to the enclosing NSWindow.
    func windowChrome(for theme: Theme) -> some View {
        modifier(WindowChromeModifier(theme: theme))
    }
}

// MARK: - Private

private struct WindowAccessor: NSViewRepresentable {
    let theme: Theme

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let theme = self.theme
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titlebarAppearsTransparent = theme.transparentTitleBar
            // .fullSizeContentView lets the contentView extend under the
            // titlebar, so the (safe-area-ignoring) background view in the
            // SwiftUI tree can fill the area behind a transparent titlebar.
            // Harmless when the titlebar is opaque, so leave it on once set.
            if theme.transparentTitleBar {
                window.styleMask.insert(.fullSizeContentView)
            }
        }
    }
}
