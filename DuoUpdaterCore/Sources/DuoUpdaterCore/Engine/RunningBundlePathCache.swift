import Foundation

/// The bundle paths of the processes running right now, in the form
/// `InstalledApp.path` is recorded in — symlink-resolved and stripped of
/// DuoUpdater's staging names — with each answer remembered for as long as
/// the raw path that produced it stays in the list.
///
/// **What it saves.** `UpdatePolicy.runtimeBundlePath` calls
/// `resolvingSymlinksInPath()`, which is a `realpath` — a filesystem walk, not a
/// string operation. The running set is recomputed on the main thread on every
/// change to `NSWorkspace.runningApplications` — for *any* process on the machine.
/// Measured on the development machine in a release build, over a live snapshot
/// of 129 bundle URLs (106 distinct paths):
///
///     resolve every process, every event   1.164 ms
///     this cache, warm                     0.095 ms
///     no resolution at all                 0.047 ms
///
/// Nearly all of that re-derived answers already known: the processes behind
/// those URLs are overwhelmingly long-lived and their bundles do not move.
/// Feeding each snapshot through here keeps the resolution for the paths still
/// present, resolves only the ones that just appeared, and forgets the ones that
/// left — so the per-event cost is bounded by the number of **newly appeared
/// distinct bundle paths**, and the table by the number of distinct paths in the
/// snapshot. Not "one per launch": a single user-visible app launch brings its
/// XPC services with it, each with its own `bundleURL` (Safari alone adds four),
/// and a login brings a hundred at once.
///
/// **The invariant it needs** is not "bundles do not move" but the narrower "the
/// resolver's answer for a fixed raw path does not change while that path stays
/// in the snapshot". `resolvingSymlinksInPath` is existence-sensitive — see
/// `InstallerWindowCloser`, which records that it drops a leading `/private`
/// only for a path that exists — so a first resolution taken while the bundle
/// was momentarily absent is the answer kept until the process exits. The
/// install paths that could do that call `refreshRunningApps` themselves before
/// they decide anything, and a path that leaves the snapshot is forgotten.
///
/// **Why not skip the resolution.** `AppScanner` records `InstalledApp.path`
/// symlink-resolved, and `isRunning` compares that string against this set, so
/// an app launched through a symlink would never light up if its raw
/// `bundleURL` were used as-is. `bundleURL` is *mostly* already resolved —
/// measured, 1 of 129 running bundle URLs differs from its own realpath (an
/// `AuthenticationServices` XPC service that resolves into
/// `/System/Volumes/Preboot/Cryptexes`) — but "mostly" is not a rule to compare
/// paths by, and keeping the resolution costs 0.05 ms/event once memoized.
/// It also does double duty: `runtimeBundlePath` is where the
/// `.duoupdater-staged-` / `-old` / `-new` names are normalised away, which is
/// not optional and is why the default resolver is that function and not a bare
/// `resolvingSymlinksInPath`.
///
/// **Keyed by the raw path, not the process.** Several processes commonly
/// share one bundle (an app and its helpers) and cost one resolution between
/// them; and a reported URL that moves onto a staging name is simply a new key,
/// resolved afresh.
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
    /// distinct bundle URLs. Internal: the tests reach it with `@testable`, and
    /// nothing outside this file has business knowing the table's size.
    var count: Int { resolved.count }

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
