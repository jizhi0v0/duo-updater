import Foundation

/// Short-TTL cache backing `MacAppStoreSource.prewarm(_:)`'s batched iTunes
/// lookups.
///
/// A full scan's per-app checks all start within the same task-group window
/// (see `UpdateChecker.check(_:)`, which calls `prewarm` before that group
/// starts), so an entry here only needs to outlive one scan pass — 120 s
/// comfortably covers even a slow one (measured: ~7.5 s for 209 requests, ~6.5 s
/// of that spent on ~30 App Store lookups). This is strictly additive:
/// `MacAppStoreSource.lookup(bundleID:region:)` checks here first and, on a
/// miss, falls through unchanged to its normal per-bundle request — a prewarm
/// that failed, or an app it never covered (a fallback-region probe, or a
/// single-app recheck that still calls `check(_:)` with one element and so
/// still prewarms, but for just that one app), costs nothing extra.
///
/// Same outer-optional convention as `AppStorePageCache`: nil means "not
/// prewarmed (or the entry expired) — go do the normal live lookup"; `.some(nil)`
/// means "prewarm asked and the store legitimately had zero results for this
/// bundle in this storefront" — a definite answer, not a reason to ask again.
actor AppStoreLookupCache {

    private struct Key: Hashable {
        let bundleID: String
        let region: String
    }

    private struct Entry {
        let result: MacAppStoreSource.LookupResult?
        let fetchedAt: Date
    }

    let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var store: [Key: Entry] = [:]

    init(ttl: TimeInterval = 120, now: @escaping @Sendable () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    func lookup(bundleID: String, region: String) -> MacAppStoreSource.LookupResult?? {
        let key = Key(bundleID: bundleID, region: region)
        guard let entry = store[key], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return .some(entry.result)
    }

    /// Records one batch's worth of results. `results` maps every bundle id that
    /// was IN that batch request to what came back for it — including a nil for
    /// one the store didn't have, so a later miss on that id reads as a cached
    /// "not found" rather than falling through to a live request.
    func store(_ results: [String: MacAppStoreSource.LookupResult?], region: String) {
        let stamp = now()
        for (bundleID, result) in results {
            store[Key(bundleID: bundleID, region: region)] = Entry(result: result, fetchedAt: stamp)
        }
    }
}
