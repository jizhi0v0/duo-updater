import DuoUpdaterCore
import Foundation
import Testing

@Suite(.serialized) @MainActor
struct InstallSpaceStateTests {
    final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: Int64?
        private var reads = 0
        private var reclaims = 0
        init(_ bytes: Int64?) { self.bytes = bytes }
        func set(_ bytes: Int64?) { lock.withLock { self.bytes = bytes } }
        func read(_ reclaiming: Bool = false) -> DiskSpaceGuard.Capacity {
            lock.withLock {
                reads += 1
                if reclaiming { reclaims += 1 }
                return .init(freeBytes: bytes)
            }
        }
        var readCount: Int { lock.withLock { reads } }
        var reclaimCount: Int { lock.withLock { reclaims } }
    }

    @Test func lowSpacePausesAdmissionAndTheNextRefreshRecoversWithoutChangingPreferences() async {
        let probe = Probe(BackupStore.freeSpaceFloorBytes - 1)
        let state = InstallSpaceState(readCapacity: { _ in probe.read() })
        #expect(await state.refresh() == false)
        #expect(state.isLow)
        #expect(state.message != nil)

        // There is no separate polling loop: changing the observed disk alone
        // doesn't change a control until an open/check/admission refresh samples it.
        probe.set(BackupStore.freeSpaceFloorBytes + 1_000_000)
        #expect(state.isLow)
        #expect(probe.readCount == 1)
        #expect(await state.refresh())
        #expect(!state.isLow)
        #expect(state.message == nil)
        #expect(probe.readCount == 2)
    }

    @Test func anUnreadableCapacityDoesNotDisableEveryUpdate() async {
        let state = InstallSpaceState(readCapacity: { _ in .init(freeBytes: nil) })
        #expect(await state.refresh())
        #expect(!state.isLow)
        #expect(state.message == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func batchAdmissionStillReclaimsWhenItJoinsAReadOnlyControlRefresh() async {
        let reading = AsyncStream.makeStream(of: Void.self)
        let admitting = AsyncStream.makeStream(of: Void.self)
        let release = DispatchSemaphore(value: 0)
        let probe = Probe(BackupStore.freeSpaceFloorBytes - 1)
        let state = InstallSpaceState { reclaiming in
            if !reclaiming {
                let sampled = probe.read()
                if probe.readCount == 1 {
                    reading.continuation.yield()
                    release.wait()
                }
                return sampled
            }
            return .init(freeBytes: BackupStore.freeSpaceFloorBytes + (reclaiming ? 1 : -1))
        }
        let control = Task { await state.refresh() }
        var reads = reading.stream.makeAsyncIterator()
        await reads.next()
        let batch = Task {
            admitting.continuation.yield()
            return await state.refresh(reclaimingDownloads: true)
        }
        var admissions = admitting.stream.makeAsyncIterator()
        await admissions.next()
        release.signal()
        #expect(await batch.value)
        await control.value
        #expect(!state.isLow)
    }

    @Test func aHealthyCapacityCheckLeavesTheInstallLockAvailable() async {
        let state = InstallSpaceState { _ in
            let competing = try? InstallLock.acquire()
            #expect(competing != nil)
            competing?.release()
            return .init(freeBytes: BackupStore.freeSpaceFloorBytes + 1)
        }
        #expect(await state.refresh(reclaimingDownloads: true))
    }

    @Test func aBusyInstallerPreventsCacheReclamationButNotReadingCapacity() async throws {
        let holder = try InstallLock.acquire()
        defer { holder.release() }
        let probe = Probe(BackupStore.freeSpaceFloorBytes - 1)
        let state = InstallSpaceState(readCapacity: probe.read)
        #expect(await state.refresh(reclaimingDownloads: true) == false)
        #expect(state.isLow)
        #expect(probe.readCount == 1)
        #expect(probe.reclaimCount == 0)
    }
}
