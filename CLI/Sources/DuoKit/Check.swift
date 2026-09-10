import Foundation
import DuoUpdaterCore

/// `duo list` and `duo check` — what is installed, and what has an update.
///
/// `list` is offline and instant; `check` is `list` plus the network. They share
/// their output shape so a `--json` consumer can treat them the same.
public enum Check {

    public struct Options: Sendable {
        public var queries: [String] = []
        public var json = false
        /// Show every app, not just the ones with an update. Implied by `list`.
        public var all = false
        /// Include apps the user ignored or whose offered version they skipped.
        public var includeHidden = false
        public var checkForUpdates = true
        /// Keep only apps answered by these sources, matched case-insensitively
        /// against `RemoteVersion.sourceName` ("Sparkle", "Homebrew", "Vendor",
        /// "GitHub", "App Store", …). Empty means every source.
        public var sources: Set<String> = []
        /// Ask TestFlight to refresh its local store before checking.
        ///
        /// Off by default and never implied: it starts an app the user did not
        /// start. See `TestFlightRefresh` for why a background launch is the only
        /// form of this we are willing to offer, and #478 for why the store goes
        /// stale in the first place.
        public var refreshTestFlight = false
        public init() {}
    }

    /// One row, in the shape both commands emit. `NDJSON` rather than one big
    /// array so a slow check prints rows as they resolve instead of after.
    struct Row: Encodable {
        let name: String
        let bundleID: String?
        let path: String
        let installedVersion: String?
        let installedBuild: String?
        let latestVersion: String?
        /// The build behind `latestVersion`, when the source reports one. Only
        /// interesting when the marketing version doesn't move — see `emitText`.
        var latestBuild: String? = nil
        let source: String?
        let status: String
        /// Whether the source reports something newer — NOT `latestVersion !=
        /// nil`, which is also true for an app that is already current and made
        /// `--all` report every checked app as an available update.
        let hasUpdate: Bool
        let hidden: Bool
        let route: String?
    }

    /// What to tell the user about a refresh attempt. Written to stderr so `--json`
    /// stays one object per line, and phrased so that "we launched TestFlight" is
    /// never left implicit — the user is entitled to know why an app appeared.
    static func describe(_ outcome: TestFlightRefresh.Outcome) -> String {
        switch outcome {
        case .refreshed(let after):
            // The moment the store last changed, NOT how long the command waited:
            // the wait runs on past it by `settleInterval` to be sure the sync has
            // finished. Measured 6.0s here against 14.0s wall clock, so saying
            // "took" would be wrong by more than half.
            let seconds = Double(after.components.seconds) + Double(after.components.attoseconds) / 1e18
            return String(format: "duo: TestFlight refreshed its data (new data landed after %.1fs)", seconds)
        case .changedWithoutSettling(let lastChange):
            // Says "may not have finished", never "refreshed". The row printed
            // immediately below this line can be the pre-sync one, and a user who
            // was told the refresh succeeded has no reason to look twice.
            let seconds = Double(lastChange.components.seconds)
                + Double(lastChange.components.attoseconds) / 1e18
            return String(
                format: "duo: TestFlight was still writing when we stopped waiting "
                      + "(last seen moving after %.1fs); the versions below may predate the sync",
                seconds)
        case .launchedWithoutChange:
            return "duo: launched TestFlight in the background; its data did not change"
        case .activatedWithoutChange:
            return "duo: nudged the running TestFlight; its data did not change"
        case .activationUnavailable:
            return "duo: TestFlight is already running, and this macOS does not let us reload it "
                 + "without taking the screen. Switch to TestFlight yourself if you want its data reloaded."
        case .refusedSecureInput:
            // Secure keyboard entry is session-wide, and Terminal's own Secure
            // Keyboard Entry holds it for the life of the terminal you are probably
            // reading this in. So this must not promise it will clear on its own.
            return "duo: secure keyboard entry is on, so TestFlight was left alone. "
                 + "A password field, a password manager, or your terminal's Secure Keyboard Entry holds it."
        case .alreadyFrontmost:
            return "duo: TestFlight is open in front of you — its own window is more current than anything we can reload"
        case .activationFailed(let code):
            return "duo: could not reload the running TestFlight (code \(code))"
        case .focusNotRestored(let code):
            return "duo: reloaded TestFlight, but could not put your focus back (code \(code)) — "
                 + "TestFlight may be in front now"
        case .notInstalled:
            return "duo: TestFlight is not installed, so there is nothing to refresh"
        case .launchFailed:
            return "duo: could not launch TestFlight"
        }
    }

