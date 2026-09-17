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

    /// Settings marked "new" when this page was opened. See `SettingsSpotlights`.
    @State private var spotlit: Set<String> = []

    var body: some View {
        SettingsPage(section: .general) {
            scheduleCard
            afterUpdateCard.settingsAnchor(.backups)
            concurrencyCard
            routingCard
        }
        .onAppear {
            // Snapshot before acknowledging: `acknowledgeSpotlights` clears the
            // page's dots as soon as the page is looked at, which is what the menu
            // bar and the sidebar want, but the row still has to show its own.
            spotlit = prefs.pendingSpotlights
            prefs.acknowledgeSpotlights(in: .general)
        }
        .task {
            // Resolve token availability once. `GitHubToken.resolve` may shell out
            // to `gh auth token`, so keep it off the main thread.
            let explicit = prefs.githubToken.isEmpty ? nil : prefs.githubToken
            hasGitHubToken = await Task.detached(priority: .utility) {
                await GitHubToken.resolve(explicit: explicit) != nil
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
            SettingsDivider()
            HStack(spacing: 6) {
                Toggle("Show what each app is built with", isOn: $prefs.showRuntimeTags)
                // From the snapshot, not from `prefs`: opening the page retires the
                // dot immediately (so the menu bar and sidebar stop pointing here),
                // and reading the live value would make this one vanish in the same
                // frame it was meant to be noticed in.
                if spotlit.contains(SettingsSpotlights.appRuntimeTags.id) { SpotlightDot() }
            }
            .settingsRow()
        } footer: {
            if prefs.hideDockIcon {
                Text("DuoUpdater runs from the menu bar only. The pending-update count moves to the menu-bar icon — the Dock badge needs a Dock icon to sit on.")
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
        SettingsCard(header: "After an update") {
            Toggle("Notify me when updates are found", isOn: $prefs.notifyOnUpdates)
                .settingsRow()
            SettingsDivider()
            SettingsToggle(
                "Relaunch updated apps automatically",
                detail: "Apps are asked to quit normally, so unsaved-work prompts still appear. One that won’t quit keeps its Relaunch button.",
                isOn: $prefs.autoRestartAfterUpdate)
            SettingsDivider()
            SettingsToggle(
                "Keep a backup so updates can be rolled back",
                detail: "One previous version per app, kept in Application Support and replaced by the next update.",
                isOn: $prefs.keepBackups)
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
            SettingsCard(header: "Install routing") {
                VStack(alignment: .leading, spacing: 4) {
                    AdaptivePickerRow(title: Text("App Store updates")) {
                        Picker("App Store updates", selection: $prefs.appStoreUpdateStrategy) {
                            ForEach(Preferences.AppStoreUpdateStrategy
                                .visibleCases(current: prefs.appStoreUpdateStrategy)) { strategy in
                                Text(strategy.label).tag(strategy)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    PickerOptionDetail(appStoreStrategyDetail)
                }
                .settingsRow()
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 4) {
                    AdaptivePickerRow(title: Text("Self-updating apps")) {
                        Picker("Self-updating apps", selection: $prefs.vendorInstallPolicy) {
                            ForEach(Preferences.VendorInstallPolicy.allCases) { policy in
                                Text(policy.label).tag(policy)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    PickerOptionDetail(String(localized: "For apps that ship their own updater (Office, Teams, OneDrive, Edge, Chrome, VS Code, …)."))
                    PickerOptionDetail(vendorPolicyDetail)
                }
                .settingsRow()
            }

            testFlightCard.settingsAnchor(.testFlightDetection)
        }
    }

    /// What DuoUpdater does about TestFlight betas (`TestFlightDetection`).
    ///
    /// Here rather than under Updates, which is DuoUpdater's own self-update: this
    /// is the same question as the two pickers above — how much to do about one
    /// source — and the tip on a TestFlight row sends the reader to this page.
    ///
    /// The description under the picker names the permission and the cost because
    /// both are real and neither is visible from the picker: the two "on" states need
    /// Full Disk Access, and only the third starts an app the user did not start.
    /// Those stay on screen; only why TestFlight has to be started is behind the ⓘ.
    private var testFlightCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 4) {
                AdaptivePickerRow(title: HStack(spacing: 4) {
                    Text("TestFlight betas")
                    SettingsInfoButton("TestFlight keeps the builds it offers you in its own database, and only TestFlight itself ever brings that database up to date — so a fresh answer means starting TestFlight. Reading the database needs Full Disk Access; without it, beta rows say so.")
                }) {
                    Picker("TestFlight betas", selection: $prefs.testFlightDetection) {
                        ForEach(Preferences.TestFlightDetection.allCases) { detection in
                            Text(detection.label).tag(detection)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    // The rows on screen were answered under the old setting and nothing
                    // else revisits them until the next round, so the change is settled
                    // here — a `didSet` on `Preferences` cannot, it knows no model.
                    .onChange(of: prefs.testFlightDetection) { model.testFlightDetectionChanged() }
                }
                PickerOptionDetail(testFlightDetectionDetail)
            }
            .settingsRow()
        }
    }

    // MARK: - Option descriptions

    // What the SELECTED option does, rather than a footer walking through every
    // option: the reader sees the consequence of the choice they just made, next
    // to the control, in a third of the text.

    private var appStoreStrategyDetail: String {
        switch prefs.appStoreUpdateStrategy {
        case .full:
            return String(localized: "Downloads the whole app again through mas. The predictable route for release builds, and it needs no Accessibility access.")
        case .incremental:
            return String(localized: "Presses App Store’s own Update button, so only what changed is downloaded. Needs Accessibility access, and is still being evaluated.")
        }
    }

    private var vendorPolicyDetail: String {
        switch prefs.vendorInstallPolicy {
        case .alwaysOverwrite:
            return String(localized: "The default. Downloads the vendor’s own installer and applies it even while the app is open, quitting and relaunching it afterwards.")
        case .deferWhenRunning:
            return String(localized: "Nothing touches an app while it is open: it installs only once the app is closed, and offers Open instead, leaving the update to the app itself.")
        }
    }

    private var testFlightDetectionDetail: String {
        switch prefs.testFlightDetection {
        case .off:
            return String(localized: "Nothing is read, and beta rows say detection is off instead of guessing.")
        case .whenAsked:
            return String(localized: "Reads what TestFlight already knows, and asks it for a fresh answer when you press Refresh. Needs Full Disk Access.")
        case .keepFresh:
            return String(localized: "Also asks TestFlight on its own — at most once an hour, or when a beta has moved on — starting it in the background for a few seconds (about 0.7 MB). Needs Full Disk Access.")
        }
    }
}

/// One caption line under a picker row: what the current choice means.
private struct PickerOptionDetail: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
private struct AdaptivePickerRow<Title: View, Content: View>: View {
    let title: Title
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
