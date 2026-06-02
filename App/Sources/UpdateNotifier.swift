import Foundation
import UserNotifications

/// Best-effort macOS user notifications for finished updates.
///
/// Every call is fire-and-forget: a notification must never block or break an
/// install. If the user hasn't granted permission (or this ad-hoc-signed build
/// can't post), the request is simply dropped.
@MainActor
enum UpdateNotifier {

    /// Ask once for permission to post notifications. Safe to call on launch;
    /// the system only prompts the first time.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A not-running app was updated in place — there's nothing left to do.
    static func updated(app: String, version: String?) {
        post(title: app, body: version.map { "Updated to \($0)." } ?? "Updated.")
    }

    /// A running app was updated on disk, but its live process is still on the
    /// old version. The user restarts it when ready, through the app's own quit
    /// flow.
    static func readyToRestart(app: String, version: String?) {
        let lead = version.map { "Update to \($0) is ready." } ?? "Update is ready."
        post(title: app, body: lead + " Restart to apply it.")
    }

    /// The user restarted and the new version is now live.
    static func restarted(app: String, version: String?) {
        post(title: app, body: version.map { "Now running \($0)." } ?? "Restarted on the new version.")
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
