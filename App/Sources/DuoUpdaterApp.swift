import SwiftUI
import AppKit

@main
struct DuoUpdaterApp: App {
    @State private var model = AppListModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        // First-run onboarding: grant the permissions Duo Updater needs up front
        // instead of discovering them mid-update. Auto-opened once by `MenuBarLabel`;
        // re-openable from Settings → Permissions → "Run Setup Again…".
        Window("Welcome to Duo Updater", id: WelcomeView.windowID) {
            WelcomeView(model: model)
        }
        .defaultSize(width: 560, height: 700)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)  // chromeless, setup-assistant feel

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
            SettingsCommand(model: model)
        }
    }
}

/// The menu-bar status icon, and the one launch-time hook a menu-bar app reliably
/// gets: the label View renders as soon as the status item appears (before any popover
/// opens), so its `.task` is where we trigger first-run onboarding.
private struct MenuBarLabel: View {
    @Bindable var model: AppListModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            // Badge the icon with the number of pending updates. Uses `badgeCount`
            // (not `updateCount`) so a refresh's mid-flight `.unknown` rows don't
            // flicker the badge to zero and back.
            if model.badgeCount > 0 {
                Image(systemName: "\(min(model.badgeCount, 50)).circle.fill")
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .task {
            // Runs once at launch. Show onboarding only the first time, then never
            // again (the user can re-open it from Settings).
            AppDockBadge.syncSoon(count: model.badgeCount)
            if hasCompletedOnboarding {
                AppUpdater.shared.start()
                return
            }
            openWindow(id: WelcomeView.windowID)
            model.surfaceWindow(sceneID: WelcomeView.windowID)
        }
        .onChange(of: model.badgeCount) { _, count in
            AppDockBadge.sync(count: count)
            AppDockBadge.syncSoon(count: count)
        }
    }
}

/// The app-menu "Settings…" command (⌘,), pointing at our Window-based settings.
private struct SettingsCommand: Commands {
    let model: AppListModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: SettingsView.windowID)
                model.surfaceWindow(sceneID: SettingsView.windowID)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button("Check for DuoUpdater Updates…") {
                AppUpdater.shared.checkForUpdates()
            }
            .disabled(!AppUpdater.shared.canCheckForUpdates)
        }
    }
}
