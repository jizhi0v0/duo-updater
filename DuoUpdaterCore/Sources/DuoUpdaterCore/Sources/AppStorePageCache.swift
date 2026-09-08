import Foundation

/// Cross-scan TTL cache for App Store Mac versions/notes and Mac-compatibility
/// flags, stored separately by (trackId, region).
/// Caches nil parses from successful responses; callers must exclude transport
/// failures, non-2xx responses, and undecodable bodies
/// (`MacAppStoreSource.PageFetchOutcome`).
/// See `docs/engine-notes/app-store-page-cache.md` §1 for scope and history,
/// and `MacAppStorePageCacheTests` for cache and source-integration coverage.
public actor AppStorePageCache {

    /// Must outlive the source stack, which `AppListModel.makeSources` rebuilds
    /// each check. Tests inject isolated instances with a controllable clock.
    /// See `docs/engine-notes/app-store-page-cache.md` §2 for the lifetime regression.
    public static let shared = AppStorePageCache()

    private struct Key: Hashable {
        let trackId: Int
        let region: String
    }

    private struct Entry<Value> {
        let value: Value
        let fetchedAt: Date
    }

    /// Maximum entry age (default: one hour); explicit refreshes invalidate sooner.
    /// This bounds staleness, not vendor publication frequency.
    /// See `docs/engine-notes/app-store-page-cache.md` §3 for the original choice.
    let ttl: TimeInterval
    private let now: @Sendable () -> Date

    private var versionStore: [Key: Entry<MacAppStoreSource.MacVersionInfo?>] = [:]
    private var compatStore: [Key: Entry<Bool?>] = [:]

    /// `MacAppStoreSource.resolve` registers each bundle's (trackId, region) keys.
    /// A bundle can span storefronts; multiple bundle IDs can share a track ID.
    /// Retained across invalidations for all bundles resolved since process launch,
    /// including subsequently uninstalled apps.
    private var keysByBundleID: [String: Set<Key>] = [:]

    /// `now` is injectable so tests can advance the clock past `ttl` without a
    /// real sleep.
    init(ttl: TimeInterval = 3600, now: @escaping @Sendable () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    /// Associate a bundle with its cache key for later targeted invalidation.
    /// Called by `resolve` regardless of which branch scrapes a page.
    func note(bundleID: String, trackId: Int, region: String) {
        keysByBundleID[bundleID, default: []].insert(Key(trackId: trackId, region: region))
    }

    /// Clear both stores for a user-present full refresh. Scheduled sweeps retain
    /// entries; per-row rechecks use `invalidate(bundleIDs:)` instead.
    /// Retains the reverse index and does not cancel in-flight fetches.
    /// See `docs/engine-notes/app-store-page-cache.md` §4 for invalidation history.
    public func invalidateAll() {
        versionStore.removeAll()
        compatStore.removeAll()
    }

    /// Clear both stores for the bundles' registered keys; unknown IDs are a no-op.
    /// Shared track IDs may also evict another bundle's entry. The reverse index
    /// survives so repeated invalidation does not require another `note` call.
    /// An in-flight fetch can repopulate either store after invalidation; this is
    /// not a guarantee of a separate live fetch for a recheck racing a sweep.
    /// See `docs/engine-notes/app-store-page-cache.md` §5 for that race window.
    public func invalidate(bundleIDs: [String]) {
        for id in bundleIDs {
            for key in keysByBundleID[id] ?? [] {
                versionStore[key] = nil
                compatStore[key] = nil
            }
        }
    }

    /// The cached Mac-version scrape for (trackId, region), if a fresh entry
    /// exists. `.some(nil)` means "cached, and the page had no version";
    /// nil means "not cached (or expired) — go fetch it".
    func cachedVersion(trackId: Int, region: String) -> MacAppStoreSource.MacVersionInfo?? {
        let key = Key(trackId: trackId, region: region)
        guard let entry = versionStore[key], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return .some(entry.value)
    }

    func storeVersion(_ value: MacAppStoreSource.MacVersionInfo?, trackId: Int, region: String) {
        versionStore[Key(trackId: trackId, region: region)] = Entry(value: value, fetchedAt: now())
    }

    /// Same shape as `cachedVersion`, for the Mac-compatibility flag.
    func cachedCompatibility(trackId: Int, region: String) -> Bool?? {
        let key = Key(trackId: trackId, region: region)
        guard let entry = compatStore[key], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return .some(entry.value)
    }

    func storeCompatibility(_ value: Bool?, trackId: Int, region: String) {
        compatStore[Key(trackId: trackId, region: region)] = Entry(value: value, fetchedAt: now())
    }
}
