import Foundation

/// Free space on this Mac while an update is installed.
///
/// An install writes to the boot volume twice before anything is swapped — the
/// downloaded archive and the bundle unpacked from it, both in the temporary
/// directory — and when a rollback point was taken, the old version's blocks
/// stay held by it after the swap instead of being freed. With the app on the
/// outbox's APFS volume the backup is a clone that costs almost nothing until
/// the original is replaced; an app on another volume was copied in full when
/// the backup was taken, and holds nothing extra here afterwards. Several
/// installs run at once (`InstallPermits`), so a check that only looked at
/// free space would let four of them see the same figure and all decide there
/// was room.
///
/// The floor is the backups' one, ``BackupStore/freeSpaceFloorBytes``, and
/// it is read on the outbox's volume only. That is the volume that matters
/// when the temporary directory is on it too — the per-user one under
/// /var/folders and the outbox under the home folder are both on the Data
/// volume of a standard install. A home folder moved to another disk would
/// leave the temporary directory unwatched; nothing here checks for that.
///
/// Three points, in order:
/// 1. **Before anything is fetched** an install reserves what it is expected
///    to use (``SpaceLedger``). With not enough room it waits for the other
///    installs to finish and give theirs back, and is refused only when none
///    is running and there is still not enough.
/// 2. **While downloading** free space is watched (``watching(sparing:_:)``).
///    A fall under the floor deletes this Mac's oldest backups until it is
///    back above; with nothing left to delete the download is stopped.
/// 3. **Right before the swap** the room the swap needs is checked once more
///    (``ensureRoom(for:sparing:)``), with the same deletions if short. A
///    refusal here leaves nothing changed on disk.
///
/// The swap itself is never interrupted: half a bundle in /Applications is
/// worse than a full disk.
public enum DiskSpaceGuard {

    /// An install that did not start, or stopped before its swap, because this
    /// Mac is too low on space.
    public struct InsufficientSpace: LocalizedError, Equatable, Sendable {
        /// Free space the install wanted to find, floor included.
        public let needed: Int64
        public let free: Int64

        public var errorDescription: String? {
            let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            return "Not enough free space on this Mac to install this update: it has "
                + "\(format(free)) free and needs \(format(needed)). Nothing was changed."
        }
    }

    /// Test seam: how long a reservation waits between looks. Production
    /// reads one second.
    @TaskLocal static var reservationRetryOverride: Duration?

    /// What an install of `app` is expected to take from this Mac, at most:
    /// the archive and the unpacked bundle, each counted at the installed
    /// bundle's size, plus that size again when a rollback point for it sits
    /// on this Mac and will hold the old blocks after the swap.
    ///
    /// The installed bundle stands in for the new one because nothing else is
    /// known before the fetch, and the archive is counted at the same size. A
    /// compressed zip or DMG is smaller than what it unpacks to, so that errs
    /// high; an uncompressed or padded image can be larger, and the floor's
    /// margin is what covers it.
    static func estimate(for app: InstalledApp) async -> (total: Int64, toApply: Int64) {
        let path = app.path
        let size = await offCooperativePool(qos: .userInitiated) {
            BackupStore.logicalSize(of: path)
        }
        let key = BackupStore.key(bundleID: app.bundleID, path: app.path)
        let retained = BackupStore.backup(forKey: key)?.store.location == .outbox ? size : 0
        return (2 * size + retained, size + retained)
    }

    /// The installs of this process and the bytes each has claimed.
    ///
    /// Per process, like `InstallPermits`: the app and `duo` each keep their
    /// own, and ``InstallLock`` is what keeps them from installing at once.
    public final class SpaceLedger: @unchecked Sendable {
        public static let shared = SpaceLedger()

        private let lock = NSLock()
        private var reserved: Int64 = 0

        public init() {}

        var reservedBytes: Int64 { lock.withLock { reserved } }

        private enum Decision { case granted, wait, refuse }

