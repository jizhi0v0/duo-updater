import Foundation

extension InstallJournal {

    /// What a Restore of an interrupted install came to.
    public enum InterruptedRestore: Sendable, Equatable {
        /// Looked at again first, and the app is no longer cut off: it reads
        /// again — the store finished writing it (a `mas` install records no
        /// child to wait for), or something reinstalled it. Nothing restored.
        case noLongerInterrupted
        /// An install of it is running: process `pid`. Nothing restored.
        case stillRunning(pid: Int32)
        /// Another installer holds the install lock, so nothing could be
        /// looked at. Nothing restored.
        case deferred
        /// Still cut off, and nothing to restore from: no backup was kept and
        /// no rollback point was taken. Reinstalling is the way back.
        case noWayBack
        /// Put back from the copy the journal points at; the interrupted
        /// install is cleared (`BackupStore`'s restore clears it).
        case restored(BackupStore.RestoreOutcome)
    }

    /// Restore the app an interrupted install left at `appPath` — the GUI's
    /// Restore, after looking again at what is there now.
    ///
    /// The journal's verdict can be old: it was reached at launch, or when the
    /// install ended, and the app may have changed since. So every finished
    /// install is classified again from the disk (`processLeftovers`), and the
    /// app's standing read, before anything is replaced; only an app still
    /// cut off is restored, from the source read then
    /// (``InterruptedInstall/restoreFrom``), under the install lock, through
    /// `BackupStore.restoreReportingUserData` — what `duo backups restore`
    /// runs for an interrupted install.
    public static func restoreInterrupted(
        at appPath: URL, lock: ProcessInstallLock = .shared
    ) async throws -> InterruptedRestore {
        try await restoreInterrupted(at: appPath, lock: lock, cleanup: .live)
    }

    static func restoreInterrupted(
        at appPath: URL, lock: ProcessInstallLock, cleanup: Cleanup
    ) async throws -> InterruptedRestore {
        // Held from the look to the swap, so another process (`duo backups
        // restore`, `duo install`) cannot change the app in between;
        // `processLeftovers` joins this process's claim.
        do { try await lock.claim() } catch { return .deferred }
        do {
            let result = try await restoreHoldingTheLock(at: appPath, lock: lock, cleanup: cleanup)
            await lock.release()
            return result
        } catch {
            await lock.release()
            throw error
        }
    }

    private static func restoreHoldingTheLock(
        at appPath: URL, lock: ProcessInstallLock, cleanup: Cleanup
    ) async throws -> InterruptedRestore {
        guard await processLeftovers(lock: lock, cleanup: cleanup) != nil else { return .deferred }
        switch standing(of: appPath) {
        case .clear: return .noLongerInterrupted
        case .stillRunning(let pid): return .stillRunning(pid: pid)
        case .interrupted: break
        }
        let wanted = standardized(appPath.path)
        guard let item = interruptedInstalls().first(where: { standardized($0.appPath.path) == wanted })
        else { return .noLongerInterrupted }
        guard let source = item.restoreFrom else { return .noWayBack }
        let outcome = try await BackupStore.restoreReportingUserData(
            forKey: source.key, over: item.appPath, from: source.purpose)
        return .restored(outcome)
    }
}
