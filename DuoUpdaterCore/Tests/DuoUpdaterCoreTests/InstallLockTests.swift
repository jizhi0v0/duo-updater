import Testing
import Foundation
@testable import DuoUpdaterCore

/// The lock exists to stop `duo install` and the menu-bar app replacing the same
/// bundle, or writing the backup index, at the same time. It shipped taken by
/// only one of the two, which made it look like it worked.
@Suite struct InstallLockTests {

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-lock-\(UUID().uuidString)")
            .appendingPathComponent("install.lock")
    }

    @Test func aSecondHolderIsRefusedAndTheFirstIsNamed() throws {
        let url = scratch()
        let first = try InstallLock.acquire(at: url)
        defer { first.release() }

        #expect(throws: InstallLock.Failure.self) {
            _ = try InstallLock.acquire(at: url)
        }
        #expect(InstallLock.currentHolder(at: url) == getpid(),
                "the refusal must be able to say who is holding it")
    }

    @Test func releasingMakesItAvailableAgain() throws {
        let url = scratch()
        try InstallLock.acquire(at: url).release()
        let second = try InstallLock.acquire(at: url)
        second.release()
    }

    /// The reason `ProcessInstallLock` exists: `flock` is exclusive per open
    /// file description, not per process, so the app's own parallel installs
    /// would have blocked each other if each took the raw lock.
    @Test func rawLocksCollideEvenWithinOneProcess() throws {
        let url = scratch()
        let held = try InstallLock.acquire(at: url)
        defer { held.release() }
        #expect(throws: InstallLock.Failure.self) {
            _ = try InstallLock.acquire(at: url)
        }
    }

    @Test func concurrentInstallsInOneProcessShareOneClaim() async throws {
        let url = scratch()
        let gate = ProcessInstallLock(url: url)
        try await gate.claim()
        try await gate.claim()   // a second install in the same process joins
        // Still held after one of them finishes.
        await gate.release()
        #expect(InstallLock.currentHolder(at: url) == getpid())
        await gate.release()
        // Free once the last one is done — provable by taking it raw.
        let after = try InstallLock.acquire(at: url)
        after.release()
    }

    /// An over-eager cleanup path must not free a lock another install still
    /// depends on.
    @Test func anUnbalancedReleaseIsANoOp() async throws {
        let url = scratch()
        let gate = ProcessInstallLock(url: url)
        await gate.release()
        try await gate.claim()
        await gate.release()
        await gate.release()
        let after = try InstallLock.acquire(at: url)
        after.release()
    }
    /// The refusal must be the *specific* case that names the holder, not just some
    /// `Failure` — the pid is the whole point of the message.
    ///
    /// Note this does not prove the `errno` capture in `acquire` is correct: the
    /// test passes either way today, because the `holderPID` and `close` calls that
    /// sit between the failed `flock` and the old `errno` read happen to succeed
    /// without disturbing it. Capturing errno immediately is defensive (POSIX only
    /// promises errno is set on failure, not that success leaves it alone), and the
    /// mis-ordering was latent rather than a bug anyone had hit.
    @Test func aRefusalReportsTheHolderRatherThanAGenericFailure() throws {
        let url = scratch()
        let first = try InstallLock.acquire(at: url)
        defer { first.release() }

        do {
            _ = try InstallLock.acquire(at: url)
            Issue.record("the second acquire should have been refused")
        } catch let failure as InstallLock.Failure {
            guard case .heldByAnother(let pid) = failure else {
                Issue.record("expected .heldByAnother, got \(failure)")
                return
            }
            #expect(pid == getpid())
        }
    }

    /// `release()` closes the descriptor and `deinit` calls `release()` again, so
    /// dropping a lock that was already released closes the same fd twice. The
    /// second close lands on whatever the process has since opened under that
    /// number — in a parallel test run, another suite's file — and the
    /// accompanying `flock(LOCK_UN)` unlocks somebody else's lock.
    ///
    /// Deterministic stand-in for that race: free the number, claim it with a
    /// probe, then drop the lock and check the probe survived.
    @Test func droppingAReleasedLockDoesNotCloseSomeoneElsesDescriptor() throws {
        let url = scratch()
        var lock: InstallLock? = try InstallLock.acquire(at: url)
        lock!.release()

        let probePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-lock-probe-\(UUID().uuidString)").path
        let probe = open(probePath, O_CREAT | O_RDWR, 0o600)
        try #require(probe >= 0)
        defer { close(probe); unlink(probePath) }

        lock = nil   // deinit → release() again

        #expect(fcntl(probe, F_GETFD) != -1,
                "InstallLock closed a descriptor it no longer owned")
    }
}

/// Which routes get a rollback point, and whether the store remembers that a
/// backup came from a `.pkg` — the restore path words itself differently for
/// those, because only the app bundle comes back.
@Suite struct BackupProvenanceTests {

    @Test func everyRouteWeApplyOurselvesGetsABackup() {
        #expect(InstallCoordinator.wantsBackup(.vendor))
        #expect(InstallCoordinator.wantsBackup(.sparkle))
        #expect(InstallCoordinator.wantsBackup(.homebrew))
        // Included as of 2026-08-09: these had no rollback point at all, which is
        // the case where one is most wanted.
        #expect(InstallCoordinator.wantsBackup(.installer))
        // The store re-downloads a prior build on demand, so a local copy of a
        // multi-gigabyte bundle would be dead weight.
        #expect(!InstallCoordinator.wantsBackup(.appStore))
    }

}
