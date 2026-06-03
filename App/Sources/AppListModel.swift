import Foundation
import Observation
import AppKit
import DuoUpdaterCore

/// Owns the scanned app list, their update status, and in-flight installs.
@MainActor
@Observable
final class AppListModel {
    private(set) var results: [UpdateResult] = []
    private(set) var isScanning = false
    private(set) var isChecking = false
    private(set) var lastScan: Date?

    /// Per-app install progress, keyed by app id.
    private(set) var installing: [String: InstallStage] = [:]
    /// Per-app install error message, keyed by app id.
    private(set) var installErrors: [String: String] = [:]
    /// App ids whose on-disk bundle is newer than the version their running
    /// process launched with — i.e. updated (by us, the app's own updater, or
    /// brew) but not yet relaunched, so still executing old code.
    private(set) var needsRestart: Set<String> = []
    /// id → the build version the running instance launched with, for display.
    private var runningVersionByID: [String: String] = [:]
    /// When the last full networked check finished — shown in the header so the
    /// user can judge how fresh the results are.
    private(set) var lastCheck: Date?
    /// result.id → the version we have a rollback backup for, refreshed from the
    /// on-disk backup store whenever the list changes.
    private(set) var backupVersions: [String: String] = [:]

    func runningVersion(_ id: String) -> String? { runningVersionByID[id] }
    func backupVersion(_ id: String) -> String? { backupVersions[id] }

    /// A pending update the user hasn't ignored or skipped — what the badge counts
    /// and what "Update All" acts on.
    func isActionableUpdate(_ result: UpdateResult) -> Bool {
        guard result.hasUpdate else { return false }
        if prefs.isIgnored(result.app) { return false }
        if prefs.isVersionSkipped(result.app, version: result.remote?.displayVersion) { return false }
        return true
    }

    var updateCount: Int { results.filter(isActionableUpdate).count }

    private let sparkleInstaller = SparkleInstaller()
    private let homebrewInstaller = HomebrewInstaller()
    private let packageInstaller = PackageInstaller()
    private let vendorInstaller = VendorInstaller()

    /// Drives the App Management drag-to-authorize panel (vendored PermissionFlow)
    /// when an install is blocked by the privacy gate. Lazy so we only spin up the
    /// panel/window-tracking machinery the first time we actually hit a denial.
    @ObservationIgnored private lazy var permissionFlow = PermissionFlow.makeController()

    /// User settings (token, concurrency, ignore list, backups…). Read live on
    /// each refresh so a change made in the Settings window takes effect next check.
    let prefs: Preferences

    /// Background auto-check loop; nil when the frequency is "manual".
    private var scheduler: Task<Void, Never>?

    /// Per-app download traffic, tracked to the byte and persisted across runs.
    private let trafficStore = TrafficStore()
    /// Snapshot of per-app traffic for the UI, refreshed after each recorded
    /// download. Sorted heaviest-app-first by the store.
    private(set) var trafficStats: [AppTrafficStat] = []
    /// Grand total bytes downloaded across every app.
    private(set) var trafficTotalBytes: Int64 = 0

    init(prefs: Preferences = .shared) {
        self.prefs = prefs
        // Register the notification delegate + actionable categories (this also
        // requests notification permission once).
        NotificationController.shared.register(model: self)
        // Load any previously recorded traffic so the stats view isn't empty on
        // launch before the first install of this session.
        Task { await refreshTrafficStats() }
    }

    /// The ordered source stack, rebuilt per check so it picks up a token change
    /// and the App Store source re-reads the signed-in storefront region.
    private func makeSources() -> [any UpdateSource] {
        let token = GitHubToken.resolve(explicit: prefs.githubToken.isEmpty ? nil : prefs.githubToken)
        return [
            MacAppStoreSource(),
            SparkleAppcastSource(),
            HomebrewCaskSource(),
            // GitHub Releases for apps distributed that way (detection only unless
            // a rule names an installable asset).
            GitHubReleasesSource(token: token),
            // Last resort: bespoke per-vendor version endpoints. Only fires when
            // the earlier sources all miss and a recipe exists.
            VendorProbeSource()
        ]
    }

