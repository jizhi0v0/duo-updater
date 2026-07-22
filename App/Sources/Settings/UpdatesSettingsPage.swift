import SwiftUI

/// Duo Updater's own version and self-update check — separate from the managed
/// app list, which is what the rest of the window is about.
struct UpdatesSettingsPage: View {
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
                footer: "Automatic checks are enabled too, but this button forces an immediate check."
            ) {
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
