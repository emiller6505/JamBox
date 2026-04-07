import AppKit
import SwiftUI

/// A modifier that lets a SwiftUI Table be scrolled to a specific row.
/// SwiftUI's `ScrollViewReader` doesn't work with macOS `Table` (which is
/// backed by NSTableView, not a SwiftUI ScrollView), so we walk the window
/// hierarchy to find the underlying NSTableView and call
/// `scrollRowToVisible(_:)` directly.
///
/// Usage:
/// ```
/// @State var scrollTarget: Int?
/// Table(...).onTableScroll(rowIndex: $scrollTarget)
/// // later: scrollTarget = 42  → table scrolls to row 42
/// ```
/// The binding is reset to nil after each scroll so consecutive scrolls
/// to the same row still trigger.
struct TableScrollerModifier: ViewModifier {
    @Binding var rowIndex: Int?

    func body(content: Content) -> some View {
        content.overlay {
            // Pass the value (not the binding) so SwiftUI sees a real change
            // when rowIndex updates and re-renders the helper. NSViewRepresentable's
            // updateNSView only fires when the wrapping struct's stored values
            // differ — and Bindings hash by reference identity, so a binding alone
            // wouldn't trigger an update.
            TableScrollerHelper(targetRow: rowIndex) {
                rowIndex = nil
            }
            .frame(width: 0, height: 0)
        }
    }
}

extension View {
    func onTableScroll(rowIndex: Binding<Int?>) -> some View {
        modifier(TableScrollerModifier(rowIndex: rowIndex))
    }
}

// MARK: - Private

private struct TableScrollerHelper: NSViewRepresentable {
    let targetRow: Int?
    let onScrolled: () -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let target = targetRow else { return }

        // Defer to the next runloop tick so the NSView is in the window hierarchy
        // and the table has finished any pending layout from the same render pass.
        DispatchQueue.main.async {
            guard let window = nsView.window,
                  let tableView = Self.findTableView(in: window.contentView)
            else { return }

            // Clamp to a valid row before calling AppKit (negative or
            // out-of-range values would crash NSTableView).
            let row = min(max(target, 0), tableView.numberOfRows - 1)
            if row >= 0 {
                tableView.scrollRowToVisible(row)
            }

            // Reset the parent's binding so the next scroll-to-same-row still fires.
            onScrolled()
        }
    }

    /// Depth-first search down the view tree to find an NSTableView.
    private static func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tableView = view as? NSTableView {
            return tableView
        }
        for subview in view.subviews {
            if let found = findTableView(in: subview) {
                return found
            }
        }
        return nil
    }
}
