import Foundation
import UserNotifications

/// Best-effort macOS user notifications for finished updates.
///
/// Every call is fire-and-forget: a notification must never block or break an
/// install. If the user hasn't granted permission (or this ad-hoc-signed build
/// can't post), the request is simply dropped.
@MainActor
enum UpdateNotifier {

    /// A background check found updates. Carries the actionable category so the
    /// banner shows "Update All" / "View" buttons (handled by
    /// `NotificationController`). `total` is the full pending count; `newApps`
    /// names the ones that newly appeared since the last check.
    static func updatesAvailable(total: Int, newApps: [String]) {
        let title = total == 1 ? "1 update available" : "\(total) updates available"
        let body: String
        switch newApps.count {
        case 0:  return  // nothing newly appeared — don't nag
        case 1:  body = "\(newApps[0]) has an update."
        case 2:  body = "\(newApps[0]) and \(newApps[1]) have updates."
        default: body = "\(newApps[0]), \(newApps[1]), and \(newApps.count - 2) more have updates."
        }
        post(title: title, body: body, categoryID: NotificationController.ID.updatesCategory)
    }

    /// A not-running app was updated in place — there's nothing left to do.
    static func updated(app: String, version: String?) {
        post(title: app, body: version.map { "Updated to \($0)." } ?? "Updated.")
    }

    /// "Update All" finished — one summary instead of a banner per app. Apps that
    /// were running show a Restart badge in the menu, so we don't enumerate them.
    static func batchUpdated(count: Int) {
        post(title: "Updates installed",
             body: count == 1 ? "1 app was updated." : "\(count) apps were updated.")
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

    private static func post(title: String, body: String, categoryID: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // A category id attaches the actionable buttons registered for it.
        if let categoryID { content.categoryIdentifier = categoryID }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
