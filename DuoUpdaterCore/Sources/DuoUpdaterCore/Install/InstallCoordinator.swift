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
    }

    public enum CoordinatorError: LocalizedError {
        case routeNotSupportedHere(Route)
        case missingCaskToken
        case notAnUpdate

        public var errorDescription: String? {
            switch self {
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

        public init(
            bytesDownloaded: Int64,
            finalHost: String?,
            stagedPackageURL: URL?,
            applied: Bool,
            usedDelta: Bool = false
        ) {
            self.bytesDownloaded = bytesDownloaded
            self.finalHost = finalHost
            self.stagedPackageURL = stagedPackageURL
            self.applied = applied
            self.usedDelta = usedDelta
        }
    }

    /// How many downloads and applies may run at once. Shared by both hosts, but
    /// per-process: two processes installing at the same time is what
    /// ``InstallLock`` prevents, not this.
    private let permits: InstallPermits
    private let vendor = VendorInstaller()
    private let sparkle = SparkleInstaller()
    private let homebrew = HomebrewInstaller()
    private let packages = PackageInstaller()

    public init(permits: InstallPermits = InstallPermits(downloads: 4, applies: 2)) {
        self.permits = permits
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
        case "Homebrew":          return .homebrew
        case "Vendor", "GitHub":  return .vendor
        case "App Store":         return .appStore
        default:                  return .sparkle
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
        case .homebrew, .vendor, .sparkle, .installer, .appStore: return true
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
        case failed
    }

    /// Store a rollback point for `app`.
    public static func backUp(_ app: InstalledApp, route: Route) async -> BackupOutcome {
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
        return await Task.detached(priority: .userInitiated) { () -> BackupOutcome in
            // Only *sealed* unreadable files stop a backup. Unsealed ones are the
            // app's own runtime droppings; the copy skips them and still restores.
            let unreadable = BackupManifest.unreadableFiles(in: path)
            if let blocked = unreadable.sealed.first {
                return .unreadable(path: path.appendingPathComponent(blocked).path)
            }
            do {
                try BackupStore.save(
                    appPath: path, key: key, version: version,
                    buildVersion: buildVersion, bundleID: bundleID,
                    fromPackageInstall: fromPackage, fromAppStore: fromStore)
                // An input method's settings and learned dictionary live outside
                // its bundle, so the bundle rollback point above cannot speak for
                // them — and they are exactly what went missing when this app's
                // one-click for WeType was withdrawn. Cloned, so it is close to
                // free; deliberately AFTER the save, whose staging directory
                // replaces the key directory wholesale. See
                // `InputMethodDataBackup`.
                //
                // Not folded into `BackupOutcome`: this is not a reason to change
                // what the user is told about the *bundle* rollback, and the
                // outcome enum is switched over in both the app and the CLI.
                if InPlaceSwap.usesContentsRotation(target: path) {
                    let captured = InputMethodDataBackup.save(
                        bundleName: path.deletingPathExtension().lastPathComponent,
                        bundleID: bundleID, key: key)
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
        }.value
    }

    /// Fetch and apply `result` by `route`.
    ///
    /// - Parameter releaseAfterDownload: called once, as soon as the bytes are
    ///   down (or as soon as a tool that fetches on our behalf finishes), so a
    ///   per-host gate the caller holds can be handed to the next app rather
    ///   than spanning the extract and swap too. Must be idempotent — it is not
    ///   called at all on paths that never reach a download.
    /// - Parameter beforeInstallerOpen: `.installer` route only — runs after the
    ///   package passes the gate and before it reaches macOS's Installer, so the
    ///   caller can retire the window this package supersedes while Installer is
    ///   idle. See `PackageInstaller.handOver`.
    public func perform(
        _ result: UpdateResult,
        route: Route,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void = {},
        beforeInstallerOpen: @Sendable () async -> Void = {}
    ) async throws -> Outcome {
        // The install path was silent end to end, which made "it said it updated
        // and nothing changed" impossible to answer after the fact — the only
        // evidence was the app's own mtime. `.notice`, so it is still readable when
        // the report arrives hours later.
        let label = "\(result.app.name) [\(result.app.bundleID ?? "?")]"
        Log.install.notice(
            "install start: \(label, privacy: .public) \(result.app.shortVersion ?? "?", privacy: .public) → \(result.remote?.displayVersion ?? "?", privacy: .public) via \(String(describing: route), privacy: .public)")
        do {
            let outcome = try await performRoute(
                result, route: route, progress: progress,
                releaseAfterDownload: releaseAfterDownload,
                beforeInstallerOpen: beforeInstallerOpen)
            // `applied` is the load-bearing bit: false means the bytes are staged
            // but nothing on disk has changed yet, which is exactly the state that
            // used to be indistinguishable from a finished update.
            Log.install.notice(
                "install returned: \(label, privacy: .public) applied=\(outcome.applied, privacy: .public) bytes=\(outcome.bytesDownloaded, privacy: .public) staged=\(outcome.stagedPackageURL != nil, privacy: .public)")
            return outcome
        } catch {
            Log.install.error(
                "install failed: \(label, privacy: .public) via \(String(describing: route), privacy: .public) — \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func performRoute(
        _ result: UpdateResult,
        route: Route,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void,
        beforeInstallerOpen: @Sendable () async -> Void
    ) async throws -> Outcome {
        switch route {
        case .appStore:
            throw CoordinatorError.routeNotSupportedHere(.appStore)

        case .installer:
            progress(.downloading(fraction: 0))
            let verifyDownload: @Sendable (URL) throws -> Data? = { file in
                try Self.verifyInstallerDownload(file, for: result, progress: progress)
            }
            let opened = try await permits.withDownloadPermit {
                // Cancelled while parked on the permit: don't start the fetch.
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
            progress(.runningCommand("starting brew…"))
            // brew's fetch and swap are one command we cannot split, so the whole
            // run takes the apply permit — and brew does its own downloading, so
            // those bytes are never counted rather than estimated.
            await permits.waitForApply()
            var applyHeld = true
            defer { if applyHeld { permits.signalApply() } }
            try Task.checkCancellation()
            try await homebrew.upgrade(caskToken: token) { line in
                progress(.runningCommand(line))
            }
            permits.signalApply()
            applyHeld = false
            await releaseAfterDownload()
            return Outcome(
                bytesDownloaded: 0, finalHost: nil, stagedPackageURL: nil, applied: true)

        case .vendor:
            do {
                return try await fetchThenSwap(
                    result, progress: progress, releaseAfterDownload: releaseAfterDownload,
                    download: {
                        try await self.vendor.download($0, preferDelta: true, onStage: $1)
                    },
                    apply: { _ = try await self.vendor.apply($0, download: $1, onStage: $2) })
            } catch let failure as DeltaRouteFailure {
                Log.install.info("delta route failed, retrying with the full archive: \(result.app.name, privacy: .public) — \(failure.errorDescription ?? "unknown", privacy: .public)")
                // The patch's bytes were spent whether or not it worked, so they
                // belong in the total this install reports.
                return try await withBytes(failure.bytesSpent) { try await fetchThenSwap(
                    result, progress: progress, releaseAfterDownload: releaseAfterDownload,
                    download: {
                        try await self.vendor.download($0, preferDelta: false, onStage: $1)
                    },
                    apply: { _ = try await self.vendor.apply($0, download: $1, onStage: $2) }) }
            }

        case .sparkle:
            do {
                return try await fetchThenSwap(
                    result, progress: progress, releaseAfterDownload: releaseAfterDownload,
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
                    result, progress: progress, releaseAfterDownload: releaseAfterDownload,
                    download: {
                        try await self.sparkle.download($0, preferDelta: false, onStage: $1)
                    },
                    apply: { _ = try await self.sparkle.apply($0, download: $1, onStage: $2) }) }
            }
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
            usedDelta: outcome.usedDelta)
    }

    /// Source-specific proof over a package route's original download. A Sparkle
    /// package bypasses SparkleInstaller's archive path, but must not bypass Gate 1:
    /// EdDSA covers the exact enclosure (the outer DMG when the pkg is wrapped).
    /// PackageInstaller independently verifies the selected inner package's
    /// Developer ID Installer signature and Team ID before opening it.
    static func verifyInstallerDownload(
        _ file: URL,
        for result: UpdateResult,
        progress: @Sendable (InstallStage) -> Void
    ) throws -> Data? {
        guard result.remote?.sourceName == "Sparkle" else { return nil }
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
    /// the `defer` is here and not at the call sites.
    private func fetchThenSwap(
        _ result: UpdateResult,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void,
        download: @Sendable (UpdateResult, @Sendable @escaping (InstallStage) -> Void) async throws -> DownloadedUpdate,
        apply: @Sendable (UpdateResult, DownloadedUpdate, @Sendable @escaping (InstallStage) -> Void) async throws -> Void
    ) async throws -> Outcome {
        let label = "\(result.app.name)"
        progress(.downloading(fraction: 0))
        Log.install.debug("\(label, privacy: .public): waiting for a download permit")
        let downloaded = try await permits.withDownloadPermit {
            try Task.checkCancellation()
            return try await download(result, progress)
        }
        await releaseAfterDownload()
        defer { try? FileManager.default.removeItem(at: downloaded.workDir) }
        Log.install.debug(
            "\(label, privacy: .public): downloaded \(downloaded.bytesDownloaded, privacy: .public) bytes, waiting for the apply permit")

        await permits.waitForApply()
        var applyHeld = true
        defer { if applyHeld { permits.signalApply() } }
        try Task.checkCancellation()
        Log.install.debug("\(label, privacy: .public): applying")
        try await apply(result, downloaded, progress)
        permits.signalApply()
        applyHeld = false
        Log.install.debug("\(label, privacy: .public): applied")

        return Outcome(
            bytesDownloaded: downloaded.bytesDownloaded, finalHost: downloaded.finalHost,
            stagedPackageURL: nil, applied: true,
            usedDelta: downloaded.appliedPatch != nil)
    }
}