        /// Claim `bytes`, waiting while other installs hold enough to make the
        /// difference. Throws ``InsufficientSpace`` when nobody else holds any
        /// and there is still not room, and `CancellationError` if cancelled
        /// while waiting.
        ///
        /// While another install is running, its bytes are counted twice — once
        /// as its claim and once as the space it has already written — so the
        /// answer errs towards waiting. Waiting is cheap; it ends when that
        /// install does.
        func reserve(_ bytes: Int64) async throws {
            let retry = DiskSpaceGuard.reservationRetryOverride ?? .seconds(1)
            var waited = false
            while true {
                try Task.checkCancellation()
                guard let free = BackupStore.outboxFreeBytes() else {
                    lock.withLock { reserved += bytes }
                    return
                }
                let needed = BackupStore.freeSpaceFloorBytes + bytes
                let decision: Decision = lock.withLock {
                    if free - reserved >= needed {
                        reserved += bytes
                        return .granted
                    }
                    return reserved > 0 ? .wait : .refuse
                }
                switch decision {
                case .granted:
                    if waited { Log.install.notice("disk space: room for \(bytes, privacy: .public) bytes now — install continues") }
                    return
                case .refuse:
                    Log.install.error("disk space: install refused — \(free, privacy: .public) bytes free, needs \(needed, privacy: .public)")
                    throw InsufficientSpace(needed: needed, free: free)
                case .wait:
                    if !waited {
                        Log.install.notice("disk space: waiting for other installs — \(free, privacy: .public) bytes free, \(bytes, privacy: .public) wanted")
                        waited = true
                    }
                    try await Task.sleep(for: retry)
                }
            }
        }

        func release(_ bytes: Int64) {
            lock.withLock { reserved = max(0, reserved - bytes) }
        }
    }

    /// `body`, with free space watched while it runs: every half second, and a
    /// fall under the floor answered by deleting this Mac's oldest backups
    /// (never `key`'s, the rollback point of the app being installed). When
    /// there is nothing left to delete, `body` is cancelled and
    /// ``InsufficientSpace`` thrown in place of whatever its cancellation threw.
    ///
    /// `body` runs in a task of its own so the watcher can cancel it alone; a
    /// cancellation of the caller is passed on to it. Two unstructured tasks
    /// rather than a task group — see the Swift 6.4 release-build miscompile
    /// around `for await` over a group.
    static func watching<T: Sendable>(
        sparing key: String, _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let work = Task { try await body() }
        let ranOut = Flag()
        let interval = BackupStore.spaceWatchIntervalOverride ?? .milliseconds(500)
        let watcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                if await !BackupStore.reclaimFreeSpace(sparing: key) {
                    ranOut.set()
                    work.cancel()
                    return
                }
            }
        }
        let result = await withTaskCancellationHandler {
            await work.result
        } onCancel: {
            work.cancel()
        }
        watcher.cancel()
        await watcher.value
        if ranOut.isSet, case .failure = result {
            Log.install.error("disk space: stopped an install mid-download — under the floor with no backup left to delete")
            throw InsufficientSpace(
                needed: BackupStore.freeSpaceFloorBytes, free: BackupStore.outboxFreeBytes() ?? 0)
        }
        return try result.get()
    }

    /// Make sure `bytes` can be written without crossing the floor, deleting
    /// this Mac's oldest backups (never `key`'s) if that is what it takes.
    /// Throws ``InsufficientSpace`` when it cannot be done.
    static func ensureRoom(for bytes: Int64, sparing key: String) async throws {
        let target = BackupStore.freeSpaceFloorBytes + bytes
        if await BackupStore.reclaimFreeSpace(sparing: key, target: target) { return }
        let free = BackupStore.outboxFreeBytes() ?? 0
        Log.install.error("disk space: install stopped before its swap — \(free, privacy: .public) bytes free, needs \(target, privacy: .public)")
        throw InsufficientSpace(needed: target, free: free)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
}
