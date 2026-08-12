/// The user-visible state after an installer has put the new bundle on disk.
///
/// Update All deliberately postpones its process-version scan until every install
/// finishes. During that window `needsRestart` is stale by design, so a running app
/// must be classified from the pre-install running snapshot instead of being called
/// complete and briefly showing “Updated ✓”.
public enum PostInstallDisposition: Sendable, Equatable {
    case awaitingBatchRestart
    case awaitingRestart
    case complete

    public static func resolve(
        defersBookkeeping: Bool,
        wasRunningBeforeInstall: Bool,
        needsRestartAfterRescan: Bool
    ) -> Self {
        if defersBookkeeping, wasRunningBeforeInstall {
            return .awaitingBatchRestart
        }
        return needsRestartAfterRescan ? .awaitingRestart : .complete
    }
}