    /// A row worth acting on: an update the user has not hidden.
    static func isActionable(_ row: Row) -> Bool { row.hasUpdate && !row.hidden }

    /// The (installed, latest) build pair to show when the marketing version stays
    /// put, mirroring `UpdateResult.buildBump` on the row shape this command emits.
    static func buildBump(_ row: Row) -> (installed: String, remote: String)? {
        guard row.latestVersion == row.installedVersion,
              let installed = row.installedBuild.map(UpdateResult.strippingBuildPrefix),
              let remote = row.latestBuild.map(UpdateResult.strippingBuildPrefix),
              installed != remote
        else { return nil }
        return (installed, remote)
    }

    public static func run(_ options: Options) async -> Int32 {
        let settings = Settings.load()
        // Before the scan, not just before the check. `AppScanner` reads the
        // TestFlight store too — that is where a bundle gets tagged
        // `isTestFlightApp`, and for a wrapped iPhone/iPad app the store is the
        // evidence (#456), the receipt being unavailable. Refreshing after the scan
        // would leave this run's tagging on the stale store and only fix the
        // version comparison, so a beta installed since the last sync would still
        // be read as something else until the next invocation.
        if options.refreshTestFlight {
            let outcome = await TestFlightRefresh().run()
            FileHandle.standardError.write(Data((describe(outcome) + "\n").utf8))
        }
        let apps = await Inventory.scan(settings)
        let selected: [InstalledApp]
        switch Inventory.select(apps, matching: options.queries) {
        case .success(let matched): selected = matched
        case .failure(let message):
            FileHandle.standardError.write(Data("duo: \(message)\n".utf8))
            return 2
        }

        // An ignored app is not asked after — its row would be filtered out below
        // anyway, so the request buys nothing. Two things override that, and both
        // are the user asking about this app specifically: naming it, and asking
        // for hidden rows. `list` asks no source at all, so it never filters here.
        let checkable = options.checkForUpdates
            ? settings.appsWorthChecking(
                selected, named: !options.queries.isEmpty, includeHidden: options.includeHidden)
            : selected

        let results: [UpdateResult]
        if options.checkForUpdates {
            results = await Inventory.checker(settings).check(checkable)
        } else {
            results = selected.map { UpdateResult(app: $0, remote: nil, status: .unknown) }
        }

        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: runningBundlePaths(),
            stagedSelfUpdates: [:],
            elevationRequiredPaths: InPlaceSwap.elevationRequiredPaths(
                for: results.map(\.app.path)),
            runningBundleIDs: runningBundleIDs())

        var rows: [Row] = []
        for result in results.sorted(by: { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }) {
            let hidden = settings.isHidden(result)
            if hidden && !options.includeHidden { continue }
            if !options.all && !result.hasUpdate { continue }
            if !options.sources.isEmpty {
                // An app no source answered for has no source to match, so a
                // `--source` filter excludes it rather than letting it through.
                let source = result.remote?.sourceName.lowercased() ?? ""
                guard options.sources.contains(source) else { continue }
            }
            rows.append(Row(
                name: result.app.name,
                bundleID: result.app.bundleID,
                path: result.app.path.path,
                installedVersion: result.installedDisplay,
                installedBuild: result.app.buildVersion,
                latestVersion: result.remote?.displayVersion,
                latestBuild: result.remote?.version,
                source: result.remote?.sourceName,
                status: describe(result.status),
                hasUpdate: result.hasUpdate,
                hidden: hidden,
                route: options.checkForUpdates
                    ? route(result, settings: settings, environment: environment)
                    : nil))
        }

