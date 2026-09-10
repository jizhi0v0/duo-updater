import Foundation

/// Shared classification after callers re-read the bundle and re-query its source.
/// `AppListModel.performInstall` and CLI `Install.reconsider` use this gate.
/// See `docs/engine-notes/pre-install-gate.md` §1 for history and
/// `PreInstallGateTests` / CLI `InstallTests` for coverage.
public enum PreInstallDecision: Sendable, Equatable {
    /// A newer version was confirmed just now. Install it.
    case proceed
    /// The bundle on disk is already current. Nothing to do, and not a failure.
    case alreadyCurrent
    /// Something else owns this app's updates. Nothing to do, and not a failure.
    case managedElsewhere
    /// The source failed (its message) or no source covers the app (nil).
    /// Failure to confirm is not evidence that the disk is current.
    case cannotConfirm(String?)
    /// The source claims up-to-date with a version older than the approved offer.
    /// This contradicts the offer, not the disk state. Callers own the wording
    /// and retain both results for reporting the versions.
    /// See `docs/engine-notes/pre-install-gate.md` §2 for the motivating incident.
    case answerRegressed
    /// No readable bundle with the expected identity at the row's path.
    /// Absence, unreadable Info.plist, and identity mismatch are indistinguishable
    /// here; callers filter identity before this gate and own the user-facing copy.
    case unreadable
}

public enum PreInstallGate {

    /// Compare the approved offer with the re-check using `VersionSide` pairs:
    /// build-only changes remain comparable without crossing version namespaces.
    /// Pass an empty side for a missing remote; incomparable sides do not regress.
    /// Only `.upToDate` can produce `.answerRegressed`.
    public static func decision(
        for status: UpdateStatus,
        offered: VersionSide,
        confirmed: VersionSide
    ) -> PreInstallDecision {
        switch status {
        case .updateAvailable:
            // A channel change can lower the offer while still updating the disk.
            return .proceed
        case .upToDate:
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

    /// A missing re-check result is `.unreadable`; never fall back to the stale
    /// offer. Otherwise classify its status and the two remote version sides.
    /// See `docs/engine-notes/pre-install-gate.md` §3 for the shared nil handling.
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