    /// Pull the latest per-app traffic snapshot out of the store onto the main
    /// actor for the UI.
    private func refreshTrafficStats() async {
        let snapshot = await trafficStore.snapshot()
        let total = await trafficStore.totalBytes()
        trafficStats = snapshot
        trafficTotalBytes = total
    }

    /// Record the bytes one install transferred, keyed to its app, then refresh
    /// the UI snapshot. `bytes <= 0` (e.g. an install that did no measured
    /// download) is ignored by the store.
    private func recordTraffic(_ result: UpdateResult, bytes: Int64) async {
        await trafficStore.record(
            appID: result.app.id,
            appName: result.app.name,
            bundleID: result.app.bundleID,
            fromVersion: result.app.shortVersion,
            toVersion: result.remote?.displayVersion,
            sourceName: result.remote?.sourceName,
            bytes: bytes
        )
        await refreshTrafficStats()
    }

    /// Scan the disk, then check every app for updates.
    func refresh() async {
        // Expire all cached changelog pages so the detail window re-fetches
        // after a manual refresh — the user expects fresh release notes.
        await ChangelogCache.shared.invalidateAll()
        isScanning = true
        // One Toolbox snapshot shared by the scan (to tag managed apps) and the
        // checker (to read latest-build info) — a single read of its local cache.
        let toolbox = ToolboxInventory()
        // One TestFlight snapshot shared by the scan (to tag managed apps) and the
        // checker (to read latest-build info) — a single read of its local cache.
        let testflight = TestFlightInventory()
        let found = await Task.detached(priority: .userInitiated) {
            AppScanner(toolbox: toolbox, testflight: testflight).scan()
        }.value
        results = found.map { UpdateResult(app: $0, remote: nil, status: .unknown) }
        lastScan = .now
        isScanning = false

        isChecking = true
        let checker = UpdateChecker(
            sources: makeSources(),
            maxConcurrency: prefs.maxConcurrency,
            toolbox: ToolboxSource(inventory: toolbox),
            testflight: testflight)
        Log.app.info("refresh: checking \(found.count, privacy: .public) apps")
        let checked = await checker.check(found)
        results = sorted(checked)
        await computeRestartInfo()
        await refreshBackupIndex()
        isChecking = false
        lastCheck = .now
        Log.app.info("refresh done: \(self.updateCount, privacy: .public) updates, \(self.needsRestart.count, privacy: .public) need restart")
    }

    /// True when this update installs seamlessly in place (Sparkle EdDSA, or a
    /// drag-to-Applications Homebrew cask). Excludes `pkg` casks, which need the
    /// system installer — see `requiresInstaller`.
    ///
    /// A Homebrew result only ever reaches us when the app was *actually*
    /// installed via Homebrew (the source gates on the local Caskroom), so
    /// `brew install --cask --force` here updates through the app's real
    /// channel — no cross-channel mixing.
    func canAutoInstall(_ result: UpdateResult) -> Bool {
        switch result.remote?.sourceName {
        case "Sparkle":
            return result.app.sparkleEdPublicKey?.isEmpty == false
                && result.remote?.edSignature != nil
        case "Homebrew":
            return result.remote?.sourceIdentifier != nil
                && result.remote?.requiresManualInstaller == false
        case "Vendor", "GitHub":
            // A vendor-website or GitHub-release app with a resolved installer
            // archive (zip/dmg/tar.gz). We download it, verify the code signature
            // matches the installed app's Team ID, then swap in place — same
            // channel, no mix. GitHub rules without an asset pattern stay
            // detection-only (vendorInstallerKind nil), so they fall through here.
            return result.remote?.vendorInstallerKind != nil
                && result.remote?.requiresManualInstaller == false
        default:
            return false
        }
    }

