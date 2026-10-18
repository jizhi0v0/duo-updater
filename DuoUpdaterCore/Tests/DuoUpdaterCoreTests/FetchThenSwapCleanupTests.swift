import Foundation
import Testing
@testable import DuoUpdaterCore

/// `InstallCoordinator.fetchThenSwap` owns the download's scratch directory once
/// `download` returns, and removes it on every exit: the apply succeeding, the
/// apply throwing, and a cancellation landing before the apply. The directory
/// here is an invented one with a file in it; `download` and `apply` are stubs.
///
/// Mutation: drop the `defer { await removeItemOffCooperativePool(at: downloaded.workDir) }`
/// → all three leave the directory behind.
@Suite struct FetchThenSwapCleanupTests {

    private struct ZZApplyFailed: Error {}

    @Test func theWorkDirGoesWhenTheApplySucceeds() async throws {
        let workDir = try Self.workDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        _ = try await Self.run(workDir: workDir) { }
        #expect(!FileManager.default.fileExists(atPath: workDir.path))
    }

    @Test func theWorkDirGoesWhenTheApplyThrows() async throws {
        let workDir = try Self.workDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        await #expect(throws: ZZApplyFailed.self) {
            _ = try await Self.run(workDir: workDir) { throw ZZApplyFailed() }
        }
        #expect(!FileManager.default.fileExists(atPath: workDir.path))
    }

    /// Cancelled while downloading: the download stub cancels its own task and
    /// returns, so the apply phase's `checkCancellation` throws before `apply`.
    @Test func theWorkDirGoesWhenCancelledBeforeTheApply() async throws {
        let workDir = try Self.workDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let applied = Counter()
        let task = Task {
            try await Self.run(workDir: workDir, cancelDuringDownload: true) { applied.bump() }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(applied.value == 0)
        #expect(!FileManager.default.fileExists(atPath: workDir.path))
    }

    // MARK: - Cancelled around the commit

    /// Cancelled inside the apply phase, after its preparation and just before
    /// its swap: the swap — wrapped in `InstallCommit` exactly as the installers
    /// wrap `InPlaceSwap.replace` — never starts, the scratch directory goes, and
    /// both permits are back.
    /// Mutation: drop `InstallCommit.run`'s `checkCancellation` → swapped, red.
    @Test func aCancelJustBeforeTheSwapAppliesNothing() async throws {
        let workDir = try Self.workDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let permits = InstallPermits(downloads: 1, applies: 1)
        let swapped = Counter()
        let task = Task {
            try await Self.run(workDir: workDir, permits: permits, applyAsync: {
                // The preparation part of an apply (extract, verify) ends here.
                withUnsafeCurrentTask { $0?.cancel() }
                try await InstallCommit.run("swap") { swapped.bump() }
            })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(swapped.value == 0)
        #expect(!FileManager.default.fileExists(atPath: workDir.path))
        #expect(permits.availableDownloadPermits == 1)
        #expect(permits.availableApplyPermits == 1)
    }

    /// Cancelled while the swap runs: the swap finishes, the install reports it
    /// applied, the scratch directory goes and both permits are back.
    /// Mutation: call the commit's body directly instead of in its unstructured
    /// task → the swap's `Task.sleep` throws, nothing reports applied, red.
    @Test func aCancelDuringTheSwapStillApplies() async throws {
        let workDir = try Self.workDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let permits = InstallPermits(downloads: 1, applies: 1)
        let swapped = Counter()
        let entered = InstallCommitTests.Signal()
        let release = InstallCommitTests.Signal()
        let task = Task {
            try await Self.run(workDir: workDir, permits: permits, applyAsync: {
                try await InstallCommit.run("swap") {
                    entered.fire()
                    await release.wait()
                    // Stands in for the swap's own awaits, which a cancel that
                    // reached it would cut short.
                    try await Task.sleep(for: .milliseconds(20))
                    swapped.bump()
                }
            })
        }
        await entered.wait()
        task.cancel()
        release.fire()
        let outcome = try await task.value
        #expect(outcome.applied)
        #expect(swapped.value == 1)
        #expect(!FileManager.default.fileExists(atPath: workDir.path))
        #expect(permits.availableDownloadPermits == 1)
        #expect(permits.availableApplyPermits == 1)
    }

    // MARK: - Helpers

    private static func run(
        workDir: URL, cancelDuringDownload: Bool = false,
        permits: InstallPermits = InstallPermits(downloads: 1, applies: 1),
        apply: @escaping @Sendable () throws -> Void = {},
        applyAsync: @escaping @Sendable () async throws -> Void = {}
    ) async throws -> InstallCoordinator.Outcome {
        let coordinator = InstallCoordinator(permits: permits)
        let archive = workDir.appendingPathComponent("ZZFixture.zip")
        return try await coordinator.fetchThenSwap(
            Self.result(), spaceToApply: 0, progress: { _ in }, releaseAfterDownload: {},
            download: { _, _ in
                if cancelDuringDownload { withUnsafeCurrentTask { $0?.cancel() } }
                return DownloadedUpdate(archiveURL: archive, bytesDownloaded: 1, workDir: workDir)
            },
            apply: { _, _, _ in
                try apply()
                try await applyAsync()
            })
    }

    private static func workDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-fetchswap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("ZZFixture.app/Contents"), withIntermediateDirectories: true)
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

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }
}
