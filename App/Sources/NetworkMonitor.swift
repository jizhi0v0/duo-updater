import Foundation
import Network
import DuoUpdaterCore

/// Coarse network-reachability flag for the background update loop.
///
/// Why this exists: with the lid closed / no Wi-Fi, the periodic check still
/// fires on schedule, every networked source fails, and the list fills with
/// "click to retry" error rows — while `refresh` resets `lastCheck` so the next
/// tick is a full interval away even though nothing was actually checked. The
/// scheduler reads `path` at each tick and simply *defers* (like the busy
/// case) while offline, leaving `lastCheck` untouched so it re-checks promptly
/// once connectivity returns.
///
/// Only the *networked* check is gated — the local FS watcher / rescan backstop
/// that keep the Restart badge current are network-free and keep running.
///
/// The same deferral covers a path in Low Data Mode (`isConstrained`) or an
/// expensive one (`isExpensive`, a Personal Hotspot): `path` carries all three
/// facts and `NetworkPathState.allowsDiscretionaryTraffic` decides. Explicit user
/// actions do not read it.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// The current path. Seeded usable so a check can run before the first path
    /// update lands (NWPathMonitor delivers the initial state asynchronously);
    /// the first real update corrects it.
    private(set) var path = NetworkPathState.assumedUsable

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.duoupdater.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor calls back on `queue`; hop to the main actor.
            let state = NetworkPathState(
                isSatisfied: path.status == .satisfied,
                isConstrained: path.isConstrained,
                isExpensive: path.isExpensive)
            Task { @MainActor in self?.apply(state) }
        }
        monitor.start(queue: queue)
    }

    private func apply(_ state: NetworkPathState) {
        guard state != path else { return }
        path = state
        Log.app.info("network: \(state.isSatisfied ? "online" : "offline", privacy: .public) constrained=\(state.isConstrained, privacy: .public) expensive=\(state.isExpensive, privacy: .public)")
    }
}
