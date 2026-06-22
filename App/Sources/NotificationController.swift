import Foundation
import UserNotifications
import AppKit

/// Owns the user-notification delegate so background-check notifications can carry
/// tappable actions ("Update All", "View") that route back into the app.
///
/// Kept separate from `UpdateNotifier` (which just posts fire-and-forget banners):
/// this one holds the references needed to *act* on a tapped notification.
///
/// Not `@MainActor`: `UNUserNotificationCenterDelegate` callbacks are delivered on
/// an arbitrary queue, and Swift 6 forbids a main-actor class from conforming to a
/// non-isolated protocol. Like `Downloader`, it's `@unchecked Sendable` and guards
/// its cross-thread state with a lock, hopping to the main actor to actually act.
final class NotificationController: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    static let shared = NotificationController()

    /// Category + action identifiers, kept in one place so registration and the
    /// response handler can't drift apart.
    enum ID {
        static let updatesCategory = "UPDATES_AVAILABLE"
        static let installAll = "INSTALL_ALL"
        static let view = "VIEW"
        /// A "the app downloaded an update on its own" banner, carrying a Relaunch
        /// action that swaps in the staged build straight from the notification.
        static let selfUpdateCategory = "SELF_UPDATE_STAGED"
        static let relaunch = "RELAUNCH"
        /// userInfo key carrying the target row's id (its on-disk path) so the
        /// Relaunch action knows which app to restart.
        static let appIDKey = "appID"
    }

    private let lock = NSLock()
    // `AppListModel` is `@MainActor`, hence Sendable — safe to hand to a hop.
    private weak var _model: AppListModel?
    private var _onShowUpdates: (@Sendable @MainActor () -> Void)?

    /// Set by the app so the "View" action (and a plain tap) can open the window.
    /// Stored under the lock since the delegate reads it off the main thread.
    func setOnShowUpdates(_ handler: @escaping @Sendable @MainActor () -> Void) {
        lock.withLock { _onShowUpdates = handler }
    }

    /// Wire up the delegate, register the actionable category, and ask for
    /// permission once. Called on the main actor at launch.
    @MainActor
    func register(model: AppListModel) {
        lock.withLock { _model = model }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let installAll = UNNotificationAction(
            identifier: ID.installAll, title: "Update All", options: [])
        let view = UNNotificationAction(
            identifier: ID.view, title: "View", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: ID.updatesCategory,
            actions: [installAll, view],
            intentIdentifiers: [],
            options: [])

        // "Relaunch" quits and reopens the app to apply the build it staged itself.
        // No `.foreground`: the restart runs headless via NSWorkspace; we don't pull
        // DuoUpdater forward for it.
        let relaunch = UNNotificationAction(
            identifier: ID.relaunch, title: "Relaunch", options: [])
        let selfUpdate = UNNotificationCategory(
            identifier: ID.selfUpdateCategory,
            actions: [relaunch],
            intentIdentifiers: [],
            options: [])
        center.setNotificationCategories([category, selfUpdate])

        // `.badge` is required even though we never badge via UNUserNotificationCenter:
        // requesting authorization WITHOUT it makes the system deny badge permission for
        // the app (Settings ▸ Notifications shows no "Badges" toggle), which silently
        // suppresses the Dock badge set via `NSApp.dockTile.badgeLabel`. An app that never
        // calls requestAuthorization isn't gated this way — which is why this only bit us
        // once notifications were wired up.
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show background-check banners even while DuoUpdater is the foreground app
    /// (otherwise the user would only see them when it's in the background).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let (model, show) = lock.withLock { (_model, _onShowUpdates) }
        switch response.actionIdentifier {
        case ID.installAll:
            Task { @MainActor in await model?.installAll() }
        case ID.relaunch:
            // Restart the specific app named in the notification's userInfo.
            if let id = response.notification.request.content.userInfo[ID.appIDKey] as? String {
                Task { @MainActor in await model?.restart(byID: id) }
            }
        case ID.view, UNNotificationDefaultActionIdentifier:
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                show?()
            }
        default:
            break
        }
        completionHandler()
    }
}
