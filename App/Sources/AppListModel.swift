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

    func runningVersion(_ id: String) -> String? { runningVersionByID[id] }

    var updateCount: Int { results.filter(\.hasUpdate).count }

    private let sparkleInstaller = SparkleInstaller()
    private let homebrewInstaller = HomebrewInstaller()
    private let packageInstaller = PackageInstaller()
    private let vendorInstaller = VendorInstaller()

    /// GitHub API token, resolved once (env / `gh` CLI / a user-set value) to
    /// lift the 60/hour anonymous rate limit. nil → unauthenticated requests.
    private let githubToken: String? = GitHubToken.resolve(
        explicit: UserDefaults.standard.string(forKey: "GitHubToken")
    )

    init() {
        // Ask once so finished-update notifications can fire later.
        UpdateNotifier.requestAuthorization()
    }

    /// Scan the disk, then check every app for updates.
    func refresh() async {
        isScanning = true
        // One Toolbox snapshot shared by the scan (to tag managed apps) and the
        // checker (to read latest-build info) — a single read of its local cache.
        let toolbox = ToolboxInventory()
        let found = await Task.detached(priority: .userInitiated) {
            AppScanner(toolbox: toolbox).scan()
        }.value
        results = found.map { UpdateResult(app: $0, remote: nil, status: .unknown) }
        lastScan = .now
        isScanning = false

        isChecking = true
        // Rebuilt each refresh so the App Store source re-reads the signed-in
        // storefront — picking up an Apple ID region switch without a restart.
        let checker = UpdateChecker(sources: [
            MacAppStoreSource(),
            SparkleAppcastSource(),
            HomebrewCaskSource(),
            // GitHub Releases for apps distributed that way (detection only).
            GitHubReleasesSource(token: githubToken),
            // Last resort: bespoke per-vendor version endpoints. Only fires when
            // the earlier sources all miss and a recipe exists.
            VendorProbeSource()
        ], toolbox: ToolboxSource(inventory: toolbox))
        let checked = await checker.check(found)
        results = sorted(checked)
        await computeRestartInfo()
        isChecking = false
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
        case "Vendor":
            // An official-website app with a resolved installer archive (zip/dmg/
            // tar.gz). We download it, verify the code signature matches the
            // installed app's Team ID, then swap in place — same channel, no mix.
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
        case "Vendor":
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
        guard !results.isEmpty, !isChecking else { return }
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
            // Toolbox owns its apps' status (computed from its own cache, not a
            // version compare) — keep it; don't re-evaluate locally.
            guard remote.sourceName != "Toolbox" else {
                return UpdateResult(app: app, remote: remote, status: was.status)
            }
            return UpdateResult(
                app: app, remote: remote,
                status: UpdateChecker.evaluate(installed: app, remote: remote))
        }
        results = sorted(updated)
        computeRestartInfo()
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

    /// Install an update, routing to the right installer for its source.
    func install(_ result: UpdateResult) async {
        let id = result.id
        installErrors[id] = nil

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
            await computeRestartInfo()
            installing[id] = nil
            return
        }

        do {
            // pkg casks: download the official installer and open it. The
            // actual install happens in macOS's installer under the user's
            // control, so we don't mark it up to date — a later rescan will.
            if requiresInstaller(result) {
                installing[id] = .downloading(fraction: 0)
                try await packageInstaller.downloadAndOpen(
                    url: result.remote?.downloadURL,
                    headers: result.remote?.downloadHeaders ?? [:]
                ) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
                installing[id] = nil
                return
            }

            switch result.remote?.sourceName {
            case "Homebrew":
                guard let token = result.remote?.sourceIdentifier else { return }
                installing[id] = .runningCommand("starting brew…")
                try await homebrewInstaller.upgrade(caskToken: token) { line in
                    Task { @MainActor in self.setStage(id, .runningCommand(line)) }
                }
            case "Vendor":
                installing[id] = .downloading(fraction: 0)
                try await vendorInstaller.install(result) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
            default:
                installing[id] = .downloading(fraction: 0)
                try await sparkleInstaller.install(result) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
            }
            // Re-read from disk to reflect the new version, then recompute the
            // Restart flag by comparing each running instance's launch version
            // to what's now on disk. In-place installs (Homebrew) leave the old
            // process running stale code; Sparkle relaunches, so it won't show.
            let updated = await recheck(result)
            replaceRow(updated)
            await computeRestartInfo()

            // Tell the user it landed. If the app was running, its live process
            // is still on the old code (so it's in needsRestart) — point them at
            // the Restart action. Otherwise the in-place swap is already fully in
            // effect and there's nothing left to do.
            let version = updated.app.shortVersion
            if needsRestart.contains(updated.id) {
                UpdateNotifier.readyToRestart(app: updated.app.name, version: version)
            } else {
                UpdateNotifier.updated(app: updated.app.name, version: version)
            }
        } catch {
            installErrors[id] = error.localizedDescription
        }
        installing[id] = nil
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
        for result in results where !result.hasUpdate {
            guard let bundleID = result.app.bundleID,
                  let runVersion = running[bundleID],
                  let disk = result.app.buildVersion ?? result.app.shortVersion,
                  VersionComparator.isNewer(disk, than: runVersion) else { continue }
            ids.insert(result.id)
            versions[result.id] = runVersion
        }
        needsRestart = ids
        runningVersionByID = versions
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
            let timeout = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
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
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { needsRestart.remove(result.id); return }
        for app in running { app.terminate() }
        for _ in 0..<30 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return  // still up (likely a save prompt) — leave the badge
        }
        let relaunched = NSWorkspace.shared.open(result.app.path)
        needsRestart.remove(result.id)
        runningVersionByID[result.id] = nil
        if relaunched {
            UpdateNotifier.restarted(app: result.app.name, version: result.app.shortVersion)
        }
    }

    /// Re-read one app from disk and re-check it across all sources. Cheap
    /// enough to run right before installing, as a guard against acting on a
    /// stale row.
    private func recheck(_ result: UpdateResult) async -> UpdateResult {
        let id = result.id
        let apps = await Task.detached(priority: .userInitiated) {
            AppScanner().scan()
        }.value
        guard let fresh = apps.first(where: { $0.id == id }) else { return result }
        let checker = UpdateChecker(sources: [
            MacAppStoreSource(),
            SparkleAppcastSource(),
            HomebrewCaskSource(),
            // GitHub Releases for apps distributed that way (detection only).
            GitHubReleasesSource(token: githubToken),
            // Last resort: bespoke per-vendor version endpoints. Only fires when
            // the earlier sources all miss and a recipe exists.
            VendorProbeSource()
        ], toolbox: ToolboxSource())
        return await checker.check(fresh)
    }

    /// Replace a single row by id and re-sort.
    private func replaceRow(_ updated: UpdateResult) {
        if let idx = results.firstIndex(where: { $0.id == updated.id }) {
            results[idx] = updated
            results = sorted(results)
        }
    }

    private func sorted(_ list: [UpdateResult]) -> [UpdateResult] {
        list.sorted { a, b in
            if a.hasUpdate != b.hasUpdate { return a.hasUpdate }
            return a.app.name.localizedCaseInsensitiveCompare(b.app.name) == .orderedAscending
        }
    }
}
