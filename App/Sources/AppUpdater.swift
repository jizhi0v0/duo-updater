import AppKit
import Foundation
import Sparkle
import DuoUpdaterCore

/// Owns the moment Sparkle has our own update downloaded and staged.
///
/// Without a delegate here, "install silently" isn't silent: Sparkle's automatic
/// driver stages the update and then either waits for the app to quit or lets the
/// standard user driver put up a "ready to install" alert. Taking the delegate
/// means we choose *when* — and the only acceptable when is a moment where
/// restarting the app interrupts nothing.
@MainActor
private final class SelfUpdateInstaller: NSObject, SPUUpdaterDelegate {
    /// True when swapping the app out right now would interrupt nothing. Supplied
    /// by the app once the list model exists; while it is nil the answer is "not
    /// now", which is the safe default — Sparkle still installs a deferred update
    /// when the app quits, so a probe that never says yes costs nothing.
    var isIdle: (@MainActor () -> Bool)?

    private var installNow: (() -> Void)?
    private var watch: Task<Void, Never>?

    /// How often we look for an idle moment. Coarse on purpose: this swaps the
    /// running app out from under itself, which is nothing to hurry.
    private static let pollInterval = Duration.seconds(60)

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        Log.app.notice("self-update \(item.displayVersionString ?? "?", privacy: .public) staged — will install at the next idle moment")
        watch?.cancel()
        watch = Task { [weak self] in
            // Keep looking rather than giving up after one miss: the handler stays
            // valid, and Sparkle explicitly allows invoking it again if a
            // termination gets cancelled. The loop dies with the process when an
            // install does go through.
            while !Task.isCancelled {
                guard let self else { return }
                self.installIfIdle()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        // We own the timing from here. Returning true stalls Sparkle's scheduler —
        // and if we never find an idle moment, it still installs on quit.
        return true
    }

    private func installIfIdle() {
        guard let installNow else { return }
        guard isIdle?() == true else { return }
        // Nothing to save first: whatever windows are open come back on their own,
        // because macOS restores them across a quit and relaunch (measured — an
        // explicit restore here was written, tested against the system's own, and
        // deleted as duplicate).
        Log.app.notice("self-update: idle — installing and relaunching now")
        installNow()
    }
}

/// Holds the app's Sparkle updater for the lifetime of the process and exposes
/// a tiny Swift-friendly surface for "start once" and manual checks.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController
    private let selfInstaller: SelfUpdateInstaller
    private var didStart = false

    private init() {
        let selfInstaller = SelfUpdateInstaller()
        self.selfInstaller = selfInstaller
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: selfInstaller,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    /// Whether Sparkle downloads and installs our own updates without asking.
    /// Sparkle owns the storage (it persists to the `SUAutomaticallyUpdate` user
    /// default), so this is a straight pass-through rather than a mirror in
    /// `Preferences` that could drift.
    var installsUpdatesAutomatically: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Teach the silent installer what counts as a safe moment to restart. Called
    /// once at launch, from where the list model is in scope.
    func setIdleProbe(_ probe: @escaping @MainActor () -> Bool) {
        selfInstaller.isIdle = probe
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
