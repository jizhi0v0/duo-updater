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
        let apps = await Inventory.scan(settings)
        let selected: [InstalledApp]
        switch Inventory.select(apps, matching: options.queries) {
        case .success(let matched): selected = matched
        case .failure(let message):
            FileHandle.standardError.write(Data("duo: \(message)\n".utf8))
            return 2
        }

        let results: [UpdateResult]
        if options.checkForUpdates {
            results = await Inventory.checker(settings).check(selected)
        } else {
            results = selected.map { UpdateResult(app: $0, remote: nil, status: .unknown) }
        }

        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: runningBundlePaths(),
            stagedSelfUpdates: [:])

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
