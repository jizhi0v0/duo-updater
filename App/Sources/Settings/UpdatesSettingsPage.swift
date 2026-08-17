import SwiftUI

/// Duo Updater's own version and self-update check — separate from the managed
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
            return "Unknown"
        }
    }

    var body: some View {
        SettingsPage(section: .updates) {
            SettingsCard(
                footer: "Duo Updater updates itself separately from the managed app list, through Sparkle-signed direct downloads."
            ) {
                versionRow
            }

            SettingsCard(
                footer: "Duo Updater checks for its own updates hourly on its own. Left off, a new version puts up a prompt and waits for you.\n\nTurned on, it is downloaded and then applied at a quiet moment — no prompt, no clicking. A quiet moment means nothing is being checked or installed, no window of Duo Updater's is open, and you are working in another app; it restarts itself there. Until such a moment comes it simply waits, and installs when you quit Duo Updater anyway.\n\nThe button below forces a check right now either way."
            ) {
                Toggle("Install Duo Updater's own updates silently", isOn: $installsAutomatically)
                    .settingsRow()
                SettingsDivider()
                HStack {
                    Text("Check now")
                    Spacer(minLength: 12)
                    Button("Check for Updates…") {
                        AppUpdater.shared.checkForUpdates()
                    }
                    .settingsGlassButton(prominent: true)
                    .disabled(!AppUpdater.shared.canCheckForUpdates)
                }
                .settingsRow()
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
                Text("Duo Updater")
                    .font(.system(.title3, weight: .semibold))
                Text(currentVersionLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
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
