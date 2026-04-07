import AppKit
import SwiftUI

/// A modifier that installs a double-click handler on the underlying NSTableView
/// backing a SwiftUI Table. SwiftUI doesn't expose double-click natively, so
/// this searches the window's view hierarchy for the NSTableView and sets its
/// doubleAction.
struct TableDoubleClickModifier: ViewModifier {
    let onDoubleClick: (Int) -> Void

    func body(content: Content) -> some View {
        content.overlay {
            TableDoubleClickHelper(onDoubleClick: onDoubleClick)
                .frame(width: 0, height: 0)
        }
    }
}

extension View {
    func onTableDoubleClick(perform action: @escaping (Int) -> Void) -> some View {
        modifier(TableDoubleClickModifier(onDoubleClick: action))
    }
}

// MARK: - Private

private struct TableDoubleClickHelper: NSViewRepresentable {
    let onDoubleClick: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            // Search the entire window for an NSTableView, since the
            // background/overlay NSView may not share a direct ancestor
            // with the AppKit table backing the SwiftUI Table.
            guard let window = nsView.window,
                  let tableView = Self.findTableView(in: window.contentView)
            else {
                return
            }
            tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
            tableView.target = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleClick: onDoubleClick)
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

    final class Coordinator: NSObject {
        let onDoubleClick: (Int) -> Void

        init(onDoubleClick: @escaping (Int) -> Void) {
            self.onDoubleClick = onDoubleClick
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0 else { return }
            onDoubleClick(row)
        }
    }
}