    /// True when this update is a `pkg` (a `pkg` cask, or a vendor pkg): we
    /// download the official package and open it in the system installer (which
    /// prompts for admin itself).
    ///
    /// For Vendor we key strictly on a `.pkg` install spec — NOT on
    /// `requiresManualInstaller`, which a *detection-only* vendor recipe also
    /// sets (meaning "send the user to download by hand"). Conflating the two
    /// made detection-only apps (LM Studio, Chrome, …) wrongly show an installer
    /// button pointed at their version-check endpoint.
    func requiresInstaller(_ result: UpdateResult) -> Bool {
        switch result.remote?.sourceName {
        case "Homebrew":
            return result.remote?.requiresManualInstaller == true
        case "Vendor", "GitHub":
            return result.remote?.vendorInstallerKind == .pkg
        default:
            return false
        }
    }

    /// A cheap, network-free rescan to run whenever the menu opens. Re-reads each
    /// app from disk and re-evaluates it against the remote we already fetched, so
    /// we notice an app that updated itself in the background (its own Sparkle/
    /// Squirrel/Keystone updater, or brew) — the on-disk version jumps ahead while
    /// the running process stays old. That flips its row to up-to-date AND lets
    /// `computeRestartInfo` surface a Restart badge. No network: the full update
    /// check still runs on first open and on the manual refresh.
    func refreshLocal() async {
        // Don't churn the list while an install is in flight: this rebuilds and
        // re-sorts `results` wholesale, which would reorder/replace the row under
        // an active spinner. Installs key by id and finish fine, but the visible
        // row shouldn't shuffle mid-install.
        guard !results.isEmpty, !isChecking, installing.isEmpty else { return }
        let found = await Task.detached(priority: .userInitiated) {
            AppScanner().scan()
        }.value
        let prior = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let updated = found.map { app -> UpdateResult in
            guard let was = prior[app.id] else {
                return UpdateResult(app: app, remote: nil, status: .unknown)
            }
            // Re-derive status from the cached remote against the fresh on-disk
            // version. With no remote (App Store / Toolbox / unknown) keep what we
            // had, just refreshed to the new bundle info.
            guard let remote = was.remote else {
                return UpdateResult(app: app, remote: nil, status: was.status)
            }
            // Toolbox and TestFlight own their apps' status (computed from their
            // own cache, not a version compare) — keep it; don't re-evaluate.
            guard remote.sourceName != "Toolbox", remote.sourceName != "TestFlight" else {
                return UpdateResult(app: app, remote: remote, status: was.status)
            }
            return UpdateResult(
                app: app, remote: remote,
                status: UpdateChecker.evaluate(installed: app, remote: remote))
        }
        results = sorted(updated)
        await computeRestartInfo()
        await refreshBackupIndex()
    }

    /// Update one app's install stage, coalescing download progress to whole
    /// percent. A `URLSession` download fires `didWriteData` dozens of times per
    /// second; each write would otherwise mutate `installing` and re-render every
    /// row (the dictionary invalidates as a whole). Skipping same-percent ticks
    /// cuts that churn by ~50× and removes the visible jitter when several apps
    /// download at once.
    private func setStage(_ id: String, _ stage: InstallStage) {
        if case .downloading(let f) = stage,
           case .downloading(let prev)? = installing[id],
           Int(f * 100) == Int(prev * 100) {
            return  // same whole percent — nothing the user can see changed
        }
        installing[id] = stage
    }

