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

    /// The app's own updater downloaded and staged a new version on its own —
    /// we never clicked Update. Nothing was installed by us; the bytes are staged
    /// and a relaunch applies them. Carries a Relaunch action (routed by `appID`)
    /// and a stable per-app identifier, so the periodic re-reminder replaces the
    /// previous banner in Notification Center rather than stacking copies.
    static func selfDownloaded(app: String, version: String, appID: String) {
        post(title: app,
             body: "\(app) downloaded \(version) on its own. Relaunch to apply it.",
             categoryID: NotificationController.ID.selfUpdateCategory,
             identifier: "selfupdate:\(appID)",
             userInfo: [NotificationController.ID.appIDKey: appID])
    }

    /// Remove a self-download reminder (pending or already delivered) once the user
    /// has relaunched, so a stale "Relaunch to apply it" banner doesn't linger in
    /// Notification Center after it's been applied.
    static func clearSelfDownloaded(appID: String) {
        let id = "selfupdate:\(appID)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// The user restarted and the new version is now live.
    static func restarted(app: String, version: String?) {
        post(title: app, body: version.map { "Now running \($0)." } ?? "Restarted on the new version.")
    }

    private static func post(
        title: String, body: String, categoryID: String? = nil,
        identifier: String? = nil, userInfo: [String: String] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // A category id attaches the actionable buttons registered for it.
        if let categoryID { content.categoryIdentifier = categoryID }
        if !userInfo.isEmpty { content.userInfo = userInfo }
        // A stable identifier lets a later post with the same id *replace* this
        // banner (used by the periodic self-update reminder); nil → a fresh UUID so
        // independent banners don't clobber each other.
        let request = UNNotificationRequest(
            identifier: identifier ?? UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
