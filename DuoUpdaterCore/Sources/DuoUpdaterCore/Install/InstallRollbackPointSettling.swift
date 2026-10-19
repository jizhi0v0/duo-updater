import Foundation

/// When an install rollback point stops being needed.
///
/// It is taken for one case: the install is cut off after a third party has
/// deleted the app and before it has moved the new one in. Every other ending
/// leaves the app readable — updated, untouched, or updated by something else
/// later — and then the point is a hidden full-size copy no surface sizes,
/// lists or reclaims. So the rule is the same at every normal end of an
/// attempt and at launch: app readable ⇒ discard; app missing or unreadable ⇒
/// keep, because that is the case it was taken for — unless the install never
/// reached its commit point, when something else removed the app. A process that DIES keeps
/// it by not running any of this; the next launch's sweep then decides.
extension InstallCoordinator {

    /// What ``settleInstallRollbackPoint(for:)`` did.
    public enum RollbackPointSettlement: Sendable, Equatable {
        /// There was none for this app.
        case none
        /// The app reads, so the point was no longer the way back to anything.
        case discarded
        /// The app is missing or unreadable: kept for the user to restore.
        case kept
    }

    /// Settle `app`'s install rollback point at the end of an install attempt
    /// — success, failure, skip or refusal alike. Hosts call it from a `defer`
    /// so no exit path can miss it. Also lets go of the claim
    /// ``takeInstallRollbackPoint(_:route:)`` took, which is what lets the
    /// launch sweep see this key again.
    ///
    /// - Parameters:
    ///   - journal: this attempt's journal recording, nil when there is none.
    ///     Whether the attempt reached its commit point is read from it.
    ///   - succeeded: the host's own word that the install landed (the
    ///     coordinator returned `applied`). An app missing from its old path
    ///     after a success was moved by the install (a cask renamed in its new
    ///     version), not lost, and the point is no one's way back — unless an
    ///     earlier install of it is on record, whose way back it may be.
    @discardableResult
    public static func settleInstallRollbackPoint(
        for app: InstalledApp, journal: InstallJournal.Recording?, succeeded: Bool
    ) async -> RollbackPointSettlement {
        let key = BackupStore.key(bundleID: app.bundleID, path: app.path)
        let outcome: RollbackPointSettlement
        if BackupStore.rollbackPoint(forKey: key) == nil {
            outcome = .none
        } else if BackupStore.hasReadableBundle(at: app.path),
                  await InstallJournal.mayDiscardRollbackPoint(for: app.path) {
            await BackupStore.removeRollbackPoint(forKey: key)
            outcome = .discarded
        } else if BackupStore.hasReadableBundle(at: app.path) {
            // Readable, but over an earlier install that was cut off and not
            // verifiably repaired by this one: the point is still that
            // install's way back (`InstallJournal.mayDiscardRollbackPoint`).
            Log.install.notice(
                "rollback point: kept for \(app.path.lastPathComponent, privacy: .public) — an earlier install of it was cut off and this one did not leave it verifiably good")
            outcome = .kept
        } else if succeeded, !InstallJournal.hasEarlierInstall(of: app.path, excluding: journal) {
            await BackupStore.removeRollbackPoint(forKey: key)
            Log.install.notice(
                "rollback point: discarded for \(app.path.lastPathComponent, privacy: .public) — the install succeeded and left nothing at the old path (it moved the app)")
            outcome = .discarded
        } else if InstallJournal.ownInstallIsBeforeItsCommit(journal, for: app.path) {
            // Gone, but not by this install, which stopped before its commit
            // point — the user trashed it while the point was being taken. The
            // journal drops this install's file (`Recording.finish`), and a
            // point kept now would be listed nowhere and never swept: the sweep
            // keeps every point whose app does not read.
            await BackupStore.removeRollbackPoint(forKey: key)
            Log.install.notice(
                "rollback point: discarded for \(app.path.lastPathComponent, privacy: .public) — the app went missing before the install reached its commit point")
            outcome = .discarded
        } else {
            // Brew can fail after removing the app and not put it back — a
            // signal skips its revert, and the revert can fail itself — and
            // this copy is then the only way back.
            Log.install.notice(
                "rollback point: kept for \(app.path.lastPathComponent, privacy: .public) — the app is missing or unreadable after the install")
            outcome = .kept
        }
        await InstallRollbackPointClaims.shared.endTaking(key)
        return outcome
    }

    /// Discard every install rollback point whose app reads again: one left by
    /// an install whose process died, once the app is back, and one whose app
    /// was later updated some other way. Run at launch (the app) and at the
    /// start of `duo install`.
    ///
    /// Takes the machine-wide install lock, non-blocking, like
    /// `InPlaceSwap.recoverInterruptedSwaps`: another process mid-install may
    /// have just taken a point for an app that is still intact. Returns nil
    /// when that lock was busy — nothing was swept, and the caller should try
    /// again later. Inside this process the lock is shared, so keys an install
    /// here is holding (``InstallRollbackPointClaims``) are skipped.
    @discardableResult
    public static func sweepSettledInstallRollbackPoints(
        lock: ProcessInstallLock = .shared
    ) async -> Int? {
        do {
            try await lock.claim()
        } catch {
            Log.install.notice(
                "rollback points: another installer holds the install lock, sweep deferred")
            return nil
        }
        var discarded = 0
        // An app with an install journal file is one whose install is running,
        // was cut off and not yet looked at, or was found cut off — readable
        // or not (a broken signature reads). Its point is that app's way back.
        let journaled = InstallJournal.journaledAppPaths()
        for (key, appPath) in BackupStore.rollbackPointOrigins() {
            guard !journaled.contains(InstallJournal.standardized(appPath.path)) else { continue }
            guard await InstallRollbackPointClaims.shared.beginSweeping(key) else { continue }
            if BackupStore.hasReadableBundle(at: appPath) {
                await BackupStore.removeRollbackPoint(forKey: key)
                discarded += 1
            }
            await InstallRollbackPointClaims.shared.endSweeping(key)
        }
        await lock.release()
        if discarded > 0 {
            Log.install.notice(
                "rollback points: discarded \(discarded, privacy: .public) whose app reads again")
        }
        return discarded
    }
}

/// Keys whose rollback point an install in this process is holding, and keys
/// the sweep is deciding right now — so neither removes what the other is
/// about to rely on. The install lock cannot say this: it is shared by every
/// install in one process.
actor InstallRollbackPointClaims {
    static let shared = InstallRollbackPointClaims()

    /// The same claims for an install's pending backup
    /// (`InstallCoordinator.backUp` → `settlePendingBackup`) against
    /// `sweepPendingBackups`.
    static let pendingBackups = InstallRollbackPointClaims()

    private var taking: [String: Int] = [:]
    private var sweeping: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// Mark `key` held by an install. Waits out a sweep deciding that key, so
    /// the point the install is about to write cannot be removed under it.
    func beginTaking(_ key: String) async {
        while sweeping.contains(key) {
            await withCheckedContinuation { waiting[key, default: []].append($0) }
        }
        taking[key, default: 0] += 1
    }

    func endTaking(_ key: String) {
        guard let count = taking[key] else { return }
        taking[key] = count > 1 ? count - 1 : nil
    }

    /// Claim `key` for the sweep, or false when an install holds it.
    func beginSweeping(_ key: String) -> Bool {
        guard taking[key] == nil else { return false }
        sweeping.insert(key)
        return true
    }

    func endSweeping(_ key: String) {
        sweeping.remove(key)
        for waiter in waiting.removeValue(forKey: key) ?? [] { waiter.resume() }
    }
}
