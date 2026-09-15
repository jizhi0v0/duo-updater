import SwiftUI

/// DuoUpdater's own version and self-update check — separate from the managed
/// app list, which is what the rest of the window is about.
struct UpdatesSettingsPage: View {
    /// Mirrors Sparkle's `automaticallyDownloadsUpdates` for the toggle. Seeded in
    /// `.task` rather than in the initializer because reading it touches the
    /// main-actor updater, and written straight back on change — Sparkle keeps the
    /// stored value, so this state is only ever a view of it.
    @State private var installsAutomatically = false

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
                    info: "DuoUpdater checks for its own updates every hour. A quiet moment means nothing is being checked or installed, no DuoUpdater window is open, and you’re working in another app. Until one comes it waits — and installs when you quit DuoUpdater anyway.",
                    isOn: $installsAutomatically)
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
    }

    @ViewBuilder
    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 52, height: 52)
    }
}
