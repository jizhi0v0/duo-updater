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
        .sheet(isPresented: $showingBackups) {
            BackupsSheet(backups: backupListing) { keys in
                Task {
                    await model.deleteBackups(keys: keys)
                    backupBytes = await Task.detached(priority: .utility) {
                        BackupStore.totalSize()
                    }.value
                }
            }
        }
    }

    /// Presented by "Clean Up…", loaded on demand because measuring every backup
    /// walks the disk.
    @State private var showingBackups = false
    @State private var backupListing: [BackupStore.Listing] = []

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
            SettingsDivider()
            Toggle("Hide the Dock icon", isOn: $prefs.hideDockIcon)
                .settingsRow()
        } footer: {
            if prefs.hideDockIcon {
                Text("Duo Updater runs from the menu bar only. The pending-update count moves to the menu-bar icon — the Dock badge needs a Dock icon to sit on.")
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            footer: "After updating a running app, relaunch it for you so the new version takes effect — no second click. The app is asked to quit normally, so unsaved-work prompts still appear and anything that won’t quit just keeps its “Relaunch” button.\n\nBackups keep one previous version of each app under Application Support, so an update can be undone. Retention is one backup per app — the previous version is replaced, not accumulated."
        ) {
            Toggle("Notify me when updates are found", isOn: $prefs.notifyOnUpdates)
                .settingsRow()
            SettingsDivider()
            Toggle("Relaunch updated apps automatically", isOn: $prefs.autoRestartAfterUpdate)
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
                // Opens the list rather than acting immediately: every backup is
                // somebody's rollback, and the old behaviour (prune orphans only)
                // usually deleted nothing and said nothing, which read as broken.
                Button("Clean Up…") {
                    guard !isCleaningBackups else { return }
                    isCleaningBackups = true
                    Task {
                        backupListing = await model.backupListing()
                        isCleaningBackups = false
                        showingBackups = !backupListing.isEmpty
                    }
                }
                .disabled(isCleaningBackups || backupBytes == 0)
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
                AdaptivePickerRow(title: Text("App Store updates")) {
                    Picker("App Store updates", selection: $prefs.appStoreUpdateStrategy) {
                        ForEach(Preferences.AppStoreUpdateStrategy.availableCases) { strategy in
                            Text(strategy.label).tag(strategy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .settingsRow()
            }

            SettingsCard(
                footer: "For apps that ship their own updater (Office, Teams, OneDrive, Edge, Chrome, VS Code, …). “Always replace” — the default — downloads the vendor’s own installer and applies it whether or not the app is running, quitting and relaunching it afterwards. Switch to “Defer while running” if you would rather nothing touched an app while it is open: it then installs only when the app is closed, and offers an Open button instead while it is running, leaving the update to the app itself."
            ) {
                AdaptivePickerRow(title: Text("Self-updating apps")) {
                    Picker("Self-updating apps", selection: $prefs.vendorInstallPolicy) {
                        ForEach(Preferences.VendorInstallPolicy.allCases) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .settingsRow()
            }
        }
    }
}

// MARK: - Adaptive picker row

/// A settings picker that follows the standard macOS label-left/control-right
/// row whenever the label and the popup both fit at their natural widths, and
/// stacks the label above the popup when they do not.
///
/// Both halves of the one-line candidate are `fixedSize`, so `ViewThatFits`
/// only chooses it when the row can show the whole label AND the whole selected
/// option. That distinction is the point: these options are sentences ("Always
/// download & replace, then restart"), and a popup handed a squeezed slot does
/// not stack or shrink — it truncates the current selection. At the 660pt window
/// minimum that happened in every language we ship, English included
/// ("Full download (no extra permissi…"), which left the reader unable to see
/// which route was active without opening the menu.
///
/// Ideal widths, so no measurement pass: `Spacer(minLength: 0)` contributes 0 to
/// the candidate's ideal size, leaving it as label + 12 + popup.
private struct AdaptivePickerRow<Content: View>: View {
    let title: Text
    @ViewBuilder var picker: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                title
                    .font(.callout)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                picker.fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                title.font(.callout)
                picker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
