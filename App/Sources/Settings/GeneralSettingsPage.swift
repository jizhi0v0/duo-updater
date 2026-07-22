import SwiftUI
import DuoUpdaterCore

/// Schedule, what happens after a check, and the two install-routing policies.
struct GeneralSettingsPage: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    /// Whether a GitHub token resolves (explicit setting, env var, or `gh` login).
    /// nil until the off-main-thread probe finishes. Only drives the sub-hourly
    /// rate-limit caution — a developer with `gh` authenticated never sees it.
    @State private var hasGitHubToken: Bool?

    /// Total on-disk size of the backup store, refreshed on appear and after
    /// every cleanup so the footer stays truthful without polling.
    @State private var backupBytes: Int64?
    @State private var isCleaningBackups = false

    var body: some View {
        SettingsPage(section: .general) {
            scheduleCard
            afterUpdateCard
            concurrencyCard
            routingCard
        }
        .task {
            // Resolve token availability once. `GitHubToken.resolve` may shell out
            // to `gh auth token`, so keep it off the main thread.
            let explicit = prefs.githubToken.isEmpty ? nil : prefs.githubToken
            hasGitHubToken = await Task.detached(priority: .utility) {
                GitHubToken.resolve(explicit: explicit) != nil
            }.value
        }
        .task {
            backupBytes = await Task.detached(priority: .utility) { BackupStore.totalSize() }.value
        }
    }

    private var backupSizeLabel: String {
        guard let backupBytes else { return "…" }
        return ByteCountFormatter.string(fromByteCount: backupBytes, countStyle: .file)
    }

    private var scheduleCard: some View {
        SettingsCard {
            Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                .settingsRow()
            SettingsDivider()
            Picker("Check for updates", selection: $prefs.checkFrequency) {
                ForEach(Preferences.CheckFrequency.allCases) { freq in
                    Text(freq.label).tag(freq)
                }
            }
            .settingsRow()
            // Re-arm the background loop with the new interval immediately.
            .onChange(of: prefs.checkFrequency) { _, _ in model.reschedule() }
        } footer: {
            if prefs.checkFrequency.isHighFrequency && hasGitHubToken == false {
                Label(
                    "No GitHub token: checking this often can hit GitHub’s rate limit (60/hour) and show errors on GitHub-sourced apps. Add a token or sign in with the gh CLI under GitHub.",
                    systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var afterUpdateCard: some View {
        SettingsCard(
            header: "After an update",
            footer: "After updating a running app, restart it for you so the new version takes effect — no second click. The app is asked to quit normally, so unsaved-work prompts still appear and anything that won’t quit just keeps its “Restart” button.\n\nBackups keep one previous version of each app under Application Support, so an update can be undone. Retention is one backup per app — the previous version is replaced, not accumulated."
        ) {
            Toggle("Notify me when updates are found", isOn: $prefs.notifyOnUpdates)
                .settingsRow()
            SettingsDivider()
            Toggle("Restart updated apps automatically", isOn: $prefs.autoRestartAfterUpdate)
                .settingsRow()
            SettingsDivider()
            Toggle("Keep a backup so updates can be rolled back", isOn: $prefs.keepBackups)
                .settingsRow()
            SettingsDivider()
            Toggle("Delete a backup once its app is uninstalled", isOn: $prefs.pruneOrphanBackups)
                .settingsRow()
            SettingsDivider()
            HStack {
                Text("Backups are using \(backupSizeLabel)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clean Up Now") {
                    guard !isCleaningBackups else { return }
                    isCleaningBackups = true
                    Task {
                        _ = await model.cleanUpOrphanBackups()
                        backupBytes = await Task.detached(priority: .utility) {
                            BackupStore.totalSize()
                        }.value
                        isCleaningBackups = false
                    }
                }
                .disabled(isCleaningBackups)
            }
            .settingsRow()
        }
    }

    private var concurrencyCard: some View {
        SettingsCard(
            footer: "Lower this on a slow connection; raise it to check a large library faster."
        ) {
            Stepper(value: $prefs.maxConcurrency, in: 1...32) {
                Text("Check up to \(prefs.maxConcurrency) apps at once")
            }
            .settingsRow()
        }
    }

    private var routingCard: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(
                header: "Install routing",
                footer: "Mac App Store updates currently use the full-download route via mas. It’s the more predictable option for release builds and doesn’t require Accessibility access."
            ) {
                Picker("App Store updates", selection: $prefs.appStoreUpdateStrategy) {
                    ForEach(Preferences.AppStoreUpdateStrategy.availableCases) { strategy in
                        Text(strategy.label).tag(strategy)
                    }
                }
                .settingsRow()
            }

            SettingsCard(
                footer: "For apps that ship their own updater (Office, Teams, OneDrive, Edge, Chrome, VS Code, …). “Defer while running” installs over them only when they’re closed; while running it opens the app so its own updater applies the update. “Always replace” downloads and swaps in place either way, then prompts a restart."
            ) {
                Picker("Self-updating apps", selection: $prefs.vendorInstallPolicy) {
                    ForEach(Preferences.VendorInstallPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                .settingsRow()
            }
        }
    }
}
