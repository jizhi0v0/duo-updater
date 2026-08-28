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
        /// The app itself was running (whether or not anything was nested inside
        /// it), got quit, and we tried to bring it back. `true` if that relaunch
        /// succeeded. Reached only when `main` was non-empty — see `nestedOnly`
        /// for the case where the app itself was never running at all.
        case relaunched(Bool)
        /// The app itself was **not** running — nothing of its own was stale —
        /// but a nested app inside it (Surge's Dashboard, say) was still up,
        /// stranded on the bundle we'd moved aside, so that alone got quit and
        /// relaunched. The app itself is deliberately never started here:
        /// starting something the user had closed is not what a restart is for.
        /// `true` if every nested app that had to come back did — a nested app
        /// skipped because it was already back (its parent reopened it itself)
        /// counts as back.
        case nestedOnly(relaunched: Bool)
    }

    /// Quit every running instance of `app` and relaunch it once they've all
    /// exited. Only a total no-op (`.notRunning`) if *nothing* is running —
    /// neither the app itself nor anything nested inside it. An app that isn't
    /// running while something nested in it still is gets that nested app quit
    /// and relaunched same as always (`.nestedOnly`); the app itself is simply
    /// never one of the things put back.
    ///
    /// Graceful only: quits are `terminate()`, which honours save prompts, never
    /// a force-kill. An app that puts up such a prompt and won't exit is left
    /// running (`.stillRunning`) rather than losing unsaved work.
    @discardableResult
    public static func restart(_ app: InstalledApp) async -> Outcome {
        guard app.bundleID != nil else { return .noBundleID }
        let main = runningInstances(of: app)
        // Apps nested inside this one count as instances of it. They are separate
        // macOS apps with their own bundle ids, not child processes the parent's
        // lifetime governs, so nothing terminates them when the parent quits and
        // macOS does not tear them down either. Left running across the swap they
        // keep executing the pre-swap binary out of the bundle we moved aside —
        // Surge's Dashboard did exactly that, and then could not talk to the new
        // Surge it was no longer part of.
        let nested = nestedRunningInstances(of: app)
        let running = main + nested
        guard !running.isEmpty else { return .notRunning }
        // Sampled before the quit — once every instance is gone, so is the
        // answer — and decides whether the relaunch takes the foreground (see
        // `isFrontmost`).
        //
        // Judged per bundle, not over the union. `isFrontmost(running)` answers
        // "was any of these in front", which is the wrong question once nested apps
        // are in the set: a user working in Surge's Dashboard while Surge itself sat
        // buried would have had Surge shoved in front of them, and the Dashboard —
        // the window they actually had — brought back behind it.
        let frontmostPath = NSWorkspace.shared.frontmostApplication?.bundleURL
            .map { UpdatePolicy.runtimeBundlePath($0) }
        let parentPath = UpdatePolicy.runtimeBundlePath(app.path)
        // Captured before the quit, and normalized: a nested app already stranded
        // on a staged bundle reports the moved-aside path, and what we want to
        // relaunch is its live location.
        let nestedBundles = nested.compactMap(\.bundleURL)
            .map { URL(fileURLWithPath: UpdatePolicy.runtimeBundlePath($0)) }
        for instance in running { instance.terminate() }
        // Wait up to ~30s for a graceful quit. A heavy app (large workspace) can
        // take well over the old 6s to actually exit; bailing early would leave
        // it terminated-but-not-relaunched. The only case given up on is a
        // genuine hang/save-prompt, where the app stays *up* (never stranded down).
        for _ in 0..<150 {
            if allRunningInstances(of: app).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard allRunningInstances(of: app).isEmpty else {
            Log.install.error(
                "app-restarter: \(app.name, privacy: .public) won't quit (likely a save prompt) — leaving it running")
            return .stillRunning
        }
        // Only if it was running. Without this the emptiness guard above — which
        // now passes on a nested app alone — would *start* an app the user had
        // closed: quit Surge, leave its Dashboard up, and a relaunch would open
        // Surge. Nothing of a parent that is not running is stale, so there is
        // nothing for us to put back.
        if main.isEmpty {
            // Put back the nested apps that were open. `nestedBundles` can't be
            // empty here: `running` (= main + nested) was non-empty and main is,
            // so something in `nested` was — and `nested.compactMap(\.bundleURL)`
            // can't drop it, because `nestedRunningInstances(of:)` only ever
            // admits instances with a non-nil `.app` `bundleURL` in the first
            // place (`isNestedInside` requires one to test containment;
            // `isStandaloneNestedApp` requires `bundleURL?.pathExtension == "app"`).
            // So `nestedBundles.count == nested.count` always, and it's non-empty
            // here too.
            let results = await reopenNestedApps(nestedBundles, frontmostPath: frontmostPath)
            let relaunched = allNestedBack(results)
            Log.install.info(
                "app-restarter: \(app.name, privacy: .public) was not running itself — only its nested app(s) needed clearing (nested relaunched=\(relaunched, privacy: .public))")
            return .nestedOnly(relaunched: relaunched)
        }
        let relaunched = await launchApp(app.path, activates: frontmostPath == parentPath)
        Log.install.info(
            "app-restarter: \(app.name, privacy: .public) relaunched=\(relaunched, privacy: .public)")
        // Put back the nested apps that were open, after the parent — several only
        // make sense once it is up. Skipped (inside `reopenNestedApps`) when the
        // parent has already reopened one itself, which is common and would
        // otherwise be a second launch of an app that is now running.
        //
        // Result discarded on purpose, not an oversight: `.relaunched`'s Bool
        // answers only for the parent. Folding a nested miss in here would report
        // `false` for a parent that came back fine and swallow a correct "Now
        // running X" notification — one of the wrong fixes issue #72 called out.
        // Each nested app's own outcome is already reported by its own log line
        // inside `reopenNestedApps`.
        _ = await reopenNestedApps(nestedBundles, frontmostPath: frontmostPath)
        return .relaunched(relaunched)
    }

    /// Relaunch each nested app that was quit alongside its parent, skipping any
    /// the parent already brought back itself. One result per bundle, in order —
    /// `true` for a launch that succeeded and for one skipped because it was
    /// already back.
    private static func reopenNestedApps(_ bundles: [URL], frontmostPath: String?) async -> [Bool] {
        var results: [Bool] = []
        for bundle in bundles {
            let target = UpdatePolicy.runtimeBundlePath(bundle)
            let alreadyBack = NSWorkspace.shared.runningApplications.contains {
                matchesBundlePath($0.bundleURL, target: target)
            }
            guard !alreadyBack else {
                Log.install.debug(
                    "app-restarter: \(bundle.lastPathComponent, privacy: .public) already reopened by its parent")
                results.append(true)
                continue
            }
            let back = await launchApp(bundle, activates: frontmostPath == target)
            Log.install.info(
                "app-restarter: nested \(bundle.lastPathComponent, privacy: .public) relaunched=\(back, privacy: .public)")
            results.append(back)
        }
        return results
    }

    /// Whether every nested app we tried to bring back is back. Split out as the
    /// pure half of the `main.isEmpty` branch above — the only piece of that path
    /// testable without a live `NSWorkspace`.
    static func allNestedBack(_ results: [Bool]) -> Bool {
        results.allSatisfy { $0 }
    }

    /// Every live process belonging to this bundle — the app itself and anything
    /// nested inside it. The set the quit-wait has to watch: waiting only on the
    /// parent declared success while a nested app was still up, and the swap then
    /// moved the bundle out from under it.
    public static func allRunningInstances(of app: InstalledApp) -> [NSRunningApplication] {
        runningInstances(of: app) + nestedRunningInstances(of: app)
    }

    /// Running apps whose bundle lives *inside* `app`'s bundle.
    ///
    /// Found by asking what is running rather than by walking the bundle on disk,
    /// so it holds at any nesting depth and still finds a process whose bundle has
    /// already been moved aside by a swap (`runtimeBundlePath` maps that back).
    /// Neither filter in `runningInstances(of:)` can see these: a nested app has
    /// its own bundle id, so it is never in the parent's candidate set, and its
    /// path is a child of the target rather than equal to it.
    public static func nestedRunningInstances(of app: InstalledApp) -> [NSRunningApplication] {
        let target = UpdatePolicy.runtimeBundlePath(app.path)
        return NSWorkspace.shared.runningApplications.filter {
            isNestedInside($0.bundleURL, target: target) && isStandaloneNestedApp($0)
        }
    }

    /// Whether a nested running process is a *standalone app* rather than a piece
    /// of machinery its parent owns.
    ///
    /// Being nested is not enough, and the first version of this got it wrong: a
    /// bare containment test also catches every Chromium renderer
    /// (`…/Frameworks/Claude Helper.app`, `Google Chrome Helper.app`), XPC services,
    /// `.appex` extensions and CEF servers. Terminating those is pointless — the
    /// parent starts and stops them — and launching one again afterwards is worse
    /// than pointless, since a renderer started on its own does nothing.
    ///
    /// The line is the activation policy. Measured across the 13 nested processes
    /// running on the development machine, exactly one was `.regular`: Surge's
    /// Dashboard, the only one with a UI of its own. Every helper, renderer, XPC
    /// service and extension was `.accessory` or `.prohibited`. That is not a
    /// coincidence of the sample — a component a parent manages has no reason to
    /// present itself to the user, and an app the user opened does.
    ///
    /// The cost is a nested *accessory* app — a menu-bar utility living inside
    /// another bundle — which this will not relaunch. That is the safe direction to
    /// be wrong in: missing one leaves the user to reopen it, while quitting a
    /// renderer mid-swap breaks the app we are updating.
    static func isStandaloneNestedApp(_ candidate: NSRunningApplication) -> Bool {
        guard candidate.bundleURL?.pathExtension == "app" else { return false }
        return candidate.activationPolicy == .regular
    }

    /// True when a running instance's bundle URL resolves — after normalising away
    /// DuoUpdater's staging names — to a path strictly *inside* `target`. Split out
    /// as the pure half of `nestedRunningInstances(of:)`, like `matchesBundlePath`.
    /// The trailing separator matters: without it a sibling named `Surge Beta.app`
    /// would read as nested inside `Surge.app`.
    static func isNestedInside(_ candidateBundleURL: URL?, target: String) -> Bool {
        guard let candidateBundleURL else { return false }
        let path = UpdatePolicy.runtimeBundlePath(candidateBundleURL)
        return path != target && path.hasPrefix(target + "/")
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
    public static func launchApp(
        _ bundle: URL, activates: Bool = true, timeout: Duration = launchTimeout
    ) async -> Bool {
        return await firstToFinish(timeout: timeout, fallback: false) {
            Log.install.error(
                "app-restarter: launch timed out: \(bundle.lastPathComponent, privacy: .public) — LaunchServices never came back")
        } operation: {
            // Built inside the operation, not captured: `OpenConfiguration` is a
            // non-Sendable class, and the operation has to cross an isolation
            // boundary to race the timer.
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

    /// How long `launchApp` gives LaunchServices before it stops waiting.
    ///
    /// `openApplication` has no timeout of its own, and a launch that never comes
    /// back is not a local failure. `restart(_:)` never returns either, so its
    /// caller's `defer` never runs and the row stays on "Relaunching…"
    /// indefinitely: its Restart button is dead behind the re-entry guard, and the
    /// self-update idle probe — which refuses to fire while anything is still
    /// waiting to be relaunched — keeps Duo Updater from updating *itself* until
    /// it is quit. Giving up does not get the app open, but it stops one wedged
    /// launch from taking the rest of the app down with it.
    ///
    /// A minute is deliberately far past a normal launch. The slow case we know
    /// of is a bundle we just replaced: nothing of it is in the page cache and
    /// Gatekeeper re-validates the whole thing, which is seconds even at WeChat's
    /// half a gigabyte.
    public static let launchTimeout: Duration = .seconds(60)

    /// Await `operation`, or answer `fallback` once `timeout` elapses — **without
    /// waiting for the abandoned operation to finish**.
    ///
    /// That last part is the whole point, and it is why this is not a
    /// `withTaskGroup`: a group awaits every child before it returns, so a child
    /// wedged in a system call that ignores cancellation would hold the group open
    /// and the timeout would be decorative. Here whichever side finishes first
    /// resumes the continuation and the loser runs on unobserved.
    static func firstToFinish<T: Sendable>(
        timeout: Duration,
        fallback: T,
        onTimeout: @Sendable @escaping () -> Void = {},
        operation: @Sendable @escaping () async -> T
    ) async -> T {
        let once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let timer = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled, once.claim() else { return }
                onTimeout()
                continuation.resume(returning: fallback)
            }
            Task {
                let value = await operation()
                guard once.claim() else { return }
                timer.cancel()
                continuation.resume(returning: value)
            }
        }
    }
}

/// One-shot latch: the first caller to `claim()` gets true, every later one gets
/// false. Guards a `CheckedContinuation` that two racing tasks can reach, where a
/// second `resume` would trap.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
