import Foundation
import Testing
@testable import DuoUpdaterCore

/// A cancel before the commit point is an outcome of its own,
/// `InstallAttemptOutcome.cancelled(at:)`: not a failure, not an updated app,
/// and named by the stage it stopped at (plans/update-cancellation.md §5.8).
/// What the hosts build it from is here: the stage tracker their progress
/// callbacks go through, the batch summary "Update All" counts with, and the
/// backup that a cancel now stops midway (§2.3 D2).
///
/// Serialized like `BackupStoreSpaceTests`: each backup test binds its own
/// scratch root, but the space seams are read by code shared across them.
@Suite(.serialized) struct CancelledInstallOutcomeTests {

    // MARK: - The outcome and the summary

    /// Mutation: `countsAsUpdatedApp` as `self != .notInstalled && self !=
    /// .handedOffToSystemInstaller` → red.
    @Test func aCancelledAttemptIsNotAnUpdatedApp() {
        #expect(!InstallAttemptOutcome.cancelled(at: .downloading(fraction: 0.4)).countsAsUpdatedApp)
        #expect(!InstallAttemptOutcome.cancelled(at: .backingUp).countsAsUpdatedApp)
        #expect(InstallAttemptOutcome.installed.countsAsUpdatedApp)
    }

    /// Mixed outcomes: only `.installed` is updated, only `.cancelled` is
    /// cancelled; a failure and a hand-off are in neither.
    /// Mutation: drop the `cancelled += 1` in `record` → red.
    @Test func theBatchSummaryCountsUpdatedAndCancelledApart() {
        var summary = InstallBatchSummary()
        for outcome: InstallAttemptOutcome in [
            .installed, .cancelled(at: .downloading(fraction: 0.2)), .notInstalled,
            .handedOffToSystemInstaller, .cancelled(at: .queued), .installed,
        ] {
            summary.record(outcome)
        }
        #expect(summary.updated == 2)
        #expect(summary.cancelled == 2)
        #expect(summary.attempted == 6)
        // The targets a cancelled batch never reached are cancelled too.
        summary.recordCancelledBeforeStart(3)
        #expect(summary.cancelled == 5)
        #expect(summary.updated == 2)
    }

    @Test func theStageNameDropsThePayload() {
        #expect(InstallStage.downloading(fraction: 0.37).name == "downloading")
        #expect(InstallStage.runningCommand("==> Downloading").name == "runningCommand")
        #expect(InstallStage.backingUp.name == "backingUp")
    }

    // MARK: - Where a cancel stopped it

    /// Cancelled while downloading: the coordinator's own fetch-then-swap
    /// reports `.downloading` through the tracker the hosts wrap their progress
    /// in, the cancel surfaces as `CancellationError`, and the outcome names the
    /// download. Mutation: drop `enter(stage)` from `recording` → the tracker
    /// still says `.checking`, red.
    @Test func aCancelDuringTheDownloadIsCancelledAtTheDownload() async throws {
        let workDir = try Self.workDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let stages = InstallStageTracker(.checking)
        let forwarded = Box<[String]>([])
        let result = Self.result()
        let task = Task {
            try await InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
                .fetchThenSwap(
                    result, spaceToApply: 0,
                    progress: stages.recording { stage in forwarded.mutate { $0.append(stage.name) } },
                    releaseAfterDownload: {},
                    download: { _, progress in
                        progress(.downloading(fraction: 0.5))
                        withUnsafeCurrentTask { $0?.cancel() }
                        return DownloadedUpdate(
                            archiveURL: workDir.appendingPathComponent("ZZFixture.zip"),
                            bytesDownloaded: 1, workDir: workDir)
                    },
                    apply: { _, _, _ in Issue.record("applied after a cancel") })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        let outcome = InstallAttemptOutcome.cancelled(result.app, at: stages.stage)
        guard case .cancelled(at: .downloading) = outcome else {
            Issue.record("expected cancelled at downloading, got \(outcome)")
            return
        }
        #expect(!outcome.countsAsUpdatedApp)
        // Still forwarded to the host's own callback.
        #expect(forwarded.value.contains("downloading"))
    }

    // MARK: - The backup (D2)

    /// Cancelled while `ditto` copies: the copy is stopped, its staging is
    /// gone, nothing is listed, and the coordinator says `.cancelled` — which
    /// the hosts turn into `.cancelled(at: .backingUp)`.
    /// Mutations: await the copy without forwarding the cancel
    /// (`runDittoWatchingSpace`) → the copy lands and is listed, red; drop the
    /// `!ditto.ok, Task.isCancelled` branch in `write` → `.failed`, red; drop
    /// `catch is CancellationError` in `backUp` → `.failed`, red.
    @Test func aCancelDuringTheBackupKeepsNothingAndSaysCancelled() async throws {
        try await Self.withScratch { scratch, root in
            let app = try Self.makeApp(in: scratch, files: 3000)
            let installed = Self.installed(app)
            let key = BackupStore.key(bundleID: installed.bundleID, path: app)
            let stages = InstallStageTracker(.checking)
            stages.enter(.backingUp)
            let cut = CancelOnFirstWatch()
            let outcome = await cut.run {
                await InstallCoordinator.backUp(installed, route: .sparkle)
            }
            try #require(cut.fired, "the copy finished before the watcher's first tick — nothing was cancelled mid-copy")
            #expect(outcome == .cancelled)
            #expect(BackupStore.backup(forKey: key) == nil)
            #expect(BackupStore.allBackups().isEmpty)
            #expect(Self.entries(root).isEmpty, "left behind: \(Self.entries(root))")
            let attempt = InstallAttemptOutcome.cancelled(installed, at: stages.stage)
            #expect(attempt == .cancelled(at: .backingUp))
        }
    }

    /// The backup a cancelled copy would have replaced is untouched: the
    /// staging is separate, and the swap into the slot never ran.
    @Test func aCancelledBackupLeavesTheEarlierOneInPlace() async throws {
        try await Self.withScratch { scratch, root in
            let app = try Self.makeApp(in: scratch, files: 3000)
            let installed = Self.installed(app)
            let key = BackupStore.key(bundleID: installed.bundleID, path: app)
            let earlier = try await BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: installed.bundleID)
            let cut = CancelOnFirstWatch()
            let outcome = await cut.run {
                await InstallCoordinator.backUp(installed, route: .sparkle)
            }
            try #require(cut.fired, "the copy finished before the watcher's first tick — nothing was cancelled mid-copy")
            #expect(outcome == .cancelled)
            #expect(BackupStore.backup(forKey: key)?.savedAt == earlier.savedAt)
            #expect(Self.entries(root) == [key], "left behind: \(Self.entries(root))")
        }
    }

