import Foundation

/// When an install's backup becomes the user's backup.
///
/// `backUp` copies the app into the pending slot (`BackupStore.pendingBackupsRoot`)
/// rather than over the backup the user already has, because one slot per app
/// meant a cancelled or failed install had already replaced the way back to the
/// version before. The copy takes that slot once the app is no longer the
/// bundle it was copied from (`BackupStore.settlePending`): asked at the end of
/// every install attempt and Relaunch, and at launch for a process that died
/// before it could ask.
extension InstallCoordinator {

    /// Settle `app`'s pending backup at the end of an install attempt or a
    /// Relaunch — success, failure, skip, refusal or cancel alike. Hosts call it
    /// from the `defer` they settle the install rollback point from, so no exit
    /// path can miss it. Also lets go of the claim `backUp` took, which is what
    /// lets the launch sweep see this key again.
    ///
    /// - Parameter succeeded: the host's own word that the install landed (the
    ///   coordinator returned `applied`); see `BackupStore.settlePending`.
    @discardableResult
    public static func settlePendingBackup(
        for app: InstalledApp, succeeded: Bool
    ) async -> BackupStore.PendingSettlement {
        let key = BackupStore.key(bundleID: app.bundleID, path: app.path)
        let outcome = await BackupStore.settlePending(forKey: key, succeeded: succeeded)
        if outcome == .kept {
            Log.install.notice(
                "backup: \(app.path.lastPathComponent, privacy: .public)'s copy stays pending — the app is still the bundle it was copied from, so the earlier backup stays the way back")
        }
        await InstallRollbackPointClaims.pendingBackups.endTaking(key)
        return outcome
    }

    /// Settle every pending backup no install is holding: the copy of an app
    /// that changed since — an install whose process died after its swap, an
    /// app that updated itself, one that was removed — becomes that app's
    /// backup; one whose app is unchanged stays, for a retry to reuse. Run at
    /// launch (the app) and at the start of `duo install`, `duo restart` and
    /// `duo backups restore`. Returns how many were promoted.
    ///
    /// Takes the machine-wide install lock, non-blocking, like
    /// ``sweepSettledInstallRollbackPoints(lock:)``: another process may be
    /// mid-install with a pending copy of its own. Returns nil when that lock
    /// was busy. Inside this process the lock is shared, so keys an install
    /// here is holding are skipped, and so is an app whose orphaned installer
    /// still runs (`InstallJournal.standing`): the app is that installer's
    /// until it exits.
    @discardableResult
    public static func sweepPendingBackups(lock: ProcessInstallLock = .shared) async -> Int? {
        do {
            try await lock.claim()
        } catch {
            Log.install.notice(
                "pending backups: another installer holds the install lock, sweep deferred")
            return nil
        }
        var promoted = 0
        for (key, appPath) in BackupStore.pendingOrigins() {
            if case .stillRunning = InstallJournal.standing(of: appPath) { continue }
            guard await InstallRollbackPointClaims.pendingBackups.beginSweeping(key) else { continue }
            if await BackupStore.settlePending(forKey: key, succeeded: false) == .promoted {
                promoted += 1
            }
            await InstallRollbackPointClaims.pendingBackups.endSweeping(key)
        }
        await lock.release()
        if promoted > 0 {
            Log.install.notice(
                "pending backups: \(promoted, privacy: .public) became their app's backup — the app changed since it was copied")
        }
        return promoted
    }
}
