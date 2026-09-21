import Foundation

/// The App Store keeps one copy of an app per Apple ID, and installs its update
/// wherever it thinks that copy is — not necessarily the row we clicked. When a
/// vendor renames the bundle, the old one can be left behind under the same
/// bundle id and product id, and every Update on it lands on the other copy.
///
/// Measured 2026-09-21 on AndroMeld (`com.catchingnow.andfiles`, ADAM 6762439757):
/// `/Applications/AndDrive.app` stayed at 1.9.0 while the store kept writing
/// 1.10.0 into `/Applications/AndroMeld.app` (FSEvents on that path at 15:21:59,
/// 15:35:06, 15:35:25, each before `mas` returned). The row re-read AndDrive.app,
/// said "now 1.9.0", showed "Updated ✓", and offered the same update again —
/// three times, each with a 98 MB backup of the copy nothing touched.
public enum AppStoreLeftoverCopy {
    /// Another App Store copy of `app` that is already at `target` or newer, or
    /// nil. Such a copy means the store has nothing left to install for this
    /// product, and whatever it does install goes there, not to `app`.
    ///
    /// Same bundle id, both store copies, a different path, and the same product
    /// id when both carry one. A copy without `_MASReceipt` is a different
    /// distribution the store never writes to, so it is not a sibling here.
    public static func sibling(
        of app: InstalledApp, target: String, among others: [InstalledApp]
    ) -> InstalledApp? {
        guard app.isMASApp, let bundleID = app.bundleID else { return nil }
        let own = app.path.resolvingSymlinksInPath().path
        return others.first { other in
            guard other.isMASApp, other.bundleID == bundleID,
                  other.path.resolvingSymlinksInPath().path != own,
                  let version = other.shortVersion
            else { return false }
            if let a = app.appStoreAdamID, let b = other.appStoreAdamID, a != b { return false }
            return !VersionComparator.isNewer(target, than: version)
        }
    }

    /// Every row offering a store update that a sibling row already holds, keyed
    /// by row id, with that sibling. Such a row is an orphan: its Update can only
    /// ever land on the other copy, so it is not an update to offer or count.
    ///
    /// Answered from the rows as last scanned, not a fresh disk read — this runs
    /// whenever the list changes. The install path re-reads the disk itself
    /// (`AppListModel.appStoreSiblingAtTarget`) for the copy a click creates.
    public static func orphans(in results: [UpdateResult]) -> [String: InstalledApp] {
        let apps = results.map(\.app)
        var found: [String: InstalledApp] = [:]
        for result in results where result.hasUpdate && result.app.isMASApp {
            guard let target = result.remote?.shortVersion,
                  let sibling = sibling(of: result.app, target: target, among: apps)
            else { continue }
            found[result.id] = sibling
        }
        return found
    }
}
