import Foundation

/// An installed homebrew/cask cask whose apps have rows of their own, and the
/// apps it installed.
///
/// Such a cask is normally left to its app rows: listing it as a package too
/// would show one app twice, and Upgrade All would run `brew` on an app whose
/// own updater (Sparkle, say) keeps it current while the cask's record goes
/// stale. But when none of its app rows found an update source, nothing else
/// shows the cask's updates — `karabiner-elements` before its apps could be
/// matched through the package receipt was invisible everywhere. Then it is a
/// package row like an app-less cask (`unclaimed`).
/// A suite is different: it always keeps its package row, and the member app
/// rows link there instead of independently updating parts of the group.
public struct BrewAppCask: Sendable, Equatable {
    /// Its package row, shown while unclaimed or permanently for a suite.
    public let row: BrewInstalledFormula
    /// Its apps that have rows: standardized paths.
    public let appPaths: [String]
    /// A registered suite is always a Brew package row. Member rows only link
    /// to it; their individual versions are not the suite's package version.
    public let isSuite: Bool

    public init(row: BrewInstalledFormula, appPaths: [String], isSuite: Bool = false) {
        self.row = row
        self.appPaths = appPaths
        self.isSuite = isSuite
    }

    /// The casks (by row name) whose apps all have rows that a finished check
    /// found no update source for, and none of which the person ignored.
    ///
    /// Strict on purpose. Before a check round has answered (`checked`), every
    /// row is an unchecked `.unknown`, indistinguishable from "no source". An app
    /// with no row here (moved, or not scanned) cannot be vouched for. A row that
    /// any source answered for — even with an error — has its own update route,
    /// and a cask listed beside it would offer a second one.
    ///
    /// And every app must still be at the version Homebrew recorded installing.
    /// "No source" can hide an app that moved past that record — its own
    /// updater ran — when no source matched it at all (its name or bundle id
    /// matched another cask, so the receipt match never ran). For such an app
    /// brew's non-greedy `outdated` compares only the record: Upgrade All would
    /// reinstall, under sudo, a release older than the one on disk.
    /// Suites are always included, even before a member check or when a member
    /// is ignored; members have no independent update action to duplicate.
    public static func unclaimed(
        _ casks: [BrewAppCask], rows: [UpdateResult], checked: Bool,
        isIgnored: (InstalledApp) -> Bool
    ) -> Set<String> {
        var names = Set(casks.filter(\.isSuite).map(\.row.name))
        guard checked else { return names }
        var byPath: [String: UpdateResult] = [:]
        for row in rows { byPath[row.app.path.standardizedFileURL.path] = row }
        for cask in casks where !cask.isSuite && !cask.appPaths.isEmpty {
            let found = cask.appPaths.compactMap { byPath[$0] }
            guard found.count == cask.appPaths.count,
                  found.allSatisfy({ $0.remote == nil && $0.status == .unknown && !isIgnored($0.app) }),
                  found.allSatisfy({ isAtRecord($0.app, cask.row.installedVersion) })
            else { continue }
            names.insert(cask.row.name)
        }
        return names
    }

    /// Every app of `cask` is, on disk right now, at the version Homebrew
    /// recorded. `unclaimed` reads the last scan, which lags an app's own
    /// updater until the folder watcher's rescan lands; a brew run that takes
    /// the cask through this net asks this first, so a release older than the
    /// one on disk is never installed over it in that window.
    public static func onDiskAtRecord(
        _ cask: BrewAppCask,
        readVersion: (String) -> String? = BrewAppCask.bundleShortVersion
    ) -> Bool {
        // Brew owns the complete suite. A member's version may be unrelated
        // to the package version, so it cannot authorise or block the group.
        if cask.isSuite { return true }
        guard !cask.appPaths.isEmpty,
              let record = cask.row.installedVersion.split(whereSeparator: { $0 == "," || $0 == ":" }).first
        else { return false }
        return cask.appPaths.allSatisfy { path in
            guard let version = readVersion(path) else { return false }
            return VersionComparator.compare(String(record), version) == .orderedSame
        }
    }

    /// `CFBundleShortVersionString` read from the bundle's Info.plist now, not
    /// through `Bundle`, which caches. Found and trimmed as the scanner does
    /// (`BundleLayout.infoPlistURL`, `VersionSide.plistVersionField`), or a
    /// value the scan reads as the record would never match here.
    public static func bundleShortVersion(_ path: String) -> String? {
        let plist = BundleLayout.infoPlistURL(for: URL(fileURLWithPath: path))
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return VersionSide.plistVersionField(info["CFBundleShortVersionString"])
    }

    /// The bundle's version is the one Homebrew recorded, cut at `,`/`:` as the
    /// receipt match cuts it (`HomebrewCaskSource`).
    static func isAtRecord(_ app: InstalledApp, _ recorded: String) -> Bool {
        guard let installed = app.shortVersion,
              let record = recorded.split(whereSeparator: { $0 == "," || $0 == ":" }).first
        else { return false }
        return VersionComparator.compare(String(record), installed) == .orderedSame
    }
}
