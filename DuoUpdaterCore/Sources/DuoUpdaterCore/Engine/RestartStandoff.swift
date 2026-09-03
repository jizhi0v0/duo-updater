import Foundation

/// Whether it is safe to quit an app in order to put our update into effect.
///
/// Usually it is, and the quit is ours alone. But an app with its own updater
/// can have a build already downloaded, unpacked and parked, with an installer
/// process waiting for precisely one signal: that app terminating. Our restart
/// is that signal. Sparkle 2's installer agent and Squirrel's `ShipIt` both work
/// this way, and both wait as long as it takes — 22 minutes for ChatGPT on
/// 2026-08-22, 6 hours 49 minutes for Claude the day before, same PID throughout.
///
/// So a quit we think of as the last step of our install is also the first step
/// of theirs, and theirs runs second:
///
///     15:15:29  our swap lands 26.818.41705, verified on disk
///     15:15:29  quit for restart  →  appDeath  →  Autoupdate wakes
///     15:16:04  disk reads 26.818.41509, the build Sparkle had staged at 14:53
///
/// Nothing failed. The install was correct, the restart was correct, and the
/// user saw the update reappear.
///
/// **Sparkle 1 is not covered.** Its automatic driver arms an
/// `NSApplicationWillTerminateNotification` observer in the host process and
/// launches `Autoupdate.app` only after the quit has begun. Before the decision
/// this type is asked to make there is therefore no parked helper to enumerate.
/// The gap is not that its extraction is unfindable: Sparkle 1 stages downloads
/// and extraction under `Caches/<bundleID>/org.sparkle-project.Sparkle/
/// PersistentDownloads/` (confirmed against the 1.16.0 and 1.27.3 sources —
/// `SPUDownloader.getAndCleanTempDirectory` calls `SPULocalCacheDirectory
/// .cachePathForBundleIdentifier:`), the same bundle-id-keyed tree
/// `sparkleStagedBundle` already walks for Sparkle 2's `Installation/`, just a
/// different subdirectory. What is missing is a signal independent of the host
/// process that proves an install is armed: `PersistentDownloads/` has the same
/// stale-leftover problem `Installation/` does — Sparkle only garbage-collects
/// entries older than ten days, and only on the next staging run — so an
/// unpacked bundle sitting there is no more evidence than one in `Installation/`
/// is. `disableSuddenTermination` accompanies the hook, but no public
/// cross-process API and acceptable noise floor have been established for that
/// signal. Do not turn any of those into a hold-back predicate without first
/// measuring it.
///
/// The decision therefore is not "is another installer armed" — that alone is
/// harmless — but "is it armed with something OTHER than what we just wrote".
/// When both sides hold the same build the quit is safe: whichever installer
/// runs second writes the same bytes. TablePlus was in exactly that state the
/// same afternoon, staging 26.9.11 while we were about to install 26.9.11, and
/// there was nothing to prevent.
public enum RestartStandoff {

    public enum Decision: Sendable, Equatable {
        /// No conflicting installer is parked; quit as normal.
        case proceed
        /// Another installer holds a different build. Quitting would apply it
        /// over ours, so don't — the restart is the user's to make once they know.
        case holdBack(stagedVersion: String)
    }

    /// `staged` is what the app's own updater will install on quit (nil if
    /// nothing is staged); the two `onDisk` values are the bundle as it stands
    /// now, i.e. what we just installed.
    ///
    /// **Every field that both sides carry must match**, not just the marketing
    /// string. The first version of this compared `CFBundleShortVersionString`
    /// alone, which is blind to the case it was written for: a vendor that keeps
    /// the marketing version stable across builds could have 1.4.2 (5104) parked
    /// while we install 1.4.2 (5120), the strings would agree, the restart would
    /// be waved through, and 5104 would land on top of ours — the exact failure
    /// this type exists to prevent, wearing a different version scheme.
    ///
    /// The bias is deliberate and one-directional. Holding back costs a manual
    /// quit; proceeding when the builds differ silently undoes an install the
    /// user asked for. So it takes at least one field the two sides agree on to
    /// proceed, and any disagreement — or nothing comparable at all, as with an
    /// unreadable bundle — holds back.
    ///
    /// "At least one", not "all of them present": a bundle whose build number is
    /// readable and matches is proof enough even if its marketing string is
    /// missing, and vice versa. Requiring both would hold back on every app whose
    /// staged copy omits `CFBundleVersion`.
    public static func decide(
        staged: StagedSelfUpdate?,
        onDiskShortVersion: String?,
        onDiskBuildVersion: String?
    ) -> Decision {
        guard let staged else { return .proceed }

        // Only pairs where BOTH sides carry a value can be compared; a field
        // missing on either side proves nothing either way. That rule lives in
        // `VersionComparator.isSame` now — this function was the one place in the
        // codebase that had it right, so the others were changed to share it
        // rather than it being restated here.
        let onDisk = VersionSide(marketing: onDiskShortVersion, build: onDiskBuildVersion)
        guard VersionComparator.isSame(staged.versionSide, as: onDisk)
        else { return .holdBack(stagedVersion: staged.version) }
        return .proceed
    }
}
