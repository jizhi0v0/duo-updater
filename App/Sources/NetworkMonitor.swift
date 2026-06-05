import Foundation
import Network
import DuoUpdaterCore

/// Coarse network-reachability flag for the background update loop.
///
/// Why this exists: with the lid closed / no Wi-Fi, the periodic check still
/// fires on schedule, every networked source fails, and the list fills with
/// "click to retry" error rows — while `refresh` resets `lastCheck` so the next
/// tick is a full interval away even though nothing was actually checked. The
/// scheduler reads `isOnline` at each tick and simply *defers* (like the busy
/// case) while offline, leaving `lastCheck` untouched so it re-checks promptly
/// once connectivity returns.
///
/// Only the *networked* check is gated — the local FS watcher / rescan backstop
/// that keep the Restart badge current are network-free and keep running.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// True when the system reports a usable network path. Seeded `true` so a
    /// check can run before the first path update lands (NWPathMonitor delivers
    /// the initial state asynchronously); the first real update corrects it.
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.duoupdater.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor calls back on `queue`; hop to the main actor.
            let online = path.status == .satisfied
            Task { @MainActor in self?.apply(online: online) }
        }
        monitor.start(queue: queue)
    }

    private func apply(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        Log.app.info("network: \(online ? "online" : "offline", privacy: .public)")
    }
}
