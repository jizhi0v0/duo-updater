import Foundation
import CryptoKit

/// Performs the fetch-and-apply half of an install, for every route that does
/// not need a GUI.
///
/// This is the part the menu-bar app and `duo install` must not each have a copy
/// of: which installer handles which source, when the download and apply permits
/// are taken and — the subtle one — when they are *given back*. The apply permit
/// is released the instant the swap lands, because everything after it (waiting
/// for a process to quit, asking for a relaunch) is user time, and a permit held
/// through user time throttles the whole queue for nothing.
///
/// What stays with the caller: progress display, traffic accounting, backups,
/// restart bookkeeping, and turning an error into a permission prompt. Those are
/// all things the two hosts legitimately do differently.
///
/// The App Store route is deliberately absent. It needs either the privileged
/// helper (whose `SMAppService.daemon` registration requires an app bundle) or
/// the Accessibility API driving App Store.app, so it cannot be honestly shared
/// with a command-line tool. `duo install` refuses it with a message rather than
/// half-doing it.
///
/// The Xcode route is here but needs its downloader injected: fetching an
/// Xcode archive takes an Apple ID session, which lives in the menu-bar app's
/// web view. The app passes an `XcodeArchiveDownloading`; `duo` passes none and
/// the route refuses.
public actor InstallCoordinator {

    /// Which installer applies this update. Derived from the source name rather
    /// than chosen by the caller, so both hosts route identically.
    public enum Route: String, Sendable, CaseIterable {
        case homebrew
        /// A `.pkg`: downloaded, then handed to the system installer, which the
        /// user finishes. We never see it land.
        case installer
        case vendor
        case sparkle
        case appStore
        /// An Xcode `.xip` from Apple's developer site. The bytes come through the
        /// host's `XcodeArchiveDownloading` (an Apple ID session only the menu-bar
        /// app has); a coordinator built without one refuses this route.
        case xcode
    }

    public enum CoordinatorError: LocalizedError {
        case routeNotSupportedHere(Route)
        case missingCaskToken
        case notAnUpdate

        public var errorDescription: String? {
            switch self {
            case .routeNotSupportedHere(.xcode):
                return "Xcode downloads need your Apple ID sign-in, which only the menu-bar app has"
            case .routeNotSupportedHere(let route):
                return "the \(route.rawValue) route cannot be driven from here"
            case .missingCaskToken:
                return "the Homebrew source did not name a cask to upgrade"
            case .notAnUpdate:
                return "this app has no update to install"
            }
        }
    }

    /// What an install produced, for the caller's bookkeeping.
    public struct Outcome: Sendable {
        /// Bytes we measured ourselves. Zero for routes where another tool does
        /// the fetching (Homebrew, the App Store) — deliberately not estimated,
        /// so every recorded number is one we actually counted.
        public let bytesDownloaded: Int64
        /// The host the download ended on after redirects, for the traffic log.
        public let finalHost: String?
        /// Where the downloaded `.pkg` was left. The system installer owns the
        /// finish, so the caller offers "Install" (re-open this exact file)
        /// rather than downloading it again.
        public let stagedPackageURL: URL?
        /// Whether the new version is on disk now. False for `.installer`, where
        /// the user still has a window to click through.
        public let applied: Bool
        /// True only when a Sparkle binary patch was actually applied. Merely
        /// publishing a matching patch is not enough: a failed delta route retries
        /// the full archive and reports false, so the traffic ledger records what
        /// happened rather than what the feed offered.
        public let usedDelta: Bool
        /// Bundle ids of the login-item agents the recipe asked us to restart
        /// after the swap (`LoginItemAgentRestart`) that are not confirmed
        /// running from the new bundle. Empty for every app that declares none.
        public let agentsNotRestarted: [String]

        public init(
            bytesDownloaded: Int64,
            finalHost: String?,
            stagedPackageURL: URL?,
            applied: Bool,
            usedDelta: Bool = false,
            agentsNotRestarted: [String] = []
        ) {
            self.bytesDownloaded = bytesDownloaded
            self.finalHost = finalHost
            self.stagedPackageURL = stagedPackageURL
            self.applied = applied
            self.usedDelta = usedDelta
            self.agentsNotRestarted = agentsNotRestarted
        }
    }

    /// How many downloads and applies may run at once. Shared by both hosts, but
    /// per-process: two processes installing at the same time is what
    /// ``InstallLock`` prevents, not this.
    private let permits: InstallPermits
    private let vendor: VendorInstaller
    private let sparkle = SparkleInstaller()
    private let homebrew = HomebrewInstaller()
    private let packages = PackageInstaller()
    /// The `.xcode` route's downloader, or nil where there is none (the CLI).
    private let xcodeDownloader: (any XcodeArchiveDownloading)?
    /// The live process list `NestedAppGuard` reads before a swap. A seam for
    /// tests.
    private let runningProcesses: @Sendable () -> [NestedAppGuard.RunningProcess]
    /// The process list and signal `LoginItemAgentRestart` uses around a swap.
    /// Seams for tests.
    private let agentProcesses: @Sendable () -> [LoginItemAgentRestart.Process]
    private let signalAgent: @Sendable (pid_t, Int32) -> Void
    private let agentJobPID: @Sendable (String) async -> pid_t?
    /// Free space claimed by this process's installs. See `DiskSpaceGuard`.
    private let space: DiskSpaceGuard.SpaceLedger

    public init(
        permits: InstallPermits = InstallPermits(downloads: 4, applies: 2),
        xcodeDownloader: (any XcodeArchiveDownloading)? = nil,
        runningProcesses: @escaping @Sendable () -> [NestedAppGuard.RunningProcess] = NestedAppGuard.liveProcesses,
        space: DiskSpaceGuard.SpaceLedger = .shared,
        vendor: VendorInstaller = VendorInstaller(),
        agentProcesses: @escaping @Sendable () -> [LoginItemAgentRestart.Process] = LoginItemAgentRestart.liveProcesses,
        signalAgent: @escaping @Sendable (pid_t, Int32) -> Void = { _ = kill($0, $1) },
        agentJobPID: @escaping @Sendable (String) async -> pid_t? = LoginItemAgentRestart.launchdJobPID
    ) {
        self.agentProcesses = agentProcesses
        self.signalAgent = signalAgent
        self.agentJobPID = agentJobPID
        self.permits = permits
        self.vendor = vendor
        self.space = space
        self.xcodeDownloader = xcodeDownloader
        self.runningProcesses = runningProcesses
    }

    /// The refusal a host must check BEFORE it touches anything for this
    /// install. Clearing a staged self-update changes state, and so does taking a
    /// rollback point: retention is one per app, so a refused install that had
    /// already backed up would lose the previous rollback point.
    ///
    /// Only the routes whose swap this coordinator performs or starts: `.sparkle`
    /// and `.vendor` (`fetchThenSwap`) and `.homebrew`. `perform` asks again
    /// before the download and before the apply, for a nested app started in the
    /// meantime.
    public static func nestedAppRefusal(
        for result: UpdateResult, route: Route,
        processes: () -> [NestedAppGuard.RunningProcess] = NestedAppGuard.liveProcesses
    ) -> NestedAppRunningError? {
        switch route {
        case .sparkle, .vendor, .homebrew:
            return NestedAppGuard.refusal(
                result.app.path, appName: result.app.name, processes: processes)
        case .installer, .appStore, .xcode:
            return nil
        }
    }

    /// Throws `NestedAppRunningError` when an app nested in `result`'s bundle is
    /// running on its own (see `NestedAppGuard`).
    private func refuseWhileNestedAppRuns(_ result: UpdateResult) throws {
        try NestedAppGuard.check(
            result.app.path, appName: result.app.name, processes: runningProcesses)
    }

    /// The route an update takes.
    ///
    /// Total on purpose, with `.sparkle` as the fallback rather than a nil that
    /// would mean "unroutable": that is what the menu-bar app's switch has
    /// always done, and an appcast is the right guess for a source we do not
    /// otherwise recognise. It is not a licence to call this for anything —
    /// callers must still gate on `UpdatePolicy.canAutoInstall` /
    /// `requiresInstaller`, which is what keeps detection-only apps out.
    public static func route(for result: UpdateResult, requiresInstaller: Bool) -> Route {
        if requiresInstaller { return .installer }
        switch result.remote?.sourceName {
        case "Homebrew":                    return .homebrew
        case "Vendor", "GitHub", "Electron", MyGoUpdateSource.sourceName: return .vendor
        case "App Store":                   return .appStore
        case XcodeReleasesSource.sourceName: return .xcode
        default:                            return .sparkle
        }
    }

    /// Whether to take a rollback point before this route runs.
    ///
    /// Every route, including `.appStore`. That one used to be excluded on the
    /// grounds that "the store can always re-fetch a prior build, so a local copy
    /// of a multi-gigabyte bundle is dead weight" — which is not true. The App
    /// Store offers only an app's *current* version; there is no user-facing way
    /// to ask it for the build you were running yesterday. (Its one backward-
    /// looking prompt, "install the last compatible version", fires when the
    /// current release needs a newer macOS than the machine has, and is not
    /// rollback.) So the App Store route was the one route that applied an update
    /// with no way back at all.
    ///
    /// The copy needs no privileges: App Store bundles are `root:wheel` 755 but
    /// every file in them is world-readable (checked across all 22 store-installed
    /// apps on the development machine — none had an unreadable file), and the
    /// `_MASReceipt` travels with the bundle, so a restored copy carries the
    /// receipt that was issued *for it* rather than a mismatched newer one.
    /// Restoring one does need an administrator, because the installed bundle is
    /// root-owned — `InPlaceSwap.needsElevatedReplace` recognises that and routes
    /// it to the privileged swap. What a rollback here cannot do is make the store
    /// forget: it will list the update again, and re-apply it on its own if
    /// automatic app updates are on. The restore path says so.
    ///
    /// It is not free, and the tempting "APFS clones it, so it costs nothing"
    /// argument only covers half the work. `ditto` into the backup store *is* a
    /// clone (2750 MB of Word in 8.7s for ~16 MB of new blocks), but `save` then
    /// fingerprints the copy, and `BackupManifest.compute` streams a SHA-256 over
    /// every byte — another 8.7s for that same bundle. Store apps are the largest
    /// things we back up, so this route is where that lands hardest: budget for
    /// roughly a second per 150 MB before the update starts moving. The clone's
    /// blocks then become the backup's own once the update replaces the original,
    /// which is when a rollback point starts costing what it is worth.
    ///
    /// `.installer` is included, with a caveat the restore path surfaces: a
    /// `.pkg` can lay down helpers, daemons and launch items beside the `.app`,
    /// and we only ever copy the bundle — so restoring gives an older app next
    /// to newer components rather than a clean rollback. It is still worth
    /// having. Before this, pkg-route apps had no rollback point *at all*, which
    /// is the case where you most want one: the system installer's change is the
    /// one we cannot watch land or undo ourselves.
    public static func wantsBackup(_ route: Route) -> Bool {
        // Left as an exhaustive switch rather than a bare `true`: a new route has
        // to state its answer here, which is the decision this function exists for.
        switch route {
        // `.xcode` included: a ~4 GB bundle, cloned by `ditto` and then hashed
        // in full by `BackupManifest.compute` — see the cost note above.
        case .homebrew, .vendor, .sparkle, .installer, .appStore, .xcode: return true
        }
    }

    /// Whether to take an install rollback point before this route runs — the
    /// automatic one, for a user with no backup being taken (see
    /// ``BackupStore/Purpose/installRollbackPoint``).
    ///
    /// Only the routes that hand the swap to someone else, because only those
    /// can leave the app missing when cut off: `brew install --cask --force`
    /// on an installed cask copies the old bundle into the Caskroom backup and
    /// removes it from `/Applications` before it moves the new one in, and its
    /// rescue restores it only for a StandardError — not for a signal, and an
    /// EPIPE's rescue writes to the dead pipe before the revert (Homebrew
    /// 7.0.9, read from source; the EPIPE path is not measured).
    /// What `mas` and App Store do inside is not known, so they count as able
    /// to. The routes whose swap is ours (`.sparkle`, `.vendor`, `.xcode`)
    /// cannot: unprivileged it is an atomic exchange, elevated the shell puts
    /// the original back itself, and launch recovers either.
    ///
    /// What a rollback point is for is narrower than "a third party swaps":
    /// it is OUR process dying mid-install and taking the installer down with
    /// it — a brew child dies on its next write to the stdout pipe we held
    /// (measured, with the parent SIGKILLed), and brew's next line falls
    /// between deleting the old app and moving the new one in. `.installer` is
    /// left out for that reason. A package handed to Installer.app is
    /// installed by Installer, in its own process, which our death cannot
    /// interrupt; and we never see it succeed — `perform` returns with the
    /// window still open — so nothing would ever discard a point taken there.
    /// It could only leak, growing to the app's full size once the package
    /// replaces the blocks the clone shares.
    ///
    /// Never when a user backup is being taken for this install: that backup
    /// IS the rollback point, and a second copy would buy nothing.
    public static func wantsInstallRollbackPoint(_ route: Route, takingUserBackup: Bool) -> Bool {
        guard !takingUserBackup else { return false }
        // Exhaustive for the same reason as `wantsBackup`: a new route has to
        // state whether someone else does its swap.
        switch route {
        case .homebrew, .appStore: return true
        case .installer, .sparkle, .vendor, .xcode: return false
        }
    }

    /// Take the install rollback point for `app`. Silent by design — the user
    /// asked for no backup, and this is not one to be told about unless it is
    /// needed — so the outcome is logged and returned, never surfaced. A copy
    /// that fails does not stop the install, exactly as a failed backup does
    /// not.
    ///
    /// Not taken over an earlier install of the app that was cut off or is
    /// still running, for the reason ``backUp(_:route:)`` gives.
    @discardableResult
    public static func takeInstallRollbackPoint(_ app: InstalledApp, route: Route) async -> Bool {
        let standing = InstallJournal.standing(of: app.path)
        guard standing == .clear else {
            Log.install.notice(
                "rollback point: \(app.path.lastPathComponent, privacy: .public) not saved — an earlier install of it \(standing == .interrupted ? "was cut off" : "is still running", privacy: .public); its way back stays as it is")
            return false
        }
        let key = BackupStore.key(bundleID: app.bundleID, path: app.path)
        // Held until `settleInstallRollbackPoint` lets go, so the launch sweep
        // cannot discard this point while the install it guards is running —
        // the app is intact right up to the third party's swap, which is
        // exactly what the sweep reads as "no longer needed".
        await InstallRollbackPointClaims.shared.beginTaking(key)
        do {
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app.path, key: key,
                // The same label/comparison pair `backUp` records.
                version: app.shortVersion ?? app.buildVersion,
                buildVersion: app.buildVersion, bundleID: app.bundleID,
                fromPackageInstall: route == .installer, fromAppStore: route == .appStore)
            Log.install.notice(
                "rollback point: saved \(app.path.lastPathComponent, privacy: .public) before \(String(describing: route), privacy: .public)")
            return true
        } catch is CancellationError {
            // Not "installing without one": the caller stops the install.
            Log.install.notice(
                "rollback point: \(app.path.lastPathComponent, privacy: .public) not saved — the install was cancelled")
            return false
        } catch {
            Log.install.error(
                "rollback point: \(app.path.lastPathComponent, privacy: .public) not saved, installing without one — \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// What taking a rollback point did. Never fatal — the caller decides
    /// whether to proceed without a safety net — but never swallowed either, or
    /// the user finds out only when a rollback later finds nothing.
    public enum BackupOutcome: Sendable, Equatable {
        case saved
        /// The bundle is not fully readable by us, so no copy was attempted.
        /// `path` is the first file that stopped it.
        case unreadable(path: String)
        /// Stored, but without files the app had written into its own bundle.
        /// It restores; whatever state lived in them is lost.
        case savedWithoutRuntimeState(omitted: Int)
        /// Skipped, or stopped mid-copy, because this Mac is too low on space
        /// to hold a copy. See ``BackupStore/freeSpaceFloorBytes``.
        case insufficientSpace
        /// Stopped mid-copy because the install was cancelled. Nothing of the
        /// copy is kept; an earlier backup of the app is untouched. The caller
        /// stops the install as cancelled rather than going on without one.
        case cancelled
        /// Not attempted: an earlier install of the app was cut off, or is
        /// still running (`InstallJournal.standing`). The bundle may be the
        /// one it left damaged, or one it is halfway through swapping, and a
        /// copy would replace the earlier backup — one slot per app — that is
        /// the way back to the app as it was. That backup is untouched.
        case skippedForEarlierInstall(InstallJournal.Standing)
        case failed
    }

    /// Store a rollback point for `app`.
    ///
    /// Every caller goes through here — an install's backup, and a
    /// Relaunch's (`StagedRelaunchBackup.take`) — so the check that the copy
    /// would not overwrite an interrupted install's way back is made here,
    /// not at each call site.
    public static func backUp(_ app: InstalledApp, route: Route) async -> BackupOutcome {
        let standing = InstallJournal.standing(of: app.path)
        guard standing == .clear else {
            Log.install.notice(
                "backup: \(app.path.lastPathComponent, privacy: .public) not backed up — an earlier install of it \(standing == .interrupted ? "was cut off" : "is still running", privacy: .public); its backup stays as it is")
            return .skippedForEarlierInstall(standing)
        }
        let key = BackupStore.key(bundleID: app.bundleID, path: app.path)
        // Recorded as a PAIR now: written marketing-first ALONE, the label was
        // "1.0" for every build of a frozen-marketing app, and the workbench's
        // "is a rollback a no-op" filter then hid the Rollback row after a real
        // update.
        //
        // `version` keeps its `?? buildVersion` fallback, which is not redundant:
        // it is the DISPLAY label (the Backups sheet, `duo backups list`, the
        // row's "restored to X"), and an app whose Info.plist carries only
        // `CFBundleVersion` would otherwise be listed with no version at all.
        // `buildVersion` is the separate comparison half.
        let version = app.shortVersion ?? app.buildVersion
        let buildVersion = app.buildVersion
        let fromPackage = (route == .installer)
        let fromStore = (route == .appStore)
        let path = app.path
        let bundleID = app.bundleID
        // The bundle walk goes to Dispatch — not `Task.detached`, which still runs
        // on the cooperative pool. It was one hop for everything below, measured at
        // 8.7s twice over for Word, 8.7s of a pool only as wide as the core count.
        // The two `ditto` copies inside no longer need it (`ChildProcess` awaits
        // them without parking a thread), and `BackupStore.save` hops its own
        // whole-bundle walks. See `offCooperativePool`.
        // Only *sealed* unreadable files stop a backup. Unsealed ones are the
        // app's own runtime droppings; the copy skips them and still restores.
        let unreadable = await offCooperativePool(qos: .userInitiated) {
            BackupManifest.unreadableFiles(in: path)
        }
        if let blocked = unreadable.sealed.first {
            return .unreadable(path: path.appendingPathComponent(blocked).path)
        }
        // Held until `settlePendingBackup` lets go, so the launch sweep cannot
        // decide this key's pending copy while the install it is for runs.
        await InstallRollbackPointClaims.pendingBackups.beginTaking(key)
        do {
            // Pending, not over the user's backup: that stays the rollback
            // point until the install changes the app, so a cancel or a
            // failure from here on cannot cost it (`settlePendingBackup`).
            try await BackupStore.savePending(
                appPath: path, key: key, version: version,
                buildVersion: buildVersion, bundleID: bundleID,
                fromPackageInstall: fromPackage, fromAppStore: fromStore)
            // An input method's settings and learned dictionary live outside
            // its bundle, so the bundle rollback point above cannot speak for
            // them — and they are exactly what went missing when this app's
            // one-click for WeType was withdrawn. Cloned, so it is close to
            // free; deliberately AFTER the save, whose staging directory
            // replaces the key directory wholesale — the pending one, which
            // it moves with when promoted. See `InputMethodDataBackup`.
            //
            // Not folded into `BackupOutcome`: this is not a reason to change
            // what the user is told about the *bundle* rollback, and the
            // outcome enum is switched over in both the app and the CLI.
            if InPlaceSwap.usesContentsRotation(target: path) {
                let captured = await InputMethodDataBackup.save(
                    bundleName: path.deletingPathExtension().lastPathComponent,
                    bundleID: bundleID, key: key, in: BackupStore.pendingBackupsRoot)
                if captured.isEmpty {
                    Log.install.error(
                        "user data: captured nothing for \(path.lastPathComponent, privacy: .public) — a rollback will restore the bundle only")
                } else {
                    // Leaf names, not full paths: these all live under the
                    // user's home, and the leaf is what identifies the location
                    // while the prefix is only their account name.
                    Log.install.notice(
                        "user data: snapshotted \(captured.count, privacy: .public) location(s) for \(path.lastPathComponent, privacy: .public): \(captured.map(\.original.lastPathComponent).joined(separator: ", "), privacy: .public)")
                }
            }
            return unreadable.unsealed.isEmpty
                ? .saved
                : .savedWithoutRuntimeState(omitted: unreadable.unsealed.count)
        } catch BackupStore.BackupError.insufficientSpace {
            // `save` has already logged what it measured.
            return .insufficientSpace
        } catch is CancellationError {
            // `save` has already logged it and removed its staging.
            return .cancelled
        } catch {
            // The identity of the error is the whole diagnosis, and collapsing
            // every `BackupError` into a bare `.failed` threw it away: the log
            // could say a backup failed but never which of the half-dozen
            // throws in `save` fired, so a report could not be acted on without
            // first reproducing it. Each of those sites now says what it saw;
            // this records which one won.
            Log.install.error(
                "backup: \(path.lastPathComponent, privacy: .public) failed — \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Fetch and apply `result` by `route`.
    ///
    /// - Parameter releaseAfterDownload: called once per download attempt, as soon
    ///   as the bytes are down (or as soon as a tool that fetches on our behalf
    ///   finishes), so a per-host gate the caller holds can be handed to the next
    ///   app rather than spanning the extract and swap too. A delta-route failure
    ///   that retries with the full archive downloads twice and so calls this
    ///   twice. Must be idempotent — it is not called at all on paths that never
    ///   reach a download.
    /// - Parameter beforeInstallerOpen: `.installer` route only — runs after the
    ///   package passes the gate and before it reaches macOS's Installer, so the
    ///   caller can retire the window this package supersedes while Installer is
    ///   idle. See `PackageInstaller.handOver`.
    /// - Parameter installedPopulation: every bundle this machine's scan knows
    ///   about, for `SelfUpdaterStash`'s attribution gate — whether anyone ELSE
    ///   claims the updater cache directory this app's download would come from.
    ///   **No default**, so every call site has to answer it rather than one of
    ///   them silently inheriting "unknown"; nil is refused, not assumed safe.
    /// - Parameter digestOnlyAllowed: `UpdateSettings.allowsDigestOnlyInstalls`
    ///   as it stands now, read by the host after its pre-install re-check — the
    ///   offer the row showed may predate the user turning it off. No default,
    ///   for the same reason as `installedPopulation`.
    public func perform(
        _ result: UpdateResult,
        route: Route,
        installedPopulation: [InstalledApp]?,
        digestOnlyAllowed: Bool,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void = {},
        beforeInstallerOpen: @Sendable () async -> Void = {}
    ) async throws -> Outcome {
        // The install path was silent end to end, which made "it said it updated
        // and nothing changed" impossible to answer after the fact — the only
        // evidence was the app's own mtime. `.notice`, so it is still readable when
        // the report arrives hours later.
        let label = "\(result.app.name) [\(result.app.bundleID ?? "?")]"
        // `canAutoInstall` is the offer; this is the gate, for every route, before
        // anything is touched (`OneClickGate`).
        if let gate = OneClickGateRegistry.withholding(result.app) {
            Log.install.notice(
                "install refused: \(label, privacy: .public) — one-click gate: \(gate.reason, privacy: .public)")
            throw OneClickGateRegistry.Withheld(appName: result.app.name, reason: gate.reason)
        }
        Log.install.notice(
            "install start: \(label, privacy: .public) \(result.app.shortVersion ?? "?", privacy: .public) → \(result.remote?.displayVersion ?? "?", privacy: .public) via \(String(describing: route), privacy: .public)")
        do {
            // Every byte fetched by this install is filed against this app, the
            // same way its check was — so "everything that went anywhere for
            // Zed" is one query across both the socket rows and the ledger row.
            let outcome = try await RequestAttribution.withApp(result.app.id) {
                try await withSpaceReserved(result, route: route) { toApply in
                    try await performRoute(
                        result, route: route, installedPopulation: installedPopulation,
                        digestOnlyAllowed: digestOnlyAllowed,
                        spaceToApply: toApply,
                        progress: progress,
                        releaseAfterDownload: releaseAfterDownload,
                        beforeInstallerOpen: beforeInstallerOpen)
                }
            }
            // `applied` is the load-bearing bit: false means the bytes are staged
            // but nothing on disk has changed yet, which is exactly the state that
            // used to be indistinguishable from a finished update.
            Log.install.notice(
                "install returned: \(label, privacy: .public) applied=\(outcome.applied, privacy: .public) bytes=\(outcome.bytesDownloaded, privacy: .public) staged=\(outcome.stagedPackageURL != nil, privacy: .public)")
            return outcome
        } catch let cancelled as CancellationError {
            // Not a failure. The host logs `install cancelled at <stage>`
            // (`InstallAttemptOutcome.cancelled`), knowing the stage.
            throw cancelled
        } catch {
            Log.install.error(
                "install failed: \(label, privacy: .public) via \(String(describing: route), privacy: .public) — \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// `body` with this install's expected use of the boot volume claimed in
    /// the ledger, handing it the share the swap still needs once the archive
    /// is down. Zero, and no claim, for the routes that bring their own check
    /// (`.xcode`: `XcodeInstaller` sizes against the archive) or install
    /// nothing here (`.appStore`).
    private func withSpaceReserved(
        _ result: UpdateResult, route: Route,
        _ body: (Int64) async throws -> Outcome
    ) async throws -> Outcome {
        switch route {
        case .xcode, .appStore:
            return try await body(0)
        case .sparkle, .vendor, .installer, .homebrew:
            let estimate = await DiskSpaceGuard.estimate(for: result.app)
            try await space.reserve(estimate.total)
            do {
                let outcome = try await body(estimate.toApply)
                space.release(estimate.total)
                return outcome
            } catch {
                space.release(estimate.total)
                throw error
            }
        }
    }

    private func performRoute(
        _ result: UpdateResult,
        route: Route,
        installedPopulation: [InstalledApp]?,
        digestOnlyAllowed: Bool,
        spaceToApply: Int64,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void,
        beforeInstallerOpen: @Sendable () async -> Void
    ) async throws -> Outcome {
        switch route {
        case .appStore:
            throw CoordinatorError.routeNotSupportedHere(.appStore)

        case .xcode:
            guard let downloader = xcodeDownloader else {
                throw CoordinatorError.routeNotSupportedHere(.xcode)
            }
            return try await fetchThenSwap(
                result, spaceToApply: 0,
                progress: progress, releaseAfterDownload: releaseAfterDownload,
                download: { try await XcodeInstaller.download($0, using: downloader, onStage: $1) },
                apply: { try await XcodeInstaller.apply($0, download: $1, onStage: $2) })

        case .installer:
            progress(.downloading(fraction: 0))
            let verifyDownload: @Sendable (URL) throws -> Data? = { file in
                try Self.verifyInstallerDownload(file, for: result, progress: progress)
            }
            let opened = try await permits.withDownloadPermit(cancellable: true) {
                // A cancel while queued throws out of the wait itself; this
                // catches one that landed as the permit was handed over.
                try Task.checkCancellation()
                return try await packages.downloadAndOpen(
                    url: result.remote?.downloadURL,
                    installedApp: result.app.path,
                    headers: result.remote?.downloadHeaders ?? [:],
                    onStage: progress,
                    verifyDownload: verifyDownload,
                    beforeOpen: beforeInstallerOpen)
            }
            await releaseAfterDownload()
            return Outcome(
                bytesDownloaded: opened.bytesDownloaded, finalHost: opened.finalHost,
                stagedPackageURL: opened.packageURL, applied: false)

        case .homebrew:
            guard let token = result.remote?.sourceIdentifier else {
                throw CoordinatorError.missingCaskToken
            }
            // brew moves the bundle aside like our own swap does, so it gets the
            // same refusal, before brew is started.
            try refuseWhileNestedAppRuns(result)
            progress(.runningCommand("starting brew…"))
            // brew's fetch and swap are one command we cannot split, so the whole
            // run takes the apply permit — and brew does its own downloading, so
            // those bytes are never counted rather than estimated.
            // Cancelled while queued: throws holding no permit, before brew starts.
            try await permits.waitForApplyOrCancel()
            var applyHeld = true
            defer { if applyHeld { permits.signalApply() } }
            // Still needed: a cancel landing as the permit was handed over
            // returns normally with the permit held (see `waitForDownloadOrCancel`).
            try Task.checkCancellation()
            let agents = snapshotLoginItemAgents(result)
            try await homebrew.upgrade(caskToken: token) { line in
                progress(.runningCommand(line))
            }
            permits.signalApply()
            applyHeld = false
            await releaseAfterDownload()
            return Outcome(
                bytesDownloaded: 0, finalHost: nil, stagedPackageURL: nil, applied: true,
                agentsNotRestarted: await restartLoginItemAgents(agents))

        case .vendor:
            do {
                return try await vendorRoute(
                    result, useLocalStash: true, installedPopulation: installedPopulation,
                    digestOnlyAllowed: digestOnlyAllowed, spaceToApply: spaceToApply,
                    progress: progress, releaseAfterDownload: releaseAfterDownload)
            } catch let failure as LocalStashFailure {
                // The bytes the app's own updater parked did not unpack or did not
                // pass a gate, and a retry would pick the same file again until
                // that updater replaced it. Take the route's own artifact instead,
                // verified as usual. The stash spent no network bytes, so there is
                // nothing to add to what the retry reports.
                Log.install.notice("local stash failed, downloading the route's own artifact: \(result.app.name, privacy: .public) — \(failure.errorDescription ?? "unknown", privacy: .public)")
                return try await vendorRoute(
                    result, useLocalStash: false, installedPopulation: installedPopulation,
                    digestOnlyAllowed: digestOnlyAllowed, spaceToApply: spaceToApply,
                    progress: progress, releaseAfterDownload: releaseAfterDownload)
            }

        case .sparkle:
            do {
                return try await fetchThenSwap(
                    result, spaceToApply: spaceToApply,
                    progress: progress, releaseAfterDownload: releaseAfterDownload,
                    download: {
                        try await self.sparkle.download($0, preferDelta: true, onStage: $1)
                    },
                    apply: { _ = try await self.sparkle.apply($0, download: $1, onStage: $2) })
            } catch let failure as DeltaRouteFailure {
                // The patch route didn't work out; take the full archive, which is
                // always published alongside it. Only `DeltaRouteFailure` lands here
                // — a gate failure on the full route is a real refusal and must not
                // be retried. The second pass re-acquires both permits, which is
                // correct: it is a second download competing for the same budget.
                Log.install.info("delta route failed, retrying with the full archive: \(result.app.name, privacy: .public) — \(failure.errorDescription ?? "unknown", privacy: .public)")
                // The patch's bytes were spent whether or not it worked, so they
                // belong in the total this install reports.
                return try await withBytes(failure.bytesSpent) { try await fetchThenSwap(
                    result, spaceToApply: spaceToApply,
                    progress: progress, releaseAfterDownload: releaseAfterDownload,
                    download: {
                        try await self.sparkle.download($0, preferDelta: false, onStage: $1)
                    },
                    apply: { _ = try await self.sparkle.apply($0, download: $1, onStage: $2) }) }
            }
        }
    }

    /// The `.vendor` route, with its delta retry. `useLocalStash` is false on the
    /// retry after a `LocalStashFailure`, for both passes.
    private func vendorRoute(
        _ result: UpdateResult,
        useLocalStash: Bool,
        installedPopulation: [InstalledApp]?,
        digestOnlyAllowed: Bool,
        spaceToApply: Int64,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void
    ) async throws -> Outcome {
        do {
            return try await fetchThenSwap(
                result, spaceToApply: spaceToApply,
                progress: progress, releaseAfterDownload: releaseAfterDownload,
                download: {
                    try await self.vendor.download(
                        $0, preferDelta: true, useLocalStash: useLocalStash,
                        population: installedPopulation, onStage: $1)
                },
                apply: {
                    _ = try await self.vendor.apply(
                        $0, download: $1, digestOnlyAllowed: digestOnlyAllowed, onStage: $2)
                })
        } catch let failure as DeltaRouteFailure {
            Log.install.info("delta route failed, retrying with the full archive: \(result.app.name, privacy: .public) — \(failure.errorDescription ?? "unknown", privacy: .public)")
            // The patch's bytes were spent whether or not it worked, so they
            // belong in the total this install reports.
            return try await withBytes(failure.bytesSpent) { try await fetchThenSwap(
                result, spaceToApply: spaceToApply,
                progress: progress, releaseAfterDownload: releaseAfterDownload,
                download: {
                    try await self.vendor.download(
                        $0, preferDelta: false, useLocalStash: useLocalStash,
                        population: installedPopulation, onStage: $1)
                },
                apply: {
                    _ = try await self.vendor.apply(
                        $0, download: $1, digestOnlyAllowed: digestOnlyAllowed, onStage: $2)
                }) }
        }
    }

    /// Add bytes already spent on an abandoned attempt to whatever the retry reports.
    private func withBytes(
        _ extra: Int64, _ body: () async throws -> Outcome
    ) async rethrows -> Outcome {
        let outcome = try await body()
        guard extra > 0 else { return outcome }
        return Outcome(
            bytesDownloaded: outcome.bytesDownloaded + extra,
            finalHost: outcome.finalHost,
            stagedPackageURL: outcome.stagedPackageURL,
            applied: outcome.applied,
            usedDelta: outcome.usedDelta,
            agentsNotRestarted: outcome.agentsNotRestarted)
    }

    /// Source-specific proof over a package route's original download. A Sparkle
    /// package bypasses SparkleInstaller's archive path, but must not bypass Gate 1:
    /// EdDSA covers the exact enclosure (the outer DMG when the pkg is wrapped).
    /// Any other Developer-ID package is checked against `expectedSHA256` when its
    /// source published one (GitHub's asset `digest` — XQuartz's rule is the
    /// registry's GitHub `.pkg`). PackageInstaller independently verifies the
    /// selected inner package's Developer ID Installer signature and Team ID
    /// before opening it.
    static func verifyInstallerDownload(
        _ file: URL,
        for result: UpdateResult,
        progress: @Sendable (InstallStage) -> Void
    ) throws -> Data? {
        guard result.remote?.sourceName == "Sparkle" else {
            // A Developer-ID package whose source published its SHA-256 (a GitHub
            // asset's `digest`) is checked against it before anything parses or
            // mounts it — this route's counterpart of `VendorInstaller`'s SHA-256
            // gate, and like it, on top of the Team-ID gate rather than instead.
            // No published digest: nothing changes.
            if result.remote?.installTrust == .developerID,
               let expected = result.remote?.expectedSHA256 {
                progress(.verifyingSignature)
                try VendorInstaller.verifySHA256(file, expectedHex: expected)
            }
            return nil
        }
        guard let key = result.app.sparkleEdPublicKey, !key.isEmpty else {
            throw SignatureVerifier.VerifyError.edSignatureMissing
        }
        progress(.verifyingSignature)
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        try SignatureVerifier.verifyEdSignature(
            fileData: data,
            signatureBase64: result.remote?.edSignature,
            publicKeyBase64: key)
        // Return the digest of the exact Data instance whose EdDSA proof passed.
        // PackageInstaller compares this with the path before it parses or mounts
        // the enclosure, so source authentication and later package pinning stay
        // separate rather than pretending the Team-ID gate proves both.
        return Data(SHA256.hash(data: data))
    }

    /// The shape both archive routes share: download under a download permit,
    /// hand the host gate back, then swap under an apply permit.
    ///
    /// The scratch directory is removed on every exit — including an apply
    /// failure and a cancellation landing between the two phases, which is why
    /// the removal is here and not at the call sites.
    ///
    /// It holds the archive and whatever was unpacked or reconstructed from it —
    /// a whole app bundle — so it is removed on Dispatch, after the apply phase
    /// returns or throws (and after `swap` has handed its apply permit back).
    /// Internal for `FetchThenSwapCleanupTests`.
    ///
    /// `spaceToApply` is what the swap still needs once the archive is down —
    /// see `DiskSpaceGuard`. Zero skips both space checks here, which is what
    /// the `.xcode` route passes; its installer sizes the job itself. No
    /// default: a call site that forgot it would silently run unguarded,
    /// which is how the first attempt of `.sparkle` and `.vendor` once did.
    func fetchThenSwap(
        _ result: UpdateResult,
        spaceToApply: Int64,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void,
        download: @escaping @Sendable (UpdateResult, @Sendable @escaping (InstallStage) -> Void) async throws -> DownloadedUpdate,
        apply: @Sendable (UpdateResult, DownloadedUpdate, @Sendable @escaping (InstallStage) -> Void) async throws -> Void
    ) async throws -> Outcome {
        let label = "\(result.app.name)"
        // Refused before any byte moves, and again right before the apply below,
        // since the nested app may have been started during the download.
        try refuseWhileNestedAppRuns(result)
        progress(.downloading(fraction: 0))
        Log.install.debug("\(label, privacy: .public): waiting for a download permit")
        let backupKey = BackupStore.key(bundleID: result.app.bundleID, path: result.app.path)
        if spaceToApply > 0 {
            Log.install.notice("disk space: \(label, privacy: .public) watched while downloading, \(spaceToApply, privacy: .public) bytes checked before its swap")
        }
        let downloaded = try await permits.withDownloadPermit(cancellable: true) {
            // Cancelled at the hand-over; a cancel while queued already threw.
            try Task.checkCancellation()
            guard spaceToApply > 0 else { return try await download(result, progress) }
            return try await DiskSpaceGuard.watching(sparing: backupKey) {
                try await download(result, progress)
            }
        }
        defer { await removeItemOffCooperativePool(at: downloaded.workDir) }
        await releaseAfterDownload()
        return try await swap(
            result, downloaded, label: label, spaceToApply: spaceToApply, backupKey: backupKey,
            progress: progress, apply: apply)
    }

    /// `fetchThenSwap` from the download onwards: wait for the apply permit, apply.
    private func swap(
        _ result: UpdateResult, _ downloaded: DownloadedUpdate, label: String,
        spaceToApply: Int64, backupKey: String,
        progress: @Sendable @escaping (InstallStage) -> Void,
        apply: @Sendable (UpdateResult, DownloadedUpdate, @Sendable @escaping (InstallStage) -> Void) async throws -> Void
    ) async throws -> Outcome {
        Log.install.debug(
            "\(label, privacy: .public): downloaded \(downloaded.bytesDownloaded, privacy: .public) bytes, waiting for the apply permit")

        // Cancelled while queued for the swap: throws holding no permit, and
        // the caller's `defer` still removes the download's work directory.
        try await permits.waitForApplyOrCancel()
        var applyHeld = true
        defer { if applyHeld { permits.signalApply() } }
        // Cancelled at the hand-over — see the Homebrew route above.
        try Task.checkCancellation()
        // Here rather than inside the installers: an error thrown inside a
        // patch-route `apply` is wrapped as `DeltaRouteFailure` and retried with
        // the full archive, and a refusal must not be retried.
        try refuseWhileNestedAppRuns(result)
        // Last point at which a refusal changes nothing on disk. Not inside
        // `apply`, for the same reason as the refusal above.
        if spaceToApply > 0 {
            try await DiskSpaceGuard.ensureRoom(for: spaceToApply, sparing: backupKey)
        }
        let agents = snapshotLoginItemAgents(result)
        Log.install.debug("\(label, privacy: .public): applying")
        try await apply(result, downloaded, progress)
        permits.signalApply()
        applyHeld = false
        let agentsNotRestarted = await restartLoginItemAgents(agents)
        Log.install.debug("\(label, privacy: .public): applied")
        // Installed: whatever partial download this app left behind
        // (`ResumableDownloadStore`) is for a version it no longer needs.
        ResumableDownloadStore.discard(forApp: result.app.id)

        return Outcome(
            bytesDownloaded: downloaded.bytesDownloaded, finalHost: downloaded.finalHost,
            stagedPackageURL: nil, applied: true,
            usedDelta: downloaded.appliedPatch != nil,
            agentsNotRestarted: agentsNotRestarted)
    }

    /// Right before a swap: the login-item agents `result`'s recipe asks to
    /// restart, and which of their processes run from this bundle now. Empty
    /// for every app that declares none. See `LoginItemAgentRestart`.
    private func snapshotLoginItemAgents(_ result: UpdateResult) -> [LoginItemAgentRestart.Agent] {
        guard let declared = LoginItemAgentRestart.declaredAgents(for: result.app) else { return [] }
        return LoginItemAgentRestart.snapshot(
            bundle: result.app.path, agentBundleIDs: declared, processes: agentProcesses)
    }

    /// Once the swap has landed: restart the agents `snapshot` found running,
    /// returning the ids of any not confirmed back.
    ///
    /// In an unstructured task so that a cancel of the install does not reach
    /// it: the swap has happened, and an agent left on the old code is the
    /// state this exists to prevent. Its waits are bounded (about 15 s).
    private func restartLoginItemAgents(_ snapshot: [LoginItemAgentRestart.Agent]) async -> [String] {
        guard snapshot.contains(where: { !$0.processes.isEmpty }) else { return [] }
        let processes = agentProcesses, signal = signalAgent, jobPID = agentJobPID
        let results = await Task {
            await LoginItemAgentRestart.restart(
                snapshot, processes: processes, signal: signal, launchdJobPID: jobPID)
        }.value
        return results.filter { !$0.succeeded }.map(\.bundleID)
    }
}
