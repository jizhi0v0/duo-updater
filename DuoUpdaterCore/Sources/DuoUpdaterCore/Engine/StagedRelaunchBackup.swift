import Foundation

/// The rollback point a Relaunch takes before it quits an app so the app's own
/// updater (ShipIt, Sparkle, Spotify's) can apply a build it already downloaded.
///
/// Our own installs back up before every route. A Relaunch did not, so an update
/// applied that way never reached the Rollback list or the bundle diff, and the
/// backup that was there — from an earlier install of ours — was now two versions
/// behind. These are the two decisions around taking one; the copy itself is
/// `InstallCoordinator.backUp`, the same call the install path makes.
public enum StagedRelaunchBackup {

    /// Whether to take a rollback point before quitting the app.
    ///
    /// Not when the user turned backups off. And not when the bundle on disk has
    /// already moved past the version the row was built from: the row is a
    /// snapshot from the last scan, and the apps that reach Relaunch are exactly
    /// the ones that replace themselves. A copy taken then would hold the NEW
    /// build under the OLD version's label, and "roll back" would restore the
    /// update it claims to undo.
    ///
    /// An unreadable bundle is not a landing (`RelaunchProgress.hasLanded` fails
    /// closed), so it still gets an attempt — and `backUp` then reports that it
    /// could not read it, rather than this silently skipping.
    public static func shouldTake(
        keepBackups: Bool, old: VersionSide, disk: VersionSide, buildIsDerived: Bool
    ) -> Bool {
        guard keepBackups else { return false }
        return !RelaunchProgress.hasLanded(old: old, disk: disk, buildIsDerived: buildIsDerived)
    }

    /// Whether the copy just taken is a copy of one build, so it can be kept and
    /// the relaunch can go on.
    ///
    /// The copy takes seconds (`InstallCoordinator.wantsBackup` records Word at
    /// ~8.7s to clone plus ~8.7s to fingerprint; quoted, not re-measured), and the swap-on-quit updaters are waiting for exactly one thing: every
    /// instance of the app to quit. A user who quits it themselves during that
    /// window lets the updater rewrite the bundle while `ditto` is still reading
    /// it. The manifest is computed from the copy, so a torn copy would verify
    /// against itself and restore cleanly into a broken app.
    ///
    /// So a copy is intact only if every instance that was running when it
    /// started is still running when it ended (none quit, so no swap-on-quit
    /// could have started), and the bundle on disk still has not moved past the
    /// version we copied (no updater swapped it in place either). A reopened app
    /// has new process ids, so quit-and-reopen during the copy is not intact
    /// either. An empty `runningBefore` proves nothing and is not intact.
    ///
    /// When this is false the caller also stands down rather than quitting: the
    /// user has taken the relaunch into their own hands, and whatever is running
    /// now may already be the new build.
    public static func isIntact(
        runningBefore: Set<pid_t>, runningAfter: Set<pid_t>,
        old: VersionSide, diskAfter: VersionSide, buildIsDerived: Bool
    ) -> Bool {
        guard !runningBefore.isEmpty, runningBefore.isSubset(of: runningAfter) else { return false }
        return !RelaunchProgress.hasLanded(old: old, disk: diskAfter, buildIsDerived: buildIsDerived)
    }
}