    /// Install an update, routing to the right installer for its source. `notify`
    /// is false for the batch path so "Update All" posts one summary banner
    /// instead of one per app. Returns true only when a bundle was actually
    /// installed (not when the app turned out already-current, or an early-out/
    /// error path was taken) so the batch summary count is exact.
    ///
    /// The per-app "updated"/"ready to restart" banners are NOT gated on
    /// `prefs.notifyOnUpdates`: that setting governs unsolicited *background*
    /// discovery alerts, whereas these are direct feedback for an install the user
    /// just clicked. The batch path opts out via `notify: false` instead.
    @discardableResult
    func install(_ result: UpdateResult, notify: Bool = true) async -> Bool {
        let id = result.id
        // Re-entrancy guard (matches `retry`): the popover "Update anyway" button
        // and the major-upgrade badge aren't disabled while an install is in
        // flight, so a double-click could otherwise launch two concurrent installs
        // for the same app — two downloads, two in-place swaps, two notifications.
        guard installing[id] == nil else { return false }
        installErrors[id] = nil
        Log.install.info("install start: \(result.app.name, privacy: .public) \(result.app.shortVersion ?? "?", privacy: .public) → \(result.remote?.displayVersion ?? "?", privacy: .public) via \(result.remote?.sourceName ?? "?", privacy: .public)")

        // Defensive re-check: the app may already be current — e.g. a manual
        // pkg install we couldn't observe, or it was updated by its own updater
        // since the last scan. Re-read it from disk and re-query before we
        // download or replace anything.
        installing[id] = .checking
        let result = await recheck(result)
        replaceRow(result)
        guard result.hasUpdate else {
            // Already current on disk — but the running instance may predate
            // that update, so recompute whether a restart is needed.
            Log.install.info("install skipped: \(result.app.name, privacy: .public) already current on disk")
            await computeRestartInfo()
            installing[id] = nil
            return false
        }

        // Back up the current bundle first (when enabled) so this update can be
        // rolled back. Only for in-place swaps we perform ourselves — Homebrew and
        // pkg installs go through their own tools and manage their own state.
        if prefs.keepBackups, canAutoInstall(result), !requiresInstaller(result) {
            await backupCurrent(result)
        }

        do {
            // pkg casks: download the official installer and open it. The
            // actual install happens in macOS's installer under the user's
            // control, so we don't mark it up to date — a later rescan will.
            if requiresInstaller(result) {
                installing[id] = .downloading(fraction: 0)
                let bytes = try await packageInstaller.downloadAndOpen(
                    url: result.remote?.downloadURL,
                    headers: result.remote?.downloadHeaders ?? [:]
                ) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
                await recordTraffic(result, bytes: bytes)
                installing[id] = nil
                return true
            }

            switch result.remote?.sourceName {
            case "Homebrew":
                // Reset the spinner on this early-out too: with the re-entrancy
                // guard above, a stuck `installing[id]` would otherwise block every
                // future install/retry for this app permanently.
                guard let token = result.remote?.sourceIdentifier else {
                    installing[id] = nil
                    return false
                }
                installing[id] = .runningCommand("starting brew…")
                // brew performs its own download, so we never see those bytes —
                // intentionally not recorded (we only count what we measured).
                try await homebrewInstaller.upgrade(caskToken: token) { line in
                    Task { @MainActor in self.setStage(id, .runningCommand(line)) }
                }
            case "Vendor", "GitHub":
                installing[id] = .downloading(fraction: 0)
                let bytes = try await vendorInstaller.install(result) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
                await recordTraffic(result, bytes: bytes)
            default:
                installing[id] = .downloading(fraction: 0)
                let bytes = try await sparkleInstaller.install(result) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
                await recordTraffic(result, bytes: bytes)
            }
            // Re-read from disk to reflect the new version, then recompute the
            // Restart flag by comparing each running instance's launch version
            // to what's now on disk. In-place installs (Homebrew) leave the old
            // process running stale code; Sparkle relaunches, so it won't show.
            let updated = await recheck(result)
            // The bundle was replaced in place (same path); drop its cached icon so
            // the row re-reads the new one instead of showing the old until restart.
            AppIconCache.invalidate(updated.app.path.path)
            replaceRow(updated)
            await computeRestartInfo()
            await refreshBackupIndex()

            // Tell the user it landed. If the app was running, its live process
            // is still on the old code (so it's in needsRestart) — point them at
            // the Restart action. Otherwise the in-place swap is already fully in
            // effect and there's nothing left to do.
            let version = updated.app.shortVersion
            if needsRestart.contains(updated.id) {
                Log.install.info("install done: \(updated.app.name, privacy: .public) now \(version ?? "?", privacy: .public) on disk, awaiting restart")
                if notify { UpdateNotifier.readyToRestart(app: updated.app.name, version: version) }
            } else {
                Log.install.info("install done: \(updated.app.name, privacy: .public) now \(version ?? "?", privacy: .public)")
                if notify { UpdateNotifier.updated(app: updated.app.name, version: version) }
            }
        } catch let error as AppManagementRequiredError {
            // The swap was blocked by the App Management privacy gate. There's no
            // API to request it, so guide the user to the right Settings pane with
            // the drag-to-authorize panel; the install can be retried once granted.
            Log.install.error("install blocked by App Management: \(result.app.name, privacy: .public)")
            installErrors[id] = error.errorDescription
            presentAppManagementPermissionFlow()
        } catch {
            Log.install.error("install failed: \(result.app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            installErrors[id] = error.localizedDescription
        }
        installing[id] = nil
        // True only if we reached the install path without throwing.
        return installErrors[id] == nil
    }

    /// Flag apps whose running instance launched with an older build than
    /// what's now on disk — reliably, by reading the live launch version from
    /// LaunchServices (`lsappinfo`), which is cached at launch and so differs
    /// from the on-disk Info.plist after an update. Covers our own installs,
    /// the app's own updater, and brew — across app restarts.
    private func computeRestartInfo() async {
        let running = await Self.runningBuildVersions()
        var ids: Set<String> = []
        var versions: [String: String] = [:]
        for result in results {
            guard let bundleID = result.app.bundleID,
                  let runVersion = running[bundleID],
                  let disk = result.app.buildVersion ?? result.app.shortVersion,
                  VersionComparator.isNewer(disk, than: runVersion) else { continue }
            // Always record the lagging running version — even for a row that
            // also has a newer update pending — so the update row can show it as
            // "current". The Restart badge, though, only makes sense when there's
            // nothing newer to install: an update-available row shows Update and
            // installing it re-triggers the restart prompt afterward.
            versions[result.id] = runVersion
            if !result.hasUpdate { ids.insert(result.id) }
        }
        needsRestart = ids
        runningVersionByID = versions
        // Re-sort: a row that just flipped to needs-restart should move up into
        // the actionable tier rather than stay wherever it last sorted.
        results = sorted(results)
    }

    /// Map of bundle id → the build version each running app launched with,
    /// parsed from `lsappinfo list` (one call for all running apps).
    ///
    /// Runs entirely off the main actor: `lsappinfo` talks to `coreservicesd`
    /// and can be slow or hang — most acutely right after we terminate and
    /// relaunch a batch of apps during an install. Blocking `@MainActor` here
    /// froze the whole UI (spin report) and stranded the half-restarted app.
    nonisolated private static func runningBuildVersions() async -> [String: String] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            // nullDevice, not Pipe(): an undrained stderr pipe deadlocks once
            // its 64KB buffer fills — lsappinfo blocks writing, we block in
            // waitUntilExit(), forever.
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return [:] }

