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

    /// Setapp's client is also an installer: launched in the background it runs
    /// its check, and installs what it finds when its own "Install automatically"
    /// is on. This is the user's permission for that, not Setapp's.
    @AppStorage(SetappAutomation.backgroundUpdatesPreference) private var setappBackgroundUpdates = true

    /// Settings marked "new" when this page was opened. See `SettingsSpotlights`.
    @State private var spotlit: Set<String> = []

    var body: some View {
        SettingsPage(section: .general) {
            scheduleCard
            afterUpdateCard
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
    }

    private var scheduleCard: some View {
        SettingsCard {
            Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                .settingsRow()
                .settingsAnchor(.launchAtLogin)
            SettingsDivider()
            Picker("Check for updates", selection: $prefs.checkFrequency) {
                ForEach(Preferences.CheckFrequency.allCases) { freq in
                    Text(freq.label).tag(freq)
                }
            }
            .settingsRow()
            .settingsAnchor(.checkFrequency)
            // Re-arm the background loop with the new interval immediately.
            .onChange(of: prefs.checkFrequency) { _, _ in model.reschedule() }
            SettingsDivider()
            Toggle("Hide the Dock icon", isOn: $prefs.hideDockIcon)
                .settingsRow()
                .settingsAnchor(.hideDockIcon)
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
            .settingsAnchor(.appRuntimeTags)
            SettingsDivider()
            Toggle("Show what each command-line tool is built with", isOn: $prefs.showCLIRuntimeTags)
                .settingsRow()
                .settingsAnchor(.cliRuntimeTags)
        } footer: {
            // What else follows the schedule (`AppListModel.backgroundRefresh`).
            // The 15-minute floor on command-line tools that read GitHub binds only
            // at the 5-minute schedule without a token — the one case the caution
            // below shows for — so it is said there rather than as a third line.
            if prefs.checkFrequency.interval != nil {
                Text("Command-line tools are checked on this schedule too.")
                    .fixedSize(horizontal: false, vertical: true)
                if model.brewInstalled {
                    Text("Homebrew’s package list is refreshed once a day, following your Homebrew auto-update settings.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if prefs.hideDockIcon {
                Text("DuoUpdater runs from the menu bar only. The pending-update count moves to the menu-bar icon — the Dock badge needs a Dock icon to sit on.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if prefs.checkFrequency.isHighFrequency && hasGitHubToken == false {
                Label(
                    "No GitHub token: checking this often can hit GitHub’s rate limit (60/hour) and show errors on GitHub-sourced apps, and command-line tools that read GitHub are checked at most every 15 minutes. Add a token or sign in with the gh CLI under GitHub.",
                    systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var afterUpdateCard: some View {
        SettingsCard(header: "After an update") {
            SettingsToggle(
                "Relaunch updated apps automatically",
                detail: "Apps are asked to quit normally, so unsaved-work prompts still appear. One that won’t quit keeps its Relaunch button.",
                isOn: $prefs.autoRestartAfterUpdate)
                .settingsAnchor(.autoRelaunch)
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
            .settingsAnchor(.concurrency)
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
                .settingsAnchor(.appStoreUpdates)
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
                .settingsAnchor(.selfUpdatingApps)
            }

            // Beside "Self-updating apps" because it is the same question for one
            // more installer: Setapp's client installs its own apps. It used to sit
            // under Updates, which is about DuoUpdater's own version.
            SettingsCard {
                SettingsToggle(
                    "Update Setapp apps in the background",
                    detail: "Starts Setapp when a check finds updates for its apps, so it installs them. A Setapp window may appear behind other apps.",
                    info: "Only when Setapp’s own automatic installation is on. DuoUpdater quits a Setapp it started after 30 seconds idle, and only when it can confirm the updates have finished and you have not used Setapp; otherwise Setapp keeps running.",
                    isOn: $setappBackgroundUpdates)
                    .settingsAnchor(.setappBackgroundUpdates)
            }

            // Also a routing question: which source answers for a brew-installed
            // copy once brew itself has nothing newer. The row menu's own choice
            // beats this either way, so it is only the default.
            SettingsCard {
                SettingsToggle(
                    "Check other sources for Homebrew apps",
                    detail: "When Homebrew has no newer version, GitHub and other sources may offer one. A Homebrew update always comes first. When off, only apps that update themselves are checked this way.",
                    info: "This is the default for apps Homebrew installed. Apps whose official Homebrew cask says they update themselves check other sources even when this is off; apps from other taps do not. To choose for one app, right-click it and use When Homebrew Has No Update. An app stays on Homebrew by itself when an install from another source is refused for its signature, until that source offers a newer release. For another edition of an app, such as a community build, choose Homebrew Only.",
                    isOn: $prefs.brewFallbackByDefault)
                    .settingsAnchor(.brewFallback)
                    .onChange(of: prefs.brewFallbackByDefault) { model.brewFallbackDefaultChanged() }
            }

            SettingsCard {
                SettingsToggle(
                    "Allow one-click updates for apps without a developer signature",
                    detail: "Checks only that the download is byte for byte the file GitHub publishes for the release. That doesn’t protect you the way a developer signature does if the developer’s account is taken over, and macOS may ask you to grant these apps’ privacy permissions again after each update.",
                    info: "For apps whose GitHub releases are only ad-hoc signed — Alacritty, Flameshot, darktable, disktree, Lokii and Obelus — and not for apps that sign their own updates with Sparkle or MyGo: those are updated in one click without it, checked against the update key in the copy you have installed. An app installed with a developer signature is never replaced by one without, whatever this says.",
                    isOn: $prefs.allowsDigestOnlyInstalls)
                    .settingsAnchor(.digestOnlyInstalls)
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
