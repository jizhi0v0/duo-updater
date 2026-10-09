import Testing
import Foundation
@testable import DuoUpdaterCore

/// The install side of the free-space floor: a claim before anything is
/// fetched, a watch while downloading, a last check before the swap.
///
/// Free space is never read from the real disk: `BackupStore.freeBytesOverride`
/// stands in for the volume, and the outbox is a scratch directory.
@Suite(.serialized)
struct DiskSpaceGuardTests {

    private let gib: Int64 = 1 << 30
    private var floor: Int64 { BackupStore.freeSpaceFloorBytes }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64
        init(_ value: Int64) { self.value = value }
        func get() -> Int64 { lock.withLock { value } }
        func set(_ new: Int64) { lock.withLock { value = new } }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }

    private func withScratch(_ body: (URL, URL) async throws -> Void) async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdaterDiskGuard-\(UUID().uuidString)")
        let root = scratch.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await BackupStore.$rootOverride.withValue(root) {
            try await BackupStore.$destinationOverride.withValue(.local) {
                try await BackupFactsLibrary.$rootOverride.withValue(
                    scratch.appendingPathComponent("Facts")) {
                    try await body(scratch, root)
                }
            }
        }
    }

    private func makeApp(_ name: String, in dir: URL, bytes: Int = 0) throws -> URL {
        let app = dir.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>com.example.\(name.lowercased())</string>
          <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        try plist.data(using: .utf8)!.write(to: contents.appendingPathComponent("Info.plist"))
        if bytes > 0 {
            try Data(repeating: 1, count: bytes).write(to: contents.appendingPathComponent("payload"))
        }
        return app
    }

    /// A stored backup for `name`, `age` seconds old.
    @discardableResult
    private func storeBackup(_ name: String, in scratch: URL, root: URL, age: TimeInterval) async throws -> String {
        let app = try makeApp(name, in: scratch)
        let id = "com.example.\(name.lowercased())"
        let key = BackupStore.key(bundleID: id, path: app)
        _ = try await BackupStore.save(appPath: app, key: key, version: "1.0", bundleID: id)
        let sidecar = root.appendingPathComponent(key).appendingPathComponent("backup.json")
        var json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any])
        json["savedAt"] = Date().addingTimeInterval(-age).timeIntervalSinceReferenceDate
        try JSONSerialization.data(withJSONObject: json).write(to: sidecar)
        return key
    }

    private func keys(in root: URL) -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { !$0.hasPrefix(".") })
    }

    // MARK: - Ledger

    @Test func aClaimIsGrantedWhenItFitsAboveTheFloor() async throws {
        let ledger = DiskSpaceGuard.SpaceLedger()
        let free = floor + 5 * gib
        try await BackupStore.$freeBytesOverride.withValue({ free }) {
            try await ledger.reserve(4 * gib)
        }
        #expect(ledger.reservedBytes == 4 * gib)
    }

    /// Time-limited: a claim that waits instead of refusing never returns.
    @Test(.timeLimit(.minutes(1)))
    func aClaimWithNobodyElseHoldingAnyIsRefusedAtOnce() async throws {
        let ledger = DiskSpaceGuard.SpaceLedger()
        let free = floor + gib
        await #expect(throws: DiskSpaceGuard.InsufficientSpace.self) {
            try await BackupStore.$freeBytesOverride.withValue({ free }) {
                try await ledger.reserve(2 * gib)
            }
        }
        #expect(ledger.reservedBytes == 0)
    }

    /// Two installs that do not both fit: the second waits for the first to
    /// give its claim back, then goes ahead, rather than being refused.
    @Test func aClaimThatDoesNotFitBesideAnotherWaitsForIt() async throws {
        let ledger = DiskSpaceGuard.SpaceLedger()
        let free = floor + 5 * gib
        try await BackupStore.$freeBytesOverride.withValue({ free }) {
            try await DiskSpaceGuard.$reservationRetryOverride.withValue(.milliseconds(5)) {
                try await ledger.reserve(4 * gib)
                let second = Task { try await ledger.reserve(4 * gib) }
                try await Task.sleep(for: .milliseconds(100))
                #expect(ledger.reservedBytes == 4 * gib)   // still waiting
                ledger.release(4 * gib)
                try await second.value
                #expect(ledger.reservedBytes == 4 * gib)   // the second's claim
            }
        }
    }

    @Test func aWaitingClaimStopsWhenCancelled() async throws {
        let ledger = DiskSpaceGuard.SpaceLedger()
        let free = floor + 5 * gib
        try await BackupStore.$freeBytesOverride.withValue({ free }) {
            try await DiskSpaceGuard.$reservationRetryOverride.withValue(.milliseconds(5)) {
                try await ledger.reserve(4 * gib)
                let second = Task { try await ledger.reserve(4 * gib) }
                try await Task.sleep(for: .milliseconds(50))
                second.cancel()
                await #expect(throws: CancellationError.self) { try await second.value }
                #expect(ledger.reservedBytes == 4 * gib)
            }
        }
    }

    // MARK: - Watching a download

    @Test func aDownloadThatStaysAboveTheFloorIsLeftAlone() async throws {
        try await withScratch { _, _ in
            let free = floor + gib
            let value = try await BackupStore.$spaceWatchIntervalOverride.withValue(.milliseconds(1)) {
                try await BackupStore.$freeBytesOverride.withValue({ free }) {
                    try await DiskSpaceGuard.watching(sparing: "nobody") {
                        try await Task.sleep(for: .milliseconds(50))
                        return 42
                    }
                }
            }
            #expect(value == 42)
        }
    }

    /// Under the floor with only the installing app's own backup in the store:
    /// that one is kept, the download is cancelled, and the error says space.
    @Test func aDownloadUnderTheFloorWithNothingToDeleteIsStopped() async throws {
        try await withScratch { scratch, root in
            let own = try await storeBackup("Own", in: scratch, root: root, age: 100)
            let free = floor - gib
            let sawCancel = Counter()
            await #expect(throws: DiskSpaceGuard.InsufficientSpace.self) {
                try await BackupStore.$spaceWatchIntervalOverride.withValue(.milliseconds(1)) {
                    try await BackupStore.$freeBytesOverride.withValue({ free }) {
                        try await DiskSpaceGuard.watching(sparing: own) {
                            do {
                                try await Task.sleep(for: .seconds(30))
                            } catch {
                                sawCancel.bump()
                                throw error
                            }
                        }
                    }
                }
            }
            #expect(sawCancel.value == 1)
            #expect(keys(in: root).contains(own))
        }
    }

    /// Under the floor with an older backup to give up: it goes, the download
    /// is not interrupted.
    @Test func aDownloadUnderTheFloorDeletesAnOlderBackupAndCarriesOn() async throws {
        try await withScratch { scratch, root in
            let own = try await storeBackup("Own", in: scratch, root: root, age: 100)
            let older = try await storeBackup("Older", in: scratch, root: root, age: 9000)
            let free = Box(floor - gib)
            let value = try await BackupStore.$spaceWatchIntervalOverride.withValue(.milliseconds(1)) {
                try await BackupStore.$freeBytesOverride.withValue({
                    // Deleting `older` gives back two GB.
                    FileManager.default.fileExists(atPath: root.appendingPathComponent(older).path)
                        ? free.get() : free.get() + 2 * (1 << 30)
                }) {
                    try await DiskSpaceGuard.watching(sparing: own) {
                        try await Task.sleep(for: .milliseconds(100))
                        return "done"
                    }
                }
            }
            #expect(value == "done")
            #expect(!keys(in: root).contains(older))
            #expect(keys(in: root).contains(own))
        }
    }

    @Test func cancellingTheInstallCancelsTheDownload() async throws {
        let free = floor + gib
        let sawCancel = Counter()
        let task = Task {
            try await BackupStore.$freeBytesOverride.withValue({ free }) {
                try await DiskSpaceGuard.watching(sparing: "nobody") {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        sawCancel.bump()
                        throw error
                    }
                }
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(sawCancel.value == 1)
    }

    // MARK: - Before the swap

    @Test func roomForTheSwapIsMadeByDeletingOlderBackups() async throws {
        try await withScratch { scratch, root in
            let own = try await storeBackup("Own", in: scratch, root: root, age: 100)
            let older = try await storeBackup("Older", in: scratch, root: root, age: 9000)
            let base = floor
            try await BackupStore.$freeBytesOverride.withValue({
                FileManager.default.fileExists(atPath: root.appendingPathComponent(older).path)
                    ? base : base + 3 * (1 << 30)
            }) {
                try await DiskSpaceGuard.ensureRoom(for: 2 * gib, sparing: own)
            }
            #expect(!keys(in: root).contains(older))
            #expect(keys(in: root).contains(own))
        }
    }

    /// End to end through `fetchThenSwap`: the swap does not fit and nothing
    /// can be deleted, so `apply` never runs and the scratch directory goes.
    @Test func aSwapThatDoesNotFitNeverStarts() async throws {
        try await withScratch { scratch, _ in
            let workDir = scratch.appendingPathComponent("work")
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let archive = workDir.appendingPathComponent("A.zip")
            try Data("zz".utf8).write(to: archive)
            let applied = Counter()
            let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
            let free = floor + gib
            await #expect(throws: DiskSpaceGuard.InsufficientSpace.self) {
                try await BackupStore.$freeBytesOverride.withValue({ free }) {
                    _ = try await coordinator.fetchThenSwap(
                        Self.result(in: scratch), spaceToApply: 2 * gib,
                        progress: { _ in }, releaseAfterDownload: {},
                        download: { _, _ in
                            DownloadedUpdate(archiveURL: archive, bytesDownloaded: 2, workDir: workDir)
                        },
                        apply: { _, _, _ in applied.bump() })
                }
            }
            #expect(applied.value == 0)
            #expect(!FileManager.default.fileExists(atPath: workDir.path))
        }
    }

    /// End to end through `fetchThenSwap`: the disk falls under the floor
    /// mid-download with nothing to delete, so the download is stopped and
    /// `apply` never runs.
    @Test func aDownloadThatRunsTheDiskDownIsStoppedBeforeTheSwap() async throws {
        try await withScratch { scratch, _ in
            let applied = Counter()
            let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
            let free = floor - gib
            await #expect(throws: DiskSpaceGuard.InsufficientSpace.self) {
                try await BackupStore.$spaceWatchIntervalOverride.withValue(.milliseconds(1)) {
                    try await BackupStore.$freeBytesOverride.withValue({ free }) {
                        _ = try await coordinator.fetchThenSwap(
                            Self.result(in: scratch), spaceToApply: gib,
                            progress: { _ in }, releaseAfterDownload: {},
                            download: { _, _ in
                                try await Task.sleep(for: .seconds(30))
                                throw CancellationError()
                            },
                            apply: { _, _, _ in applied.bump() })
                    }
                }
            }
            #expect(applied.value == 0)
        }
    }

    // MARK: - Estimate

    @Test func theEstimateCountsTheOldVersionWhenABackupHoldsIt() async throws {
        try await withScratch { scratch, _ in
            let app = try makeApp("Sized", in: scratch, bytes: 1000)
            let installed = InstalledApp(
                name: "Sized", bundleID: "com.example.sized", shortVersion: "1.0",
                buildVersion: "1", path: app, isMASApp: false, sparkleFeedURL: nil)
            let size = BackupStore.logicalSize(of: app)
            let before = await DiskSpaceGuard.estimate(for: installed)
            #expect(before.total == 2 * size)
            #expect(before.toApply == size)
            let key = BackupStore.key(bundleID: "com.example.sized", path: app)
            _ = try await BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: "com.example.sized")
            let after = await DiskSpaceGuard.estimate(for: installed)
            #expect(after.total == 3 * size)
            #expect(after.toApply == 2 * size)
        }
    }

    private static func result(in dir: URL) -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "ZZFixture", bundleID: "com.example.zzfixture",
                shortVersion: "1.0", buildVersion: "1",
                path: dir.appendingPathComponent("ZZFixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Sparkle"),
            status: .updateAvailable(latest: "1.1"))
    }
}
