import Foundation

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
        preInstallProcessStillRunning: Bool,
        needsRestartAfterRescan: Bool
    ) -> Self {
        if defersBookkeeping, preInstallProcessStillRunning {
            return .awaitingBatchRestart
        }
        return needsRestartAfterRescan ? .awaitingRestart : .complete
    }

    /// Whether a process that was running when the install started is still up
    /// now that the new bundle is on disk — the only process a restart would fix.
    ///
    /// "It was running before" is not the same question. On the App Store route
    /// the store quits a running app to replace its bundle. Whether it reopens it
    /// afterwards depends on the path, and this check does not rely on either:
    ///
    /// - App Store GUI, user clicked Continue in the close-to-update sheet — it
    ///   does. Measured on macOS 26.6, 2026-09-16, in one Update All: Excel and
    ///   Word each logged appstoreagent's `TerminationAssertion: User consented`
    ///   → Quit Apple Event → `Relaunching terminated app after update`, 12.8 s
    ///   after our installer saw the bundle change (both apps). Answering from
    ///   the pre-install flag held both rows on "Relaunch now" until the batch
    ///   ended, over an app already running the new build.
    /// - storedownloadd terminating the app — it did not (DingTalk and, through
    ///   `mas`, LocalSend, 2026-08-22, commits 2eecca24 and 912d79ae;
    ///   `AppStoreQuitPolicy`). LocalSend stayed closed even though the store's
    ///   dialog said it would reopen, so a sheet being shown is not the signal
    ///   either. The reopen there is ours, armed before the install.
    ///
    /// By pid, the process the store quit is gone either way, and one it or we
    /// relaunched was never in the set.
    ///
    /// With no pids to go on (the path-based running check and the bundle-id
    /// query disagreed), falls back to the pre-install flag: that errs towards
    /// a "Relaunch now" the batch's closing rescan clears, not towards "Updated ✓"
    /// over a process that is still on the old code.
    public static func preInstallProcessStillRunning(
        wasRunningBeforeInstall: Bool,
        preInstallPIDs: [pid_t],
        isAlive: (pid_t) -> Bool
    ) -> Bool {
        guard wasRunningBeforeInstall else { return false }
        guard !preInstallPIDs.isEmpty else { return true }
        return preInstallPIDs.contains(where: isAlive)
    }
}
