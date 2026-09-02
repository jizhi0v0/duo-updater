import Foundation

/// The fact a row's version line should explain.
///
/// This is separate from `RowActionState` because the action and the version text
/// do not carry the same payload, but their priorities must tell one story. A row
/// can be both ahead of its feed and waiting for a relaunch: the relaunch is the
/// action, so the line must explain the running → on-disk change rather than show
/// the otherwise-correct, action-less installed ↓ remote note (#210).
public enum RowVersionLineState: Sendable, Equatable {
    /// The app's own updater has the current release staged for a relaunch.
    case stagedRelaunch(StagedSelfUpdate)
    /// A landed update is waiting for the running process to restart.
    case restart(from: VersionSide)
    /// The vendor's advertised release trails what is installed; no action wins.
    case downgrade(to: String)
    /// Render the ordinary line derived from `UpdateStatus`.
    case status
}

public enum RowVersionLine {
    /// Resolve the version line in action priority order.
    ///
    /// `restartFrom` must be supplied only when the caller's restart detector says
    /// the process is stale. `pendingBatchRestartMarketing` is separate because a
    /// batch deliberately defers that detector until all installs finish, while it
    /// already knows the pre-install marketing version.
    public static func state(
        staged: StagedSelfUpdate?,
        pendingBatchRestartMarketing: String?,
        restartFrom: VersionSide?,
        downgradeVersion: String?
    ) -> RowVersionLineState {
        if let staged { return .stagedRelaunch(staged) }
        if let from = pendingBatchRestartMarketing {
            return .restart(from: VersionSide(marketing: from))
        }
        if let restartFrom { return .restart(from: restartFrom) }
        if let downgradeVersion { return .downgrade(to: downgradeVersion) }
        return .status
    }
}
