import Foundation

/// A strategy for discovering the latest available version of an app.
/// Sources are tried in priority order; the first one that can answer wins.
public protocol UpdateSource: Sendable {
    /// Human-readable name, shown in the UI ("Sparkle", "App Store", ...).
    var name: String { get }

    /// Return the latest version this source knows about for `app`, or nil if
    /// this source doesn't apply to the app (e.g. no Sparkle feed). Throw on a
    /// real failure (network/parse) so the engine can surface an error rather
    /// than silently treating it as "not applicable".
    func latestVersion(for app: InstalledApp) async throws -> RemoteVersion?

    /// Optional hook: given the full app list for a scan, do whatever
    /// cheaper-in-bulk work would help `latestVersion(for:)` avoid a request it
    /// would otherwise make per app. `UpdateChecker.check(_ apps:)` calls this
    /// once, for every source, before its per-app fan-out starts — the only
    /// point that has the whole list in hand at once. Default is a no-op, so
    /// only a source that actually has a batched endpoint needs to implement it
    /// (see `MacAppStoreSource.prewarm`, which batches iTunes lookups).
    func prewarm(_ apps: [InstalledApp]) async
}

public extension UpdateSource {
    func prewarm(_ apps: [InstalledApp]) async {}
}
