import Foundation

/// What the defensive re-check right before an install concluded.
///
/// Approving an install does NOT mean the disk still needs it: the offer being
/// acted on may be minutes or hours old — the vendor may have published again,
/// the app may have updated itself, or a package may have been installed by
/// hand. So every caller re-reads the bundle off disk and re-queries the source
/// first, and decides from THAT, through `decision(for:offered:confirmed:)`
/// below. Two callers do this today: `AppListModel.performInstall` (the
/// menu-bar click) and the CLI's `Install.reconsider` (#404, added after this
/// gate already existed).
///
/// Every non-`.updateAvailable` outcome used to collapse into one branch and
/// one log line, "already current on disk" — including a source that had been
/// tried and failed, which is not a verdict about the disk at all. See
/// `docs/engine-notes/pre-install-gate.md` §1 for the three endings that used
/// to share that sentence. `UpdateStatus` already draws the line this enum
/// reads (`.unknown` = nothing covers this app, `.error` = tried and failed,
/// retryable).
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
    /// The re-check answered with a version OLDER than what was being offered
    /// when the install was approved, and called the app current on the
    /// strength of it. Nothing was installed and nothing is known to be wrong
    /// with the bundle — the source contradicted itself, one query apart.
    ///
    /// Its own case rather than `alreadyCurrent` because the sentence
    /// `alreadyCurrent` produces ("already current on disk") is a claim about
    /// the disk, and here it is false: the disk still carries the older build
    /// that was being offered.
    ///
    /// The incident that motivated this case — two live queries seconds apart
    /// answering different versions for the same app — is not something this
    /// gate can see the cause of, and the point of this case is that it does
    /// not have to: an answer that walks backwards is not evidence something
    /// was already installed, whatever made it walk backwards. See
    /// `docs/engine-notes/pre-install-gate.md` §2.
    ///
    /// Carries no message: the two version strings live in the `UpdateResult`s
    /// the caller already holds, and the wording belongs where the rest of the
    /// user-facing copy is.
    case answerRegressed
    /// The re-check found no readable bundle at the row's own path at all.
    ///
    /// This can mean three different things, and it cannot say which:
    /// the bundle was uninstalled, its `Info.plist` no longer parses, or the
    /// path now resolves to a bundle with a different identity.
    /// `AppScanner.readApp` returns `nil` for the first two alike and cannot
    /// distinguish them; the third is caught upstream by the id filter in
    /// `AppListModel.recheckMany` / `Install.recheckOne`, which also answers
    /// with nothing rather than with the other app's row.
    ///
    /// Carries no message, unlike `.cannotConfirm`: the CLI's sentence names
    /// the path in plain text, and the App's has to go through
    /// `String(localized:)`, so the wording belongs to each host. What is
    /// shared here is only the classification.
    case unreadable
}

public enum PreInstallGate {

    /// Classify the re-check's outcome.
    ///
    /// `offered` is what was being offered when the install was approved;
    /// `confirmed` is what the re-check just answered. Both are ``VersionSide``
    /// pairs and are compared with
    /// ``VersionComparator/isNewer(_:than:)-(VersionSide,VersionSide)``, so a
    /// vendor that freezes its marketing string is decided on its build and
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
            // back with a LOWER version than what was offered — e.g. the user
            // moved the app off a beta channel in its own settings between the
            // check and the approval, so the stable release it now resolves is
            // older than the beta that was offered and still newer than what is
            // installed. Refusing that would block the install just approved.
            // The `.upToDate` arm below is different: there the source is
            // claiming there is nothing to install at all.
            return .proceed
        case .upToDate:
            // The only reading of `.upToDate` this gate refuses. Every other way
            // to reach it — a manual pkg install, the app's own updater, a build
            // that landed between the check and the approval — leaves `confirmed`
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

    /// Classify the re-check's outcome when the re-check itself may have come
    /// back with nothing.
    ///
    /// This overload exists because "the re-check came back with nothing" is
    /// part of the same decision as everything `decision(for:offered:confirmed:)`
    /// already classifies, and each host used to make that call for itself —
    /// which let the two drift. The CLI grew a `.unreadable` case for it in
    /// #434; the menu bar's `recheck` kept `?? result`, silently falling back to
    /// the stale offer, which cancelled out exactly the identity guard
    /// `recheckMany` stands behind it for (#440). Both hosts now call this
    /// overload instead of branching on their own optional first, so the arm
    /// cannot be handled on one side and forgotten on the other.
    ///
    /// `nil` confirmed classifies as `.unreadable`; otherwise this delegates to
    /// `decision(for:offered:confirmed:)` with both sides' `versionSide`s (or an
    /// empty one when a result carries no remote), exactly as each host already
    /// did at its own call site.
    public static func decision(
        offered: UpdateResult,
        confirmed: UpdateResult?
    ) -> PreInstallDecision {
        guard let confirmed else { return .unreadable }
        return decision(
            for: confirmed.status,
            offered: offered.remote?.versionSide ?? VersionSide(),
            confirmed: confirmed.remote?.versionSide ?? VersionSide())
    }
}
