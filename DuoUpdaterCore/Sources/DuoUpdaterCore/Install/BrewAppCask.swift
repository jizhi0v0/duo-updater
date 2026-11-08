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
public struct BrewAppCask: Sendable, Equatable {
    /// The package row it gets while unclaimed.
    public let row: BrewInstalledFormula
    /// Its apps that have rows: standardized paths.
    public let appPaths: [String]

    public init(row: BrewInstalledFormula, appPaths: [String]) {
        self.row = row
        self.appPaths = appPaths
    }

    /// The casks (by row name) whose apps all have rows that a finished check
    /// found no update source for, and none of which the person ignored.
    ///
    /// Strict on purpose. Before a check round has answered (`checked`), every
    /// row is an unchecked `.unknown`, indistinguishable from "no source". An app
    /// with no row here (moved, or not scanned) cannot be vouched for. A row that
    /// any source answered for — even with an error — has its own update route,
    /// and a cask listed beside it would offer a second one.
    public static func unclaimed(
        _ casks: [BrewAppCask], rows: [UpdateResult], checked: Bool,
        isIgnored: (InstalledApp) -> Bool
    ) -> Set<String> {
        guard checked else { return [] }
        var byPath: [String: UpdateResult] = [:]
        for row in rows { byPath[row.app.path.standardizedFileURL.path] = row }
        var names: Set<String> = []
        for cask in casks where !cask.appPaths.isEmpty {
            let found = cask.appPaths.compactMap { byPath[$0] }
            guard found.count == cask.appPaths.count,
                  found.allSatisfy({ $0.remote == nil && $0.status == .unknown && !isIgnored($0.app) })
            else { continue }
            names.insert(cask.row.name)
        }
        return names
    }
}
