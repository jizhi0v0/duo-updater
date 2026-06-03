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
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
