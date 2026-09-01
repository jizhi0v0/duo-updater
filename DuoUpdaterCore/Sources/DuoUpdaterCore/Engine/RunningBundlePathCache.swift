import Foundation

/// The bundle paths of the processes running right now, in the form
/// `InstalledApp.path` is recorded in — symlink-resolved and stripped of
/// DuoUpdater's staging names — with each answer remembered for as long as
/// the process that produced it stays in the list.
///
/// **What it saves.** `UpdatePolicy.runtimeBundlePath` calls
/// `resolvingSymlinksInPath()`, which is a `realpath` — a filesystem walk, not a
/// string operation. The running set is recomputed on the main thread on every
/// `NSWorkspace` launch/terminate notification for *any* process on the
/// machine, and resolving the ~127 bundle URLs in one snapshot measured 1.5 ms
/// per event. Nearly all of that re-derived answers already known: the
/// processes behind those URLs are overwhelmingly long-lived and their bundles
/// do not move. Feeding each snapshot through here keeps the resolution for
/// the paths still present, resolves only the ones that just appeared, and
/// forgets the ones that left — so a launch or quit costs one `realpath` at
/// most (that of the app that launched), and the table is bounded by the
/// process count.
///
/// **Why not skip the resolution.** `AppScanner` records `InstalledApp.path`
/// symlink-resolved, and `isRunning` compares that string against this set, so
/// an app launched through a symlink would never light up if its raw
/// `bundleURL` were used as-is. Whether `NSRunningApplication.bundleURL` is
/// itself already resolved is not something this code assumes.
///
/// **Keyed by the raw path, not the process.** Several processes commonly
/// share one bundle (an app and its helpers) and cost one resolution between
/// them; and after a hot swap macOS can move a process's reported URL onto the
/// staged name, which is simply a new key and is resolved afresh.
public struct RunningBundlePathCache {
    /// raw `bundleURL.path` → what `resolver` returned for it, for exactly the
    /// raw paths present in the last snapshot.
    private var resolved: [String: String] = [:]
    private let resolver: (URL) -> String

    /// - Parameter resolver: how a raw bundle URL becomes a comparable path.
    ///   Defaults to `UpdatePolicy.runtimeBundlePath`; injectable so a test can
    ///   count how often it is asked.
    public init(resolver: @escaping (URL) -> String = UpdatePolicy.runtimeBundlePath) {
        self.resolver = resolver
    }

    /// Number of raw paths currently remembered — the previous snapshot's
    /// distinct bundle URLs.
    public var count: Int { resolved.count }

    /// The resolved paths for one snapshot of running processes.
    ///
    /// Raw paths seen in the previous snapshot reuse their answer; new ones are
    /// resolved; ones no longer present are dropped, so a path that leaves and
    /// comes back is resolved again rather than served from memory.
    public mutating func update(with bundleURLs: [URL]) -> Set<String> {
        var next: [String: String] = [:]
        next.reserveCapacity(bundleURLs.count)
        var paths: Set<String> = []
        for url in bundleURLs {
            let raw = url.path
            if let seenThisSnapshot = next[raw] {
                paths.insert(seenThisSnapshot)
                continue
            }
            let path = resolved[raw] ?? resolver(url)
            next[raw] = path
            paths.insert(path)
        }
        resolved = next
        return paths
    }
}
