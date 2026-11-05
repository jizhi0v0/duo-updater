import SwiftUI
import DuoUpdaterCore

/// DuoUpdater's own version and self-update check — separate from the managed
/// app list, which is what the rest of the window is about.
struct UpdatesSettingsPage: View {
    /// Mirrors Sparkle's `automaticallyDownloadsUpdates` for the toggle. Seeded in
    /// `.task` rather than in the initializer because reading it touches the
    /// main-actor updater, and written straight back on change — Sparkle keeps the
    /// stored value, so this state is only ever a view of it.
    @State private var installsAutomatically = false
    @AppStorage("DuoUpdaterBetaChannel") private var betaChannel = false

    /// Setapp's client is also an installer: launched in the background it runs
    /// its check, and installs what it finds when its own "Install automatically"
    /// is on. This is the user's permission for that, not Setapp's.
    @AppStorage(SetappAutomation.backgroundUpdatesPreference) private var setappBackgroundUpdates = true

    private static let sourceURL = URL(string: "https://github.com/jizhi0v0/duo-updater")!

    private var currentVersionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = (info["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch (shortVersion, build) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty && short != build:
            return "\(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return short
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return String(localized: "Unknown")
        }
    }

    var body: some View {
        SettingsPage(section: .updates) {
            SettingsCard(
                footer: "DuoUpdater updates itself separately from the managed app list, through Sparkle-signed direct downloads. The button above forces a check right now, whether or not automatic installs are on."
            ) {
                versionRow
                SettingsDivider()
                Picker("Release channel", selection: $betaChannel) {
                    Text("Stable").tag(false)
                    Text("Beta").tag(true)
                }.settingsRow()
                Text("Beta receives early updates for testing. Switching to Stable waits for a newer stable release; it does not downgrade or cancel an update already prepared.")
                    .font(.caption).foregroundStyle(.secondary).settingsRow()
                Button("Report a problem on GitHub…") {
                    var url = URLComponents(string: "https://github.com/jizhi0v0/duo-updater/issues/new")!
                    url.queryItems = [URLQueryItem(name: "body", value:
                        "DuoUpdater: \(currentVersionLine)\nChannel: \(betaChannel ? "Beta" : "Stable")\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n\nSteps to reproduce:\n\nExpected behavior:\n\nActual behavior:\n\nFor installation failures, attach the report from Settings → Diagnostics after reviewing it.")]
                    if let url = url.url { NSWorkspace.shared.open(url) }
                }.settingsRow()
            }

            SettingsCard {
                SettingsToggle(
                    "Install DuoUpdater's own updates silently",
                    detail: "Installs at a quiet moment and relaunches DuoUpdater — no prompt. Off, a new version shows a prompt and waits for you.",
                    info: "DuoUpdater checks for its own updates every hour. A quiet moment means nothing is being checked or installed, and you’re either working in another app or haven’t touched the keyboard or mouse for a minute. Open DuoUpdater windows come back after the relaunch. Until a quiet moment comes it waits — and installs when you quit DuoUpdater anyway.",
                    isOn: $installsAutomatically)
                    .settingsAnchor(.silentSelfUpdate)
            }

            SettingsCard(
                footer: "When a check finds updates, starts Setapp if it is not running and automatic installation is enabled. Quits it after 30 seconds idle only when update activity can be safely verified and you have not used it; otherwise leaves it running. A window may appear behind other apps."
            ) {
                SettingsToggle(
                    "Update Setapp apps in the background",
                    detail: "Launch Setapp quietly so it installs its updates.",
                    isOn: $setappBackgroundUpdates)
            }
        }
        .onChange(of: betaChannel) { _, _ in AppUpdater.shared.channelDidChange() }
        .task { installsAutomatically = AppUpdater.shared.installsUpdatesAutomatically }
        .onChange(of: installsAutomatically) { _, on in
            AppUpdater.shared.installsUpdatesAutomatically = on
        }
    }

    private var versionRow: some View {
        HStack(spacing: 14) {
            appIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("DuoUpdater")
                    .font(.system(.title3, weight: .semibold))
                Text(currentVersionLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                // The only pointer to the repository inside the app, and a quiet
                // one: a plain link under the version, never a prompt. NSWorkspace
                // rather than SwiftUI `openURL`, which errors -50 in this window.
                Button("Source code on GitHub") {
                    NSWorkspace.shared.open(Self.sourceURL)
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .pointerStyle(.link)
            }
            Spacer(minLength: 12)
            Button("Check for Updates…") {
                AppUpdater.shared.checkForUpdates()
            }
            .settingsGlassButton(prominent: true)
            .disabled(!AppUpdater.shared.canCheckForUpdates)
        }
        .settingsRow()
        .padding(.vertical, 4)
        .settingsAnchor(.selfUpdateCheck)
    }

    @ViewBuilder
    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 52, height: 52)
    }
}
