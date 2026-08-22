import Foundation

/// Whether it is safe to quit an app in order to put our update into effect.
///
/// Usually it is, and the quit is ours alone. But an app with its own updater
/// can have a build already downloaded, unpacked and parked, with an installer
/// process waiting for precisely one signal: that app terminating. Our restart
/// is that signal. Sparkle's `Autoupdate` and Squirrel's `ShipIt` both work this
/// way, and both wait as long as it takes — 22 minutes for ChatGPT on
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
/// The decision therefore is not "is another installer armed" — that alone is
/// harmless — but "is it armed with something OTHER than what we just wrote".
/// When both sides hold the same version the quit is safe: whichever installer
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

    /// `stagedVersion` is what the app's own updater will install on quit (nil if
    /// nothing is staged); `onDiskVersion` is the bundle as it stands now, i.e.
    /// what we just installed.
    ///
    /// An unreadable `onDiskVersion` holds back rather than proceeding. The whole
    /// value of this check is knowing the two agree, and "we could not tell" is
    /// not that — proceeding on it would be guessing with the user's app.
    public static func decide(stagedVersion: String?, onDiskVersion: String?) -> Decision {
        guard let staged = stagedVersion else { return .proceed }
        guard let onDisk = onDiskVersion, staged == onDisk else {
            return .holdBack(stagedVersion: staged)
        }
        return .proceed
    }
}
