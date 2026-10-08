import SwiftUI

/// Which updates DuoUpdater announces, and so which ones the menu-bar icon's
/// number and the Dock badge count (`AppListModel.badgeCount`).
///
/// "Apps" is the switch General used to hold (`notifyOnUpdates`, the same key);
/// the other two arrived with the background checks for command-line tools and
/// Homebrew.
struct NotificationsSettingsPage: View {
    @Bindable var prefs: Preferences

    var body: some View {
        SettingsPage(section: .notifications) {
            SettingsCard(
                header: "Notify me about updates to",
                footer: "The menu bar icon’s number and the Dock badge always count apps, and count command-line tools and Homebrew packages only while they’re switched on here. App Store’s request to relaunch an app so it can finish updating is sent either way."
            ) {
                Toggle("Apps", isOn: $prefs.notifyOnUpdates)
                    .settingsRow()
                SettingsDivider()
                Toggle("Command-line tools", isOn: $prefs.notifyOnCLIToolUpdates)
                    .settingsRow()
                SettingsDivider()
                Toggle("Homebrew packages", isOn: $prefs.notifyOnHomebrewUpdates)
                    .settingsRow()
            }
        }
    }
}
