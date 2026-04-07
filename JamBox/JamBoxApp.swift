import SwiftUI

@main
struct JamBoxApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(appModel)
                .environmentObject(appModel.player)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Picker("Theme", selection: themeBinding) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }
        }
    }

    /// A binding that reads/writes ThemeManager.current. We can't bind directly
    /// to a computed property, so we wrap it explicitly.
    private var themeBinding: Binding<Theme> {
        Binding(
            get: { themeManager.current },
            set: { themeManager.current = $0 }
        )
    }
}
