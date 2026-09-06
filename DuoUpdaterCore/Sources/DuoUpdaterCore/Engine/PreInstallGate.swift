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
    /// The re-check answered with a version OLDER than the one the row was
    /// offering when the click landed, and called the app current on the strength
    /// of it. Nothing was installed and nothing is known to be wrong with the
    /// bundle — the source contradicted itself, one second apart.
    ///
    /// Its own case rather than `alreadyCurrent` because the sentence
    /// `alreadyCurrent` produces ("already current on disk") is a claim about the
    /// disk, and here it is false: the disk still carries the older build the row
    /// was offering to replace.
    ///
    /// Observed 2026-09-06 on Nowdex (an App Store iOS-on-Mac app): four clicks
    /// over ~40 minutes, every one of them swallowed. Each time the scheduled
    /// check's batched iTunes lookup answered 1.0.9 and the click's own
    /// single-bundle lookup answered 1.0.8 seconds later — both live network
    /// loads, in one process, and the two bodies differed in length, so they were
    /// two documents and not one document read twice. It turned out to be the
    /// machine's outbound path handing that one URL a stale copy; the same URL
    /// from another process on the same machine answered 1.0.9 throughout, and
    /// re-routing it fixed the install.
    ///
    /// That cause is not something this gate can see, and the point is that it
    /// does not have to: an answer that walks backwards is not evidence the user
    /// already installed something, whatever made it walk backwards.
    ///
    /// Carries no message: the two version strings live in `UpdateResult`s the
    /// caller already holds, and the wording belongs where the rest of the
    /// user-facing copy is.
    case answerRegressed
}

public enum PreInstallGate {

    /// Classify the re-check's outcome.
    ///
    /// `offered` is what the row was showing when the click landed; `confirmed` is
    /// what the re-check just answered. Both are ``VersionSide`` pairs and are
    /// compared with ``VersionComparator/isNewer(_:than:)-(VersionSide,VersionSide)``,
    /// so a vendor that freezes its marketing string is decided on its build and
    /// nothing is ever compared across namespaces. Neither is optional: a caller
    /// that does not have one passes an empty ``VersionSide``, which is
    /// incomparable and therefore never regressed — the comparator fails closed —
    /// and the answer is the one this gate always gave.
    public static func decision(
        for status: UpdateStatus,
        offered: VersionSide,
        confirmed: VersionSide
    ) -> PreInstallDecision {
        switch status {
        case .updateAvailable:
            // NOT second-guessed, deliberately. A re-check can legitimately come
            // back with a LOWER version than the row was offering — the user moved
            // the app off a beta channel in its own settings between the scan and
            // the click, so the stable release it now resolves is older than the
            // beta that was on the row and still newer than what is installed.
            // Refusing that would block the install the user just asked for. The
            // `.upToDate` arm below is different: there the source is claiming
            // there is nothing to install at all.
            return .proceed
        case .upToDate:
            // The only reading of `.upToDate` this gate refuses. Every other way
            // to reach it — a manual pkg install, the app's own updater, a build
            // that landed between the last scan and the click — leaves `confirmed`
            // at or above what was offered, so this comparison is false and the
            // answer is unchanged.
            return VersionComparator.isNewer(offered, than: confirmed)
                ? .answerRegressed
                : .alreadyCurrent
        case .appStoreManaged, .toolboxManaged, .testFlightManaged:
            return .managedElsewhere
        case .error(let message):
            return .cannotConfirm(message)
        case .unknown:
            return .cannotConfirm(nil)
        }
    }
}
