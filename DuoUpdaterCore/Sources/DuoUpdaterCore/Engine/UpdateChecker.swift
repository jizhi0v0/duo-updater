import Foundation

/// Orchestrates update checking across sources with bounded concurrency.
/// Sources are consulted in priority order; the first that returns a version
/// for an app wins. Network fan-out is capped so we don't open hundreds of
/// sockets at once.
public struct UpdateChecker: Sendable {

    public let sources: [any UpdateSource]
    public let maxConcurrency: Int

    public init(sources: [any UpdateSource], maxConcurrency: Int = 12) {
        self.sources = sources
        self.maxConcurrency = max(1, maxConcurrency)
    }

    /// Check every app, returning results in the same order as the input.
    public func check(_ apps: [InstalledApp]) async -> [UpdateResult] {
        var results = [UpdateResult?](repeating: nil, count: apps.count)

        await withTaskGroup(of: (Int, UpdateResult).self) { group in
            var next = 0
            var inFlight = 0

            func addTask(_ index: Int) {
                let app = apps[index]
                group.addTask {
                    (index, await self.check(app))
                }
            }

            // Prime the window.
            while next < apps.count && inFlight < maxConcurrency {
                addTask(next); next += 1; inFlight += 1
            }
            // Drain and refill.
            while let (index, result) = await group.next() {
                results[index] = result
                inFlight -= 1
                if next < apps.count {
                    addTask(next); next += 1; inFlight += 1
                }
            }
        }

        return results.compactMap { $0 }
    }

    /// Check one app across all sources in priority order.
    public func check(_ app: InstalledApp) async -> UpdateResult {
        var lastError: String?

        for source in sources {
            do {
                guard let remote = try await source.latestVersion(for: app) else {
                    continue  // source doesn't apply; try the next one
                }
                return UpdateResult(
                    app: app,
                    remote: remote,
                    status: Self.evaluate(installed: app, remote: remote)
                )
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        if let lastError {
            return UpdateResult(app: app, remote: nil, status: .error(lastError))
        }
        return UpdateResult(app: app, remote: nil, status: .unknown)
    }

    /// Decide whether `remote` is newer than what's installed. Prefer comparing
    /// build versions (Sparkle's canonical key) when both sides have one; fall
    /// back to the marketing version otherwise.
    static func evaluate(installed: InstalledApp, remote: RemoteVersion) -> UpdateStatus {
        let pair: (installed: String, remote: String)?
        if let rv = remote.version, let iv = installed.buildVersion {
            pair = (iv, rv)
        } else if let rs = remote.shortVersion, let isv = installed.shortVersion {
            pair = (isv, rs)
        } else {
            pair = nil
        }

        guard let pair else { return .unknown }

        if VersionComparator.isNewer(pair.remote, than: pair.installed) {
            return .updateAvailable(latest: remote.displayVersion ?? pair.remote)
        }
        return .upToDate
    }
}
