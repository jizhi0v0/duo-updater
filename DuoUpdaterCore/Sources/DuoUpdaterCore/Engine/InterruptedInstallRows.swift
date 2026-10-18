import Foundation

/// The rows a window shows for installs an earlier run cut off
/// (`InstallJournal.interruptedInstalls`).
///
/// An app the cut-off install left readable still has its scanned row, which
/// the ladder turns into a Restore (`RowActionState.interruptedInstall`). One
/// it left gone — or with an Info.plist that no longer reads — has none: the
/// scan finds nothing at its path. That row is made here, from the journal:
/// the app's name, the version from before the update, at the app's path. Its
/// icon comes from the copy the journal points at
/// (`InterruptedInstall.iconSource`), which the host draws.
public enum InterruptedInstallRows {

    /// A stand-in row for every interrupted install whose path `scanned` has no
    /// row for. Status `.unknown`: nothing has checked it, and the ladder
    /// answers its interrupted rung before it reads the status.
    public static func standIns(
        _ interrupted: [InstallJournal.InterruptedInstall], scanned: [UpdateResult]
    ) -> [UpdateResult] {
        let paths = Set(scanned.map { $0.app.path.standardizedFileURL.path })
        var seen: Set<String> = []
        return interrupted.compactMap { item in
            let path = item.appPath.standardizedFileURL.path
            // Two cut-off installs of one app are one row.
            guard !paths.contains(path), seen.insert(path).inserted else { return nil }
            return UpdateResult(
                app: InstalledApp(
                    name: item.appName, bundleID: item.bundleID,
                    shortVersion: item.oldVersion, buildVersion: item.oldBuild,
                    path: item.appPath, isMASApp: false, sparkleFeedURL: nil),
                remote: nil, status: .unknown)
        }
    }
}
