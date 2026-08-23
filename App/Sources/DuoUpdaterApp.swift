import SwiftUI
import AppKit
import DuoUpdaterCore

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
        // survives the popover dismissing. Holds release notes and Settings (via a
        // toolbar gear); download traffic moved to its own window. Shares the model.
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

        // The release log — a global, chronological feed of every release the
        // tracked apps have shipped, accumulated over time from the version
        // checks. On its own window so it survives the popover dismissing.
        Window("Release Log", id: ReleaseLogView.windowID) {
            ReleaseLogView(model: model)
        }
        .defaultSize(width: 520, height: 620)
        .windowResizability(.contentMinSize)

        // The download ledger — how much bandwidth updating this machine has cost,
        // by app and by month. Aggregate data, so it gets its own window next to
        // the Release Log rather than living inside the app-centric workbench.
        Window("Download Traffic", id: TrafficWindowView.windowID) {
            TrafficWindowView(model: model)
        }
        // Wide by default: the header is a four-column stat strip and every row
        // carries a name, a proportion bar, and three right-aligned figures — at
        // the old 720pt the bar had no room to read as a bar. Tall for the same
        // reason the list exists: seeing the ranking means seeing many rows at once.
        // Kept under 800pt high so it still opens whole on a 1280x800 display.
        .defaultSize(width: 1000, height: 780)
        .windowResizability(.contentMinSize)

        // Duo Updater's own release notes. Its own window, like the Release Log,
        // so it survives the popover dismissing — you open it from the menu and
        // then the menu goes away.
        Window("What's New", id: SelfChangelogView.windowID) {
            SelfChangelogView(model: model)
        }
        // Landscape by default: the notes are prose, and a narrow window turns each
        // paragraph into a column of short lines. Wide enough that the rail plus a
        // comfortable measure both fit without resizing on first open.
        .defaultSize(width: 900, height: 620)
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
            // Before the badge: with the Dock icon hidden there is no tile to
            // badge, and `sync` checks the policy this sets.
            DockIcon.apply(hidden: model.prefs.hideDockIcon)
            AppDockBadge.syncSoon(count: model.badgeCount)
            if let front = SilentSelfUpdateRelaunch.consume() { handTheFrontBack(to: front) }
            // What "a safe moment to replace ourselves" means, for the silent
            // self-update path.
            AppUpdater.shared.setIdleProbe { [weak model] in
                guard let model else { return false }
                // Nothing of ours may be in flight: a scan, a check, any install,
                // or an app still waiting to be relaunched. Quitting through one of
                // those is the interruption this gate exists to prevent.
                guard model.canRefresh, model.relaunching.isEmpty else { return false }
                // Open windows do NOT block: macOS restores them across the quit and
                // relaunch on its own — measured, with nothing of ours involved, so
                // a hand-written restore would only duplicate it (and the version
                // that tried stole ~9 seconds of focus putting windows back).
                // Being *looked at* does block: if we are frontmost, wait for the
                // keyboard and mouse to go quiet so the window is never pulled out
                // from under a click. In the background there is nothing to
                // interrupt and no such wait.
                guard NSApp.isActive else { return true }
                let idleSeconds = CGEventSource.secondsSinceLastEventType(
                    .combinedSessionState, eventType: .init(rawValue: ~0)!)
                return idleSeconds >= 60
            }
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

    /// Step back out of the way after a silent self-update relaunched us. Repeated
    /// rather than checked once, because the activation arrives late: macOS restores
    /// the window a beat after launch, so a single `isActive` test here reads false
    /// and does nothing — which is exactly how the app ended up sitting frontmost
    /// for over a minute after an update nobody asked for.
    private func handTheFrontBack(to bundleID: String) {
        Log.app.info("self-update: relaunched by a silent update — handing the front back to \(bundleID, privacy: .public)")
        Task { @MainActor in
            // Retried rather than done once: macOS restores our window a beat after
            // launch and that restore activates us, so a single attempt here can
            // land before the thing it is meant to undo. Stops as soon as we are no
            // longer in front.
            for delay in [0.1, 0.4, 1.0, 2.0, 3.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard NSApp.isActive else { return }
                NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundleID)
                    .first?
                    .activate()
            }
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
