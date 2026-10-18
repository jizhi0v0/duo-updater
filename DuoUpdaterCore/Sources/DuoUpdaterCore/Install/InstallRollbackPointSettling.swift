import Foundation

/// When an install rollback point stops being needed.
///
/// It is taken for one case: the install is cut off after a third party has
/// deleted the app and before it has moved the new one in. Every other ending
/// leaves the app readable — updated, untouched, or updated by something else
/// later — and then the point is a hidden full-size copy no surface sizes,
/// lists or reclaims. So the rule is the same at every normal end of an
/// attempt and at launch: app readable ⇒ discard; app missing or unreadable ⇒
/// keep, because that is the case it was taken for. A process that DIES keeps
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
    @discardableResult
    public static func settleInstallRollbackPoint(
        for app: InstalledApp
    ) async -> RollbackPointSettlement {
        let key = BackupStore.key(bundleID: app.bundleID, path: app.path)
        let outcome: RollbackPointSettlement
        if BackupStore.rollbackPoint(forKey: key) == nil {
            outcome = .none
        } else if BackupStore.hasReadableBundle(at: app.path) {
            await BackupStore.removeRollbackPoint(forKey: key)
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
        for (key, appPath) in BackupStore.rollbackPointOrigins() {
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
