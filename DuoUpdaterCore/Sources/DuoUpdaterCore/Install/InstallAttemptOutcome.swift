import Foundation

/// What one install attempt actually did to the machine.
///
/// A `Bool` could not say it. Three outcomes reach the caller and only one of
/// them is an app that is now updated:
///
///   * `installed` — a bundle was replaced (or the store finished an install).
///   * `handedOffToSystemInstaller` — a vendor `.pkg` was staged and opened in
///     macOS's Installer. Nothing is installed yet: the user drives that window,
///     and a later rescan settles the row. It is not a failure either, so the row
///     keeps its staged-package bookkeeping and gets no error.
///   * `notInstalled` — an early-out (already current, missing id, cancelled) or
///     a failure. Which one it was lives in the row's error, not here.
///
/// The distinction is load-bearing for the batch summary: "Update All" counts
/// these to post "N apps were updated". While the hand-off returned `true`, a
/// batch of two vendor-pkg apps announced "2 apps were updated" while both
/// Installer windows were still open and nothing had been replaced.
public enum InstallAttemptOutcome: Equatable, Sendable {
    case installed
    case handedOffToSystemInstaller
    case notInstalled

    /// Whether this attempt may be counted into "N apps were updated".
    ///
    /// Only a real install may. A hand-off is deliberately excluded rather than
    /// folded in with the failures: it is the one non-failure that has not
    /// updated anything *yet*.
    public var countsAsUpdatedApp: Bool {
        self == .installed
    }
}
