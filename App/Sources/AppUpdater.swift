import Foundation
import Sparkle
import DuoUpdaterCore

/// Holds the app's Sparkle updater for the lifetime of the process and exposes
/// a tiny Swift-friendly surface for "start once" and manual checks.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController
    private var didStart = false

    private init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    /// Start Sparkle once the app is ready for its own update checks.
    func start() {
        guard !didStart else { return }
        didStart = true
        controller.startUpdater()
        Log.app.info("sparkle updater started")
    }

    /// User-initiated self-update check. Starting the updater lazily keeps the
    /// first-launch onboarding free of an extra update prompt.
    func checkForUpdates() {
        start()
        controller.checkForUpdates(nil)
    }
}
