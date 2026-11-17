import DuoUpdaterCore
import Foundation
import Observation

/// One space snapshot for the controls and the batch admission checks. Refreshed
/// on launch, opening the controls, update checks and starting a batch; no timer.
@MainActor @Observable
final class InstallSpaceState {
    private(set) var capacity = DiskSpaceGuard.Capacity(freeBytes: nil)
    @ObservationIgnored private let readCapacity: @Sendable (Bool) -> DiskSpaceGuard.Capacity
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshReclaimsDownloads = false

    init(readCapacity: @escaping @Sendable (Bool) -> DiskSpaceGuard.Capacity = DiskSpaceGuard.Capacity.read) {
        self.readCapacity = readCapacity
    }

    var isLow: Bool { capacity.shortfall != nil }

    var message: String? {
        guard let shortfall = capacity.shortfall else { return nil }
        let free = ByteCountFormatter.string(fromByteCount: shortfall.free, countStyle: .file)
        let needed = ByteCountFormatter.string(fromByteCount: shortfall.needed, countStyle: .file)
        return String(localized: "Updates are paused: \(free) free on this Mac; at least \(needed) must remain free. Free up space, then check for updates again.")
    }

    /// Also used by non-button entry points, so a stale enabled control cannot
    /// queue a whole batch on a disk that has filled since it was last opened.
    @discardableResult
    func refresh(reclaimingDownloads: Bool = false) async -> Bool {
        if let refreshTask {
            let reclaims = refreshReclaimsDownloads
            await refreshTask.value
            if reclaimingDownloads && !reclaims && isLow {
                return await refresh(reclaimingDownloads: true)
            }
            return !isLow
        }
        refreshReclaimsDownloads = reclaimingDownloads
        let task = Task {
            let read = readCapacity
            capacity = await offCooperativePool(qos: .utility) { read(false) }
            if reclaimingDownloads && isLow {
                do {
                    try await ProcessInstallLock.shared.claim()
                    capacity = await offCooperativePool(qos: .utility) { read(true) }
                    await ProcessInstallLock.shared.release()
                } catch {
                    // Another process may be writing its resumable downloads.
                    // A read-only sample is enough until that install finishes.
                }
            }
            refreshTask = nil
        }
        refreshTask = task
        await task.value
        return !isLow
    }
}
