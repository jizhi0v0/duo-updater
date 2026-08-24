import AppKit
import DuoUpdaterCore
import Foundation

/// Starts moving backups when the backup disk appears, and stops when it is
/// about to go away.
///
/// The queue can already recover on its own — an interrupted transfer leaves the
/// local copy untouched, and the next drain redoes it — so nothing here is
/// load-bearing for correctness. What it buys is timing: without it, a disk
/// plugged in at lunchtime would sit idle until the next update happened to
/// trigger a drain, and a transfer running when the user reaches for Eject would
/// hold the volume busy long enough to be told the disk is in use.
///
/// Lives in the app rather than the core package because `NSWorkspace`'s mount
/// notifications are AppKit, and `duo` is a short-lived process that transfers
/// synchronously and has nothing to watch for.
@MainActor
final class BackupVolumeWatcher {

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.diskAppeared()
        })

        // `willUnmount`, not `didUnmount`: the point is to stop before the volume
        // goes, so the copy is not the reason the eject fails. It is best effort —
        // the notification may not arrive early enough to interrupt a write in
        // progress — which is why the recovery path does not depend on it.
        observers.append(center.addObserver(
            forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.diskLeaving()
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.diskLeaving()
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.diskAppeared()
        })

        // Quitting must take the archive subprocess down with us. `aa` is a
        // child process and macOS does not reap it on our exit, so an orphan
        // would keep writing, finish, and rename a complete archive into place
        // that no sidecar records — bytes no read path can see. Nothing is lost
        // by stopping mid-archive: the local copy is only removed once the
        // destination copy is complete, so the work is simply owed again.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            BundleArchive.terminateInFlight()
        })
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    // No `deinit` unregistering: the observers are main-actor state and `deinit`
    // is not isolated, so it cannot reach them. That is fine here rather than
    // merely tolerable — this watcher is created once, at launch, and lives as
    // long as the app does, so there is no moment where it is deallocated with
    // observers still attached. `stop()` exists for a caller that wants to.

    /// Any volume appearing is enough of a hint to look — the notification does
    /// not say which disk we care about, and asking the store is cheap next to
    /// getting this wrong.
    private func diskAppeared() {
        Task.detached(priority: .utility) {
            guard case .ready = BackupStore.availability() else { return }
            // Sweep before draining, not after: a disk that has just come back is
            // the one place an interrupted transfer's leftovers are — a `.partial`
            // the yank cut off, or a key directory whose archive landed but whose
            // sidecar never did. Clearing them first means the drain is not
            // writing beside dead bytes it will then have to work around.
            let inFlight = await BackupTransferQueue.shared.protectedKeys
            BackupStore.sweepStaleScratch(excluding: inFlight)
            await BackupTransferQueue.shared.resumePending()
            await BackupTransferQueue.shared.drain()
        }
    }

    private func diskLeaving() {
        Task.detached(priority: .utility) {
            await BackupTransferQueue.shared.suspend()
        }
    }
}
