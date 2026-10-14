import SwiftUI

/// DuoUpdater's own version and self-update check — separate from the managed
/// app list, which is what the rest of the window is about.
struct UpdatesSettingsPage: View {
    /// Mirrors Sparkle's `automaticallyDownloadsUpdates` for the toggle. Seeded in
    /// `.task` rather than in the initializer because reading it touches the
    /// main-actor updater, and written straight back on change — Sparkle keeps the
    /// stored value, so this state is only ever a view of it.
    @State private var installsAutomatically = false

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
            }

            SettingsCard {
                SettingsToggle(
                    "Install DuoUpdater's own updates silently",
                    detail: "Installs at a quiet moment and relaunches DuoUpdater — no prompt. Off, a new version shows a prompt and waits for you.",
                    info: "DuoUpdater checks for its own updates every hour. A quiet moment means nothing is being checked or installed, and you’re either working in another app or haven’t touched the keyboard or mouse for a minute. Open DuoUpdater windows come back after the relaunch. Until a quiet moment comes it waits — and installs when you quit DuoUpdater anyway.",
                    isOn: $installsAutomatically)
                    .settingsAnchor(.silentSelfUpdate)
            }
        }
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
