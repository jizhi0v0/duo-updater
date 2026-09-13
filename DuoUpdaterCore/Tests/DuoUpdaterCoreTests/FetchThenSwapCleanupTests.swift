import Foundation
import Testing
@testable import DuoUpdaterCore

/// `InstallCoordinator.fetchThenSwap` owns the download's scratch directory once
/// `download` returns, and removes it on every exit: the apply succeeding, the
/// apply throwing, and a cancellation landing before the apply. The directory
/// here is an invented one with a file in it; `download` and `apply` are stubs.
///
/// Mutation: drop the `removeItemOffCooperativePool(at: downloaded.workDir)` after
/// the apply phase → all three leave the directory behind.
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

    // MARK: - Helpers

    private static func run(
        workDir: URL, cancelDuringDownload: Bool = false,
        apply: @escaping @Sendable () throws -> Void
    ) async throws -> InstallCoordinator.Outcome {
        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
        let archive = workDir.appendingPathComponent("ZZFixture.zip")
        return try await coordinator.fetchThenSwap(
            Self.result(), progress: { _ in }, releaseAfterDownload: {},
            download: { _, _ in
                if cancelDuringDownload { withUnsafeCurrentTask { $0?.cancel() } }
                return DownloadedUpdate(archiveURL: archive, bytesDownloaded: 1, workDir: workDir)
            },
            apply: { _, _, _ in try apply() })
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
