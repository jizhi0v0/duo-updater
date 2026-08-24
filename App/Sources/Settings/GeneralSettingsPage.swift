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
            footer: "After updating a running app, restart it for you so the new version takes effect — no second click. The app is asked to quit normally, so unsaved-work prompts still appear and anything that won’t quit just keeps its “Restart” button."
        ) {
            Toggle("Notify me when updates are found", isOn: $prefs.notifyOnUpdates)
                .settingsRow()
            SettingsDivider()
            Toggle("Restart updated apps automatically", isOn: $prefs.autoRestartAfterUpdate)
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

/// Carries the measured width of a picker row up to the row itself, so the
/// share-of-the-row rule below has a number to work with.
private struct PickerRowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A settings picker that keeps its label and popup on one line — the way the
/// rest of macOS lays these out — and only stacks the label above the popup when
/// one line would be cramped.
///
/// "Cramped" is defined as the popup wanting more than `maxPopupShare` of the
/// row: German and Russian option labels ("Immer herunterladen und ersetzen,
/// dann neu starten") blow well past that, and the single-line layout was
/// clipping them, which is why both rows were stacked unconditionally when
/// localization landed.
///
/// The rule is expressed by reserving the rest of the row for the label with
/// `minWidth`: a popup that needs more than its share pushes the HStack past
/// the row, and `ViewThatFits` drops to the stacked candidate. `rowWidth` is 0
/// on the first pass — the one-line candidate is then judged on its natural
/// width alone, and the layout settles once the measurement lands.
private struct AdaptivePickerRow<Content: View>: View {
    let title: Text
    @ViewBuilder var picker: Content

    /// How much of the row the popup may take before the row stacks instead.
    private let maxPopupShare: CGFloat = 0.6

    @State private var rowWidth: CGFloat = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                title
                    .font(.callout)
                    .frame(minWidth: rowWidth * (1 - maxPopupShare), alignment: .leading)
                picker.fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                title.font(.callout)
                picker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geo in
            Color.clear.preference(key: PickerRowWidthKey.self, value: geo.size.width)
        })
        .onPreferenceChange(PickerRowWidthKey.self) { rowWidth = $0 }
    }
}
