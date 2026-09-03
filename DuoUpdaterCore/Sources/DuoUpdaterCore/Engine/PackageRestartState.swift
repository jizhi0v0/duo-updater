import Foundation

/// Whether a package we handed to macOS's installer has landed on disk and left a
/// stale running copy that ought to be restarted.
///
/// This exists because the ordinary "needs restart" check compares the version the
/// running process reports (`lsappinfo`, which reads `Info.plist`) against the
/// version on disk — and that comparison is BLIND for apps whose `Info.plist`
/// version doesn't move between builds. WeChat DevTools is the canonical case: since
/// its 2.02 Electron rewrite every build reports `CFBundleShortVersionString`
/// `36.6.0` (the Electron runtime), so `2.02.a → 2.02.b` looks identical on both
/// sides and no restart is ever detected. Duo Updater's own scan sees the real
/// version (it reads the app's `package.json`), but the running process only ever
/// tells `lsappinfo` `36.6.0`.
///
/// Launch time sidesteps the version entirely: a process that started BEFORE we
/// handed the package to the installer is running the old code, whatever version
/// string it prints; a copy the vendor's own post-install script — or the user —
/// relaunched afterwards started later and is already fresh. That also makes the
/// "the vendor restarts the app itself" case free: the relaunched process's start
/// time is after the hand-off, so nothing stale remains and no restart is offered.
public enum PackageRestartState: Sendable, Equatable {
    /// The install hasn't landed yet — still in the user's hands in the Installer
    /// window, or it was cancelled. Nothing to do; leave the staged package be.
    case pending
    /// Landed, and a copy that predates the hand-off is still running the old code.
    /// Offer a restart (and notify once).
    case readyToRestart
    /// Landed, and nothing stale is running — the app was never open, or the vendor
    /// (or user) already relaunched it. The job is done silently.
    case settled

    /// - Parameters:
    ///   - onDiskVersion: the app's CURRENT on-disk version as Duo Updater's OWN scan
    ///     reads it (which sees the real version even when `Info.plist` is frozen).
    ///   - stagedVersion: the version the handed-off package installs.
    ///   - stagedAt: when the package was handed to macOS's installer.
    ///   - runningLaunchDates: `launchDate` of every currently-running copy of this
    ///     app's bundle (by resolved path — a channel sibling must not stand in).
    ///   - buildIsDerived: whether `onDiskVersion.build` was substituted by
    ///     `AppScanner` rather than read from `CFBundleVersion`. A package source's
    ///     build is not known to share that namespace, so the derived half is
    ///     discarded and landing falls back to marketing-to-marketing.
    ///
    /// "Landed" means the two sides agree in every shared version namespace: the app
    /// now IS the version the package installs, as opposed to still being the old one
    /// (install not done) or already carrying a newer one (the staged package was
    /// superseded, not applied). Normally both marketing and build participate. A
    /// scanner-derived build is removed first because it does not describe the same
    /// namespace as the package build. These used to be bare marketing strings, so
    /// for a vendor that keeps one marketing version across builds they were equal
    /// before the installer had run — `.pending` was never returned and a genuinely-
    /// unfinished install was classified as landed.
    public static func resolve(
        onDiskVersion: VersionSide?,
        stagedVersion: VersionSide,
        stagedAt: Date,
        runningLaunchDates: [Date],
        buildIsDerived: Bool = false
    ) -> Self {
        guard var onDiskVersion else { return .pending }
        if buildIsDerived {
            onDiskVersion = VersionSide(marketing: onDiskVersion.marketing)
        }
        guard VersionComparator.isSame(onDiskVersion, as: stagedVersion)
        else { return .pending }
        let staleRunning = runningLaunchDates.contains { $0 < stagedAt }
        return staleRunning ? .readyToRestart : .settled
    }
}
