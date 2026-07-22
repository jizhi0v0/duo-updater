import SwiftUI
import AppKit
import DuoUpdaterCore

/// Permissions, the last check, and per-recipe detection health.
struct DiagnosticsSettingsPage: View {
    let model: AppListModel
    @Environment(\.openWindow) private var openWindow
    @State private var entries: [RecipeHealth.Entry] = []
    @State private var loaded = false

    /// bundleID → app name, so a Vendor recipe (keyed by bundle id) shows a
    /// friendly name. GitHub recipes are keyed by `owner/repo`, which has no app
    /// to resolve, so those fall back to the raw key.
    private var names: [String: String] {
        var map: [String: String] = [:]
        for result in model.results {
            if let id = result.app.bundleID { map[id] = result.app.name }
        }
        return map
    }

    var body: some View {
        SettingsPage(section: .diagnostics) {
            permissionsCard
            lastCheckCard
            recipesCard
        }
        .task {
            entries = await RecipeHealth.shared.snapshot()
            loaded = true
        }
        // The window is long-lived; re-pull health whenever a check completes so
        // an open Diagnostics page doesn't show stale/empty data.
        .onChange(of: model.lastCheck) {
            Task { entries = await RecipeHealth.shared.snapshot() }
        }
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        SettingsCard(
            header: "Permissions",
            footer: "App Management lets Duo Updater replace apps updated outside the App Store (Sparkle, Homebrew, direct downloads). macOS can’t grant it programmatically — the button opens System Settings with a panel you drag DuoUpdater into.\n\nGranting through that panel doesn’t trigger the system’s usual “Quit & Reopen”, so a fresh grant may not take effect until DuoUpdater restarts. Use Relaunch below after granting."
        ) {
            // App Management has no *public* status API, but the private
            // TCCAccessPreflight SPI lets us read it — so show a real check when granted.
            SettingsField(title: "App Management") {
                if model.appManagementStatus == .granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Button("Grant…") { model.presentAppManagementPermissionFlow() }
                        .settingsGlassButton()
                }
            }
            SettingsDivider()
            // Privileged helper: a one-time approval that lets App Store ("full")
            // updates run without a password each time.
            HelperStatusRow(helper: model.helperClient)
            SettingsDivider()
            HStack(spacing: 10) {
                Button("Run Setup Again…") {
                    openWindow(id: WelcomeView.windowID)
                    model.surfaceWindow(sceneID: WelcomeView.windowID)
                }
                .settingsGlassButton()
                Button("Relaunch DuoUpdater") { Self.relaunch() }
                    .settingsGlassButton()
                Spacer(minLength: 0)
            }
            .settingsRow()
        }
    }

    // MARK: - Last check

    private var lastCheckCard: some View {
        SettingsCard {
            SettingsField(title: "Last checked") {
                Text(model.lastCheck.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Recipes

    private var recipesCard: some View {
        SettingsCard(
            header: "Detection recipes",
            footer: "A recipe is flagged when it fetched successfully but couldn’t read a version — often a sign the vendor changed their page. Cleared automatically on the next successful check."
        ) {
            if !loaded {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading recipe health…").foregroundStyle(.secondary)
                }
                .settingsRow()
            } else if entries.isEmpty {
                Text("No recipe-backed apps have been checked yet this session.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .settingsRow()
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { SettingsDivider() }
                    recipeRow(entry)
                }
            }
        }
    }

    private func recipeRow(_ entry: RecipeHealth.Entry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(entry.isHealthy ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(names[entry.id] ?? entry.id).font(.callout)
                if !entry.isHealthy, let detail = entry.lastMissDetail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(entry.source).font(.caption2).foregroundStyle(.tertiary)
        }
        .settingsRow()
    }

    /// Spawn a fresh instance, then terminate this one — the standard "restart
    /// myself" handoff. `open -n` launches a new copy that outlives our exit, so a
    /// permission granted via the drag panel takes effect without the user hunting
    /// for the app in Finder.
    private static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            Log.app.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Permissions row for the privileged helper. Observes the client so it flips to
/// "Enabled" once the user approves the background item, and re-queries status on
/// appear (approval happens out-of-app, in System Settings › Login Items).
private struct HelperStatusRow: View {
    @ObservedObject var helper: PrivilegedHelperClient

    var body: some View {
        SettingsField(title: "App Store helper") {
            if helper.isEnabled {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Enable…") { helper.register() }
                    .settingsGlassButton()
            }
        }
        .onAppear { helper.refreshStatus() }
    }
}