    /// The install rollback point takes the same copy into its own store, and
    /// stops the same way. Mutation: forward no cancel in
    /// `runDittoWatchingSpace` → a rollback point is stored, red.
    @Test func aCancelDuringTheRollbackPointKeepsNothing() async throws {
        try await Self.withScratch { scratch, _ in
            let app = try Self.makeApp(in: scratch, files: 3000)
            let installed = Self.installed(app)
            let cut = CancelOnFirstWatch()
            let saved = await cut.run {
                await InstallCoordinator.takeInstallRollbackPoint(installed, route: .homebrew)
            }
            let pointsLeft = BackupStore.allRollbackPoints()
            let entriesLeft = Self.entries(BackupStore.rollbackPointsRoot)
            // Ends the claim `takeInstallRollbackPoint` began, as the hosts' defer does.
            await InstallCoordinator.settleInstallRollbackPoint(for: installed, journal: nil, succeeded: false)
            try #require(cut.fired, "the copy finished before the watcher's first tick — nothing was cancelled mid-copy")
            #expect(!saved)
            #expect(pointsLeft.isEmpty)
            #expect(entriesLeft.isEmpty, "left behind: \(entriesLeft)")
        }
    }

    // MARK: - Helpers

    /// Runs `body` in a task of its own and cancels that task from the space
    /// watcher's first tick — which only happens while `ditto` is copying. The
    /// first free-space read is the preflight before the copy; every later one
    /// is a tick. Plenty of room is reported throughout, so the watcher itself
    /// never stops anything.
    final class CancelOnFirstWatch: @unchecked Sendable {
        private let lock = NSLock()
        private var reads = 0
        private var task: Task<Void, Never>?
        private var requested = false
        private(set) var fired = false

        func run<T: Sendable>(_ body: @escaping @Sendable () async -> T) async -> T {
            let result = Box<T?>(nil)
            let free = BackupStore.freeSpaceFloorBytes + (100 << 30)
            let task = Task {
                let value = await BackupStore.$spaceWatchIntervalOverride.withValue(.milliseconds(1)) {
                    await BackupStore.$freeBytesOverride.withValue({ [self] in
                        tick()
                        return free
                    }) {
                        await body()
                    }
                }
                result.mutate { $0 = value }
            }
            lock.withLock {
                self.task = task
                if requested { task.cancel() }
            }
            await task.value
            return result.value!
        }

        private func tick() {
            let toCancel: Task<Void, Never>? = lock.withLock {
                reads += 1
                guard reads == 2 else { return nil }
                fired = true
                requested = true
                return task
            }
            toCancel?.cancel()
        }
    }

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T
        init(_ value: T) { stored = value }
        var value: T { lock.withLock { stored } }
        func mutate(_ change: (inout T) -> Void) { lock.withLock { change(&stored) } }
    }

    private static func withScratch(_ body: (URL, URL) async throws -> Void) async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-cancelled-backup-\(UUID().uuidString)")
        let root = scratch.appendingPathComponent("Backups")
        let facts = scratch.appendingPathComponent("Facts")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await BackupStore.$rootOverride.withValue(root) {
            try await BackupStore.$destinationOverride.withValue(.local) {
                try await BackupFactsLibrary.$rootOverride.withValue(facts) {
                    try await body(scratch, root)
                }
            }
        }
    }

    /// Every entry directly under `dir`, hidden ones (the staging) included.
    private static func entries(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private static func makeApp(in dir: URL, files: Int) throws -> URL {
        let app = dir.appendingPathComponent("ZZFixture-Cancel.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>App</string>
          <key>CFBundleIdentifier</key><string>com.example.zzfixture.cancel</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleShortVersionString</key><string>1.0</string>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        let payload = Data(repeating: 7, count: 4096)
        for i in 0..<files {
            try payload.write(to: resources.appendingPathComponent("r\(i).bin"))
        }
        return app
    }

    private static func installed(_ app: URL) -> InstalledApp {
        InstalledApp(
            name: "ZZFixture-Cancel", bundleID: "com.example.zzfixture.cancel",
            shortVersion: "1.0", buildVersion: nil, path: app, isMASApp: false,
            sparkleFeedURL: nil)
    }

    private static func workDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-cancelled-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("zz".utf8).write(to: dir.appendingPathComponent("ZZFixture.zip"))
        return dir
    }

    private static func result() -> UpdateResult {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-\(UUID().uuidString).app")
        return UpdateResult(
            app: InstalledApp(
                name: "ZZFixture", bundleID: "com.example.zzfixture",
                shortVersion: "1.0", buildVersion: "1", path: path,
                isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: nil),
            remote: RemoteVersion(
                shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Sparkle"),
            status: .updateAvailable(latest: "1.1"))
    }
}