        if options.json {
            emitJSON(rows, command: options.checkForUpdates ? "check" : "list")
        } else {
            emitText(rows, checked: options.checkForUpdates)
        }
        // Exit 1 signals "there is something to do", so `duo check && echo clean`
        // works. A hidden row is by definition not something to do.
        return rows.contains(where: isActionable) ? 1 : 0
    }

    /// How this update *would* be applied, from the same policy the app uses.
    ///
    /// The environment is deliberately conservative here: the CLI has not yet
    /// registered the privileged helper (`SMAppService.daemon` needs a bundle,
    /// which a standalone binary does not have), and it does not track staged
    /// self-updates, so both are reported as unavailable rather than assumed.
    /// That makes `duo check` understate the App Store `.full` route rather than
    /// promise a one-click it cannot deliver.
    static func route(
        _ result: UpdateResult, settings: Settings, environment: InstallEnvironment
    ) -> String? {
        guard result.hasUpdate else { return nil }
        if UpdatePolicy.defersToSelfUpdater(
            result, settings: settings.updateSettings, environment: environment) {
            return "self-updater"
        }
        if UpdatePolicy.canAutoInstall(
            result, settings: settings.updateSettings, environment: environment) {
            return "in-place"
        }
        if UpdatePolicy.requiresInstaller(result, environment: environment) {
            return "installer"
        }
        return "manual"
    }

    /// Bundle paths with a live process, normalised the same way the app does so
    /// a hot-swapped bundle still matches.
    static func runningBundlePaths() -> Set<String> {
        Set(RunningApps.bundleURLs().map(UpdatePolicy.runtimeBundlePath))
    }

    static func runningBundleIDs() -> Set<String> { RunningApps.bundleIDs() }

    static func describe(_ status: UpdateStatus) -> String {
        switch status {
        case .upToDate:                    return "up-to-date"
        case .updateAvailable(let latest): return "update \(latest)"
        case .unknown:                     return "unknown"
        case .appStoreManaged:             return "app-store"
        case .toolboxManaged:              return "toolbox"
        case .testFlightManaged:           return "testflight"
        case .error(let message):          return "error: \(message)"
        }
    }

    // MARK: - Output

    static func emitJSON(_ rows: [Row], command: String) {
        NDJSON.begin(command)
        for row in rows { NDJSON.row(row) }
    }

    static func emitText(_ rows: [Row], checked: Bool) {
        guard !rows.isEmpty else {
            print(checked ? "Everything is up to date." : "No apps found.")
            return
        }
        let nameWidth = min(38, rows.map(\.name.count).max() ?? 10)
        for row in rows {
            let name = row.name.count > nameWidth
                ? String(row.name.prefix(nameWidth - 1)) + "…"
                : row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            // Same marketing version on both sides (Surge 6.9.0 → 6.9.0, a
            // JetBrains EAP) reads as a no-op unless the builds are shown — the
            // build is what actually moved. Same rule the menu bar applies via
            // `UpdateResult.buildBump`; the two must not describe an update
            // differently.
            let bump = Self.buildBump(row)
            let installed = bump.map { "\(row.installedVersion ?? "?") (\($0.installed))" }
                ?? (row.installedVersion ?? "?")
            var line = "  \(name)  \(installed)"
            if let latestRaw = row.latestVersion {
                let latest = bump.map { "\(latestRaw) (\($0.remote))" } ?? latestRaw
                line += row.hasUpdate ? "  →  \(latest)" : "  (latest \(latest))"
            }
            var tags: [String] = []
            if let source = row.source { tags.append(source) }
            if let route = row.route, route != "manual" { tags.append(route) }
            if row.hidden { tags.append("hidden") }
            if !tags.isEmpty { line += "  [\(tags.joined(separator: ", "))]" }
            print(line)
        }
        let actionable = rows.filter(isActionable).count
        if checked {
            print("\n  \(actionable) update\(actionable == 1 ? "" : "s") available "
                + "of \(rows.count) app\(rows.count == 1 ? "" : "s") shown.")
        }
    }
}
