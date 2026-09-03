import AppKit
import Foundation
import Sparkle
import DuoUpdaterCore

/// A one-shot note that the launch which follows was started by a silent
/// self-update rather than by a person.
///
/// macOS restores the app's windows across the relaunch on its own — which is why
/// there is no window bookkeeping here — but restoring a window also ACTIVATES
/// the app. After an update nobody asked for, arriving in front is precisely the
/// interruption the silent path exists to avoid: measured at over a minute
/// frontmost, on top of whatever the user was actually doing.
@MainActor
enum SilentSelfUpdateRelaunch {
    private static let key = "SilentSelfUpdateRelaunch"

    /// Sparkle falls back to installing on quit when no quiet moment ever comes,
    /// which can be days later. A marker with no expiry would then drop some
    /// unrelated launch into the background for no reason.
    private static let freshness: TimeInterval = 10 * 60

    /// Records *who* was in front, because that is what the relaunch takes away —
    /// and only the process about to be replaced can see it.
    ///
    /// The obvious alternative, having the new process call `NSApp.deactivate()`,
    /// was written and measured first: five ticks over three seconds, `isActive`
    /// true at every one, `deactivate()` called at every one, and the app sat
    /// frontmost throughout. Giving the front to a named app is what actually
    /// works — the same move the app already makes when it relaunches something it
    /// just updated.
    static func arm() {
        var payload: [String: Any] = ["at": Date().timeIntervalSince1970]
        // Nothing to hand back when we were the app in front: the idle gate does
        // allow that (frontmost plus a quiet keyboard and mouse), and re-activating
        // ourselves would be a no-op at best.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           front != Bundle.main.bundleIdentifier {
            payload["front"] = front
        }
        UserDefaults.standard.set(payload, forKey: key)
    }

    /// The bundle id that should get the front back, or nil when there is nothing
    /// to do. Cleared even when stale, so it can never be consumed twice.
    static func consume() -> String? {
        let stored = UserDefaults.standard.dictionary(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        guard let stored,
              let armedAt = stored["at"] as? TimeInterval,
              Date().timeIntervalSince1970 - armedAt < freshness
        else { return nil }
        return stored["front"] as? String
    }
}

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

    /// Book our own update's download into the request ledger.
    ///
    /// Sparkle downloads through its own `URLSession`, inside the framework, so
    /// none of the metrics instrumentation on `URLSession.updates` or `Downloader`
    /// can see these bytes — and they are among the largest this app ever spends.
    /// The appcast's `contentLength` is the only figure available, hence
    /// ``RequestByteSource/declared``: our own `publish-release.sh` writes it from
    /// the real archive, so it is accurate, but it is the publisher's word rather
    /// than a measurement and the ledger says so.
    ///
    /// Known gap: Sparkle's periodic *appcast* fetch is invisible the same way and
    /// has no size to declare, so it is not recorded at all. A few KB every few
    /// hours against one host — the part of the self-update cost that does not
    /// matter, which is why this settles for the part that does.
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        guard item.contentLength > 0, let host = item.fileURL?.host else { return }
        let now = Date()
        let event = RequestEvent(
            purpose: .selfUpdate, method: "GET", scheme: item.fileURL?.scheme,
            host: host, port: item.fileURL?.port, path: item.fileURL?.path ?? "",
            // A synthetic task with a single hop: Sparkle's own redirects are as
            // invisible to us as its byte counts, and inventing hops we did not
            // observe would be worse than recording the one we can attest to.
            taskID: UUID(), hopIndex: 0, redirectCount: 0,
            status: 200, fetchType: .networkLoad,
            responseBodyBytes: Int64(item.contentLength),
            responseBodyBytesAfterDecoding: Int64(item.contentLength),
            byteSource: .declared, fetchStart: now, responseEnd: now)
        Task { await EventStore.shared.append(DuoEvent(date: now, payload: .request(event))) }
    }

    private func installIfIdle() {
        guard let installNow else { return }
        guard isIdle?() == true else { return }
        // No window bookkeeping: macOS restores them across the quit and relaunch on
        // its own (measured — an explicit restore was written, compared against the
        // system's, and deleted as duplicate). Only the *front* has to be handed
        // back, and that decision belongs to the process that comes up next.
        SilentSelfUpdateRelaunch.arm()
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
