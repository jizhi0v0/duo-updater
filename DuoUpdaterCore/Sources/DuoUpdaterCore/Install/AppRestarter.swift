import AppKit
import Foundation

/// Quits the running instance(s) of an installed app and relaunches it once
/// they've actually exited — the mechanism behind the menu-bar app's "Restart"
/// action, so an in-place update takes effect without the user quitting and
/// reopening by hand.
///
/// Pulled out of `AppListModel` so `duo restart` can offer the same action
/// without re-implementing its several hard-won details, each documented on the
/// method that encodes it. What stays with the caller: any UI-facing state
/// (a spinner while it's in flight, a badge that clears once it's done) and
/// deciding *whether* a restart is warranted — this only ever does the quit,
/// wait, relaunch.
public enum AppRestarter {

    /// What happened when `restart(_:)` tried to bring an app back up.
    public enum Outcome: Sendable, Equatable {
        /// The app has no `CFBundleIdentifier`, so there is nothing reliable to
        /// match running instances against. Nothing was attempted.
        case noBundleID
        /// No running instance was found — there was nothing to quit or relaunch.
        case notRunning
        /// Quit was requested but the app never actually exited within the
        /// timeout — almost always a save prompt. Left running, untouched.
        case stillRunning
        /// Every running instance quit; `true` if the relaunch also succeeded.
        case relaunched(Bool)
    }

    /// Quit every running instance of `app` and relaunch it once they've all
    /// exited. An app that isn't running at all is a no-op (`.notRunning`) —
    /// there is nothing whose in-memory code is stale.
    ///
    /// Graceful only: quits are `terminate()`, which honours save prompts, never
    /// a force-kill. An app that puts up such a prompt and won't exit is left
    /// running (`.stillRunning`) rather than losing unsaved work.
    @discardableResult
    public static func restart(_ app: InstalledApp) async -> Outcome {
        guard app.bundleID != nil else { return .noBundleID }
        let running = runningInstances(of: app)
        guard !running.isEmpty else { return .notRunning }
        // Sampled before the quit — once every instance is gone, so is the
        // answer — and decides whether the relaunch takes the foreground (see
        // `isFrontmost`).
        let wasFrontmost = isFrontmost(running)
        for instance in running { instance.terminate() }
        // Wait up to ~30s for a graceful quit. A heavy app (large workspace) can
        // take well over the old 6s to actually exit; bailing early would leave
        // it terminated-but-not-relaunched. The only case given up on is a
        // genuine hang/save-prompt, where the app stays *up* (never stranded down).
        for _ in 0..<150 {
            if runningInstances(of: app).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard runningInstances(of: app).isEmpty else {
            Log.install.error(
                "app-restarter: \(app.name, privacy: .public) won't quit (likely a save prompt) — leaving it running")
            return .stillRunning
        }
        let relaunched = await launchApp(app.path, activates: wasFrontmost)
        Log.install.info(
            "app-restarter: \(app.name, privacy: .public) relaunched=\(relaunched, privacy: .public)")
        return .relaunched(relaunched)
    }

    /// The running instances launched from *this exact .app*, not just any app
    /// sharing its bundle id. Channel siblings (Android Studio Preview/Stable,
    /// etc.) share one bundle id, so terminating "all with this bundle id" would
    /// also kill the sibling this call was never meant to touch — and the
    /// quit-wait in `restart(_:)` would never see the set empty (the sibling
    /// stays up), stranding the caller.
    public static func runningInstances(of app: InstalledApp) -> [NSRunningApplication] {
        let target = UpdatePolicy.runtimeBundlePath(app.path)
        let candidates = app.bundleID.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        } ?? NSWorkspace.shared.runningApplications
        return candidates.filter { matchesBundlePath($0.bundleURL, target: target) }
    }

    /// True when a running instance's bundle URL resolves — after normalising
    /// away DuoUpdater's own staging suffixes — to `target`, an on-disk bundle
    /// path already run through `UpdatePolicy.runtimeBundlePath`. Split out from
    /// `runningInstances(of:)` as the one piece of that filter that's pure
    /// enough to unit test without a live `NSRunningApplication`.
    static func matchesBundlePath(_ candidateBundleURL: URL?, target: String) -> Bool {
        guard let candidateBundleURL else { return false }
        return UpdatePolicy.runtimeBundlePath(candidateBundleURL) == target
    }

    /// Was one of these instances the app the user is actually looking at?
    ///
    /// Must be read *before* anything is quit — it decides whether the relaunch
    /// takes the foreground. An app the user had in front should come back in
    /// front, since that's their working context; an app that was buried must
    /// come back buried — an update is not a reason to shove a window in front
    /// of what someone is typing into.
    public static func isFrontmost(_ instances: [NSRunningApplication]) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        return instances.contains { $0.processIdentifier == front.processIdentifier }
    }

    /// Launch an app bundle **without wedging the caller's isolation domain**.
    ///
    /// `NSWorkspace.open(_:)` is synchronous: it doesn't return until
    /// LaunchServices has actually launched the app. For a big bundle — worse,
    /// one just rewritten by its own updater, so nothing is in the page cache —
    /// that's hundreds of milliseconds to a few seconds blocked, during which (in
    /// the menu-bar app) every other row's button is dead and the pointer spins.
    /// `openApplication(at:configuration:)` does the same work off-main and
    /// suspends instead.
    ///
    /// `activates` decides whether the launched app takes the foreground. It
    /// defaults to true (matching `open(_:)`) for launches the caller explicitly
    /// asked for, but every restart-after-update path passes the app's pre-quit
    /// foreground state instead (see `isFrontmost`), so an app that was in the
    /// background comes back in the background.
    @discardableResult
    public static func launchApp(_ bundle: URL, activates: Bool = true) async -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activates
        do {
            _ = try await NSWorkspace.shared.openApplication(at: bundle, configuration: config)
            return true
        } catch {
            Log.install.error(
                "app-restarter: launch failed: \(bundle.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
