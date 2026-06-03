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

        // The roomy companion window — opened from the popover, lives on its own
        // so it survives the popover dismissing. Shares the one model instance.
        Window("Changelog", id: ChangelogWindowView.windowID) {
            ChangelogWindowView(model: model)
        }
        .defaultSize(width: 860, height: 560)
        .windowResizability(.contentMinSize)

        // Per-app download traffic, tracked to the byte. Its own window so it
        // survives the popover dismissing; shares the one model instance.
        Window("Traffic", id: TrafficWindowView.windowID) {
            TrafficWindowView(model: model)
        }
        .defaultSize(width: 720, height: 520)
        .windowResizability(.contentMinSize)

        // Standard macOS Settings window (⌘,). Binds to the same Preferences the
        // model reads on every check.
        Settings {
            SettingsView(prefs: model.prefs, model: model)
        }
    }
}
