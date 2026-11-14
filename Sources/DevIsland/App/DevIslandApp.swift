import SwiftUI

@main
struct DevIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Used by Scripts/build-app.sh: `DevIsland --export-iconset <folder>` writes the icon PNGs and exits.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--export-iconset"), arguments.indices.contains(index + 1) {
            AppIconRenderer.exportIconset(to: URL(filePath: arguments[index + 1]))
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            AppRoot(model: appDelegate.model) { MenuBarPanel() }
        } label: {
            MenuBarLabel(store: appDelegate.model.store)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DevIsland") { appDelegate.model.windows?.showSettings() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.model.windows?.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// The menu bar icon: outlined when idle, filled while something is live.
struct MenuBarLabel: View {
    let store: ActivityStore

    var body: some View {
        Image(nsImage: store.live.isEmpty ? MenuBarGlyph.idle : MenuBarGlyph.active)
    }
}