            // Timeout backstop so a wedged lsappinfo can't hang us indefinitely.
            // SIGTERM first; if it's ignored (a wedged process can hold stdout's
            // write end open, so the blocking read below would never return),
            // escalate to SIGKILL, which the kernel can't refuse — that closes the
            // pipe and unblocks the read for sure.
            let pid = process.processIdentifier
            let term = DispatchWorkItem { process.terminate() }
            let kill = DispatchWorkItem { Foundation.kill(pid, SIGKILL) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: term)
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: kill)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            term.cancel()
            kill.cancel()
            guard let text = String(data: data, encoding: .utf8) else { return [:] }

            var map: [String: String] = [:]
            var current: String?
            for line in text.split(separator: "\n") {
                if let bundleID = quotedValue(after: "bundleID", in: line) {
                    current = bundleID
                } else if let cur = current, map[cur] == nil,
                          let version = quotedValue(after: "Version", in: line) {
                    map[cur] = version
                }
            }
            return map
        }.value
    }

    /// Extract the value of a `key="value"` pair from a line.
    nonisolated private static func quotedValue(after key: String, in line: Substring) -> String? {
        guard let start = line.range(of: key + "=\"") else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    /// Quit the stale running instance and relaunch it so the new version takes
    /// effect. Graceful only — if it won't quit (unsaved work), we leave it and
    /// keep the Restart prompt for the user to retry.
    func restart(_ result: UpdateResult) async {
        guard let bundleID = result.app.bundleID else { return }
        Log.app.info("restart: \(result.app.name, privacy: .public) [\(bundleID, privacy: .public)]")
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { needsRestart.remove(result.id); return }
        for app in running { app.terminate() }
        for _ in 0..<30 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            Log.app.error("restart: \(result.app.name, privacy: .public) won't quit (likely a save prompt) — leaving badge")
            return  // still up (likely a save prompt) — leave the badge
        }
        let relaunched = NSWorkspace.shared.open(result.app.path)
        needsRestart.remove(result.id)
        runningVersionByID[result.id] = nil
        Log.app.info("restart: \(result.app.name, privacy: .public) relaunched=\(relaunched, privacy: .public)")
        if relaunched {
            UpdateNotifier.restarted(app: result.app.name, version: result.app.shortVersion)
        }
    }

    /// Open System Settings → Privacy & Security → App Management and float the
    /// drag-to-authorize panel, prompting the user to drag **DuoUpdater itself**
    /// into the list (the permission is granted to the app doing the replacing,
    /// not the target). App Management exposes neither a request nor a status API,
    /// so this is the only way to surface it — and we can't tell afterward whether
    /// it was granted; the user simply retries the update. Also callable directly
    /// (e.g. from a menu item) so the prompt isn't strictly gated on a failure.
    func presentAppManagementPermissionFlow() {
        permissionFlow.authorize(pane: .appManagement, suggestedAppURLs: [Bundle.main.bundleURL])
    }

    // MARK: - Backups & rollback

    /// Copy the app's current bundle into the backup store before we replace it,
    /// so the update can be undone. Best-effort: a failed backup logs and proceeds
    /// (the user opted into the update; a missing safety net mustn't block it).
    private func backupCurrent(_ result: UpdateResult) async {
        let path = result.app.path
        let bundleID = result.app.bundleID
        let key = BackupStore.key(bundleID: bundleID, path: path)
        let version = result.app.shortVersion ?? result.app.buildVersion
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            do {
                try BackupStore.save(appPath: path, key: key, version: version, bundleID: bundleID)
                return true
            } catch { return false }
        }.value
        if !ok {
            Log.install.error("backup failed: \(result.app.name, privacy: .public) — proceeding without a rollback point")
        }
    }

    /// Re-read which apps have a rollback backup on disk (one directory scan),
    /// mapping it onto the current rows.
    private func refreshBackupIndex() async {
        let map = await Task.detached(priority: .utility) { BackupStore.allBackups() }.value
        var byID: [String: String] = [:]
        for result in results {
            let key = BackupStore.key(bundleID: result.app.bundleID, path: result.app.path)
            if let backup = map[key] { byID[result.id] = backup.version ?? "previous" }
        }
        backupVersions = byID
    }

    /// Restore the previous version from its backup, swapping it back over the
    /// installed bundle. Mirrors `install`'s shape: a per-row spinner, an error
    /// surfaced on the row, and a restart prompt if the running process is now
    /// ahead of what's on disk.
    func rollback(_ result: UpdateResult) async {
        let id = result.id
        guard installing[id] == nil else { return }
        let target = result.app.path
        let key = BackupStore.key(bundleID: result.app.bundleID, path: target)
        installErrors[id] = nil
        installing[id] = .installing
        Log.install.info("rollback start: \(result.app.name, privacy: .public)")
        do {
            let restored = try await Task.detached(priority: .userInitiated) { () -> String? in
                try BackupStore.restore(forKey: key, over: target)
            }.value
            AppIconCache.invalidate(target.path)
            let updated = await recheck(result)
            replaceRow(updated)
            await computeRestartInfo()
            await refreshBackupIndex()
            installing[id] = nil
            Log.install.info("rollback done: \(updated.app.name, privacy: .public) → \(restored ?? "?", privacy: .public)")
            if needsRestart.contains(updated.id) {
                UpdateNotifier.readyToRestart(app: updated.app.name, version: restored)
            }
        } catch {
            Log.install.error("rollback failed: \(result.app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            installErrors[id] = error.localizedDescription
            installing[id] = nil
        }
    }

    // MARK: - Batch update

    /// Install every pending update we can apply in place without a confirmation
    /// gate — skipping major upgrades (license-boundary warning), pkg/installer
    /// updates (need the system installer), App Store / Toolbox / TestFlight
    /// (managed elsewhere), and anything ignored or version-skipped. Sequential on
    /// purpose: parallel installs would contend on the network, the privileged
    /// swap, and the restart bookkeeping. Snapshots the target set up front so the
    /// re-sorting each install triggers can't reshuffle what we iterate.
    func installAll() async {
        let targets = results.filter { result in
            isActionableUpdate(result)
                && canAutoInstall(result)
                && !result.isMajorUpgrade
                && installing[result.id] == nil
        }
        guard !targets.isEmpty else { return }
        Log.app.info("update all: \(targets.count, privacy: .public) apps")
        // Count only the installs that actually happened (install returns false for
        // already-current/early-out/error), so the summary banner is exact.
        var installed = 0
        for target in targets {
            if await install(target, notify: false) { installed += 1 }
        }
        if prefs.notifyOnUpdates && installed > 0 {
            UpdateNotifier.batchUpdated(count: installed)
        }
    }

    /// True when there's more than one app "Update All" would act on — used to
    /// decide whether to show the batch button.
    var canUpdateAll: Bool {
        results.filter {
            isActionableUpdate($0) && canAutoInstall($0) && !$0.isMajorUpgrade
        }.count > 1
    }

    // MARK: - Ignore / skip

    /// Toggle whether this app is hidden from update checks entirely.
    func toggleIgnore(_ result: UpdateResult) {
        let nowIgnored = !prefs.isIgnored(result.app)
        prefs.setIgnored(nowIgnored, result.app)
        Log.app.info("\(nowIgnored ? "ignore" : "unignore", privacy: .public): \(result.app.name, privacy: .public)")
    }

    /// Decline the currently-offered version for this app; a newer one still shows.
    func skipThisVersion(_ result: UpdateResult) {
        guard let version = result.remote?.displayVersion else { return }
        prefs.skipVersion(version, result.app)
        Log.app.info("skip \(version, privacy: .public): \(result.app.name, privacy: .public)")
    }

    // MARK: - Background scheduler

    /// One-time startup wiring, run when the UI first appears: hand the "show
    /// updates" action to the notification controller and arm the background loop.
    /// Idempotent — safe to call on every menu open.
    private var started = false
    func start(showUpdates: @escaping @Sendable @MainActor () -> Void) {
        guard !started else { return }
        started = true
        NotificationController.shared.setOnShowUpdates(showUpdates)
        reschedule()
    }

    /// (Re)arm the background auto-check loop from the current frequency setting.
    /// Called at launch and whenever the user changes the frequency. A "manual"
    /// frequency tears the loop down entirely.
    func reschedule() {
        scheduler?.cancel()
        guard let interval = prefs.checkFrequency.interval else {
            scheduler = nil
            Log.app.info("scheduler: manual — no background checks")
            return
        }
        Log.app.info("scheduler: every \(Int(interval), privacy: .public)s")
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                // Don't stomp on a manual check or an install in flight.
                if !self.isChecking && !self.isScanning && self.installing.isEmpty {
                    await self.backgroundRefresh()
                }
            }
        }
    }

    /// A scheduled check that, unlike the manual one, notifies the user about any
    /// updates that newly appeared (so a background check is actually useful).
    private func backgroundRefresh() async {
        // Key the "before" set on raw hasUpdate (not the ignore-filtered set) so a
        // preference toggle between checks — e.g. un-ignoring an app — can't make a
        // pre-existing update look newly-arrived and fire a surprise banner.
        let before = Set(results.filter(\.hasUpdate).map(\.id))
        await refresh()
        guard prefs.notifyOnUpdates else { return }
        let now = results.filter(isActionableUpdate)
        let newly = now.filter { !before.contains($0.id) }
        guard !newly.isEmpty else { return }
        Log.app.info("background check: \(newly.count, privacy: .public) new updates")
        UpdateNotifier.updatesAvailable(total: now.count, newApps: newly.map(\.app.name))
    }

    // MARK: - Recheck

    /// Re-read one app from disk and re-check it across all sources. Cheap
    /// enough to run right before installing, as a guard against acting on a
    /// stale row.
    private func recheck(_ result: UpdateResult) async -> UpdateResult {
        let id = result.id
        let testflight = TestFlightInventory()
        let apps = await Task.detached(priority: .userInitiated) {
            AppScanner(testflight: testflight).scan()
        }.value
        guard let fresh = apps.first(where: { $0.id == id }) else { return result }
        let checker = UpdateChecker(
            sources: makeSources(),
            maxConcurrency: prefs.maxConcurrency,
            toolbox: ToolboxSource(),
            testflight: testflight)
        return await checker.check(fresh)
    }

    /// Re-run the update check for one app whose source errored — the retry
    /// affordance on an `.error` row (e.g. a transient GitHub rate-limit). Reuses
    /// the install-stage spinner to show "Checking" on just that row, and bails
    /// if the row is already busy (installing or mid-recheck).
    func retry(_ result: UpdateResult) async {
        let id = result.id
        guard installing[id] == nil else { return }
        Log.app.info("retry: re-checking \(result.app.name, privacy: .public)")
        installing[id] = .checking
        let updated = await recheck(result)
        installing[id] = nil
        replaceRow(updated)
        Log.app.info("retry done: \(updated.app.name, privacy: .public) → \(String(describing: updated.status), privacy: .public)")
    }

    /// Replace a single row by id and re-sort.
    private func replaceRow(_ updated: UpdateResult) {
        if let idx = results.firstIndex(where: { $0.id == updated.id }) {
            results[idx] = updated
            results = sorted(results)
        }
    }

    /// Actionable rows first: pending updates, then apps updated-on-disk that
    /// still need a restart, then everything else — each tier alphabetical. A
    /// restart row is just as actionable as an update, so it stays grouped with
    /// them up top instead of sinking into the up-to-date list at the bottom
    /// (which read as the row "disappearing" right after you clicked Update).
    private func sorted(_ list: [UpdateResult]) -> [UpdateResult] {
        func rank(_ r: UpdateResult) -> Int {
            if r.hasUpdate { return 0 }
            if needsRestart.contains(r.id) { return 1 }
            return 2
        }
        return list.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.app.name.localizedCaseInsensitiveCompare(b.app.name) == .orderedAscending
        }
    }
}
