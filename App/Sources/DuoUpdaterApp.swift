import SwiftUI

@main
struct DuoUpdaterApp: App {
    @State private var model = AppListModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            // Badge the menu bar icon with the number of pending updates. Uses
            // `badgeCount` (not `updateCount`) so a refresh's mid-flight `.unknown`
            // rows don't flicker the badge to zero and back.
            if model.badgeCount > 0 {
                Image(systemName: "\(min(model.badgeCount, 50)).circle.fill")
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .menuBarExtraStyle(.window)

        // The unified workbench — opened from the popover, lives on its own so it
        // survives the popover dismissing. One window now holds release notes,
        // per-app traffic, and Settings (via a toolbar gear). Shares the one model.
        Window("Duo Updater", id: WorkbenchWindowView.windowID) {
            WorkbenchWindowView(model: model)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)

        // Settings as a *regular* Window, not a `Settings` scene: that specialized
        // scene injects its own centered-title chrome, which collides with a
        // NavigationSplitView (traffic lights overlapping the sidebar, oversized
        // top padding). A plain Window hosts the split view cleanly — same as the
        // workbench. Binds to the same Preferences the model reads on every check.
        Window("Settings", id: SettingsView.windowID) {
            SettingsView(prefs: model.prefs, model: model)
        }
        .defaultSize(width: 680, height: 460)
        .windowResizability(.contentMinSize)
        .commands {
            // Restore the ⌘, "Settings…" app-menu item now that there's no Settings
            // scene to provide it automatically.
            SettingsCommand()
        }
    }
}

/// The app-menu "Settings…" command (⌘,), pointing at our Window-based settings.
private struct SettingsCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: SettingsView.windowID) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}
