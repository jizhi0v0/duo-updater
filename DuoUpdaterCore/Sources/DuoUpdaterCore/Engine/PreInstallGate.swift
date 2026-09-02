import Foundation

/// What the defensive re-check immediately before an install concluded.
///
/// Clicking Update does NOT install what the row was showing. The row may have
/// been checked minutes or hours ago; since then the vendor may have published
/// again, the app may have updated itself, or a package may have been installed by
/// hand. So the install path re-reads the bundle off disk and re-queries the source
/// first, and decides from THAT.
///
/// The decision used to be a single `guard result.hasUpdate`, which is true only
/// for `.updateAvailable` — so every other outcome fell into one branch that logged
/// "already current on disk". Three unrelated endings wore the same sentence:
///
///  - genuinely current (the manual-install / self-updater case the branch was
///    written for),
///  - the source was tried and FAILED — a timeout, a 404, a rate limit — which is
///    not a verdict about the app at all and is retryable,
///  - the app turned out to be managed elsewhere (App Store, Toolbox, TestFlight).
///
/// The middle one is the damaging conflation: a network blip while you click Update
/// produces "already current on disk" in the log, which reads as a fact about the
/// disk and sends the next person looking at the bundle instead of the network.
/// `UpdateStatus` already draws exactly this line — `.unknown` is "nothing covers
/// this app", `.error` is "a source was tried and failed, retryable" — and this is
/// the install path finally reading it.
public enum PreInstallDecision: Sendable, Equatable {
    /// A newer version was confirmed just now. Install it.
    case proceed
    /// The bundle on disk is already current. Nothing to do, and not a failure.
    case alreadyCurrent
    /// Something else owns this app's updates. Nothing to do, and not a failure.
    case managedElsewhere
    /// We could not establish whether an update exists. Carries the source's own
    /// message when there was one; `nil` when no source covers the app at all.
    ///
    /// Deliberately NOT folded into `alreadyCurrent`: "we didn't find out" and
    /// "there is nothing to find" are different answers, and only one of them is
    /// worth retrying.
    case cannotConfirm(String?)
}

public enum PreInstallGate {
    public static func decision(for status: UpdateStatus) -> PreInstallDecision {
        switch status {
        case .updateAvailable:
            return .proceed
        case .upToDate:
            return .alreadyCurrent
        case .appStoreManaged, .toolboxManaged, .testFlightManaged:
            return .managedElsewhere
        case .error(let message):
            return .cannotConfirm(message)
        case .unknown:
            return .cannotConfirm(nil)
        }
    }
}
