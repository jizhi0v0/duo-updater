import Foundation

/// TTL-memoized cache for the two things `MacAppStoreSource` scrapes off an App
/// Store product page: the Mac-track version (+ "What's New" notes) and the
/// `isIOSBinaryMacOSCompatible` flag. Both are read from more than one call site
/// per app per check (`nativeMacVersion` and `iosOnMacVersion` both scrape a
/// version page; `remoteVersion` scrapes a compatibility page), and a full scan
/// revisits the same trackId/region on every pass — memoizing turns that into
/// one fetch per hour instead of one per check.
///
/// Deliberately caches a *parse failure* (2xx response, no version/flag found)
/// the same as a *parse success* — an unparseable page costs full price again
/// only once per TTL window, not once per check, which is the failure mode this
/// exists to fix (skipping the scrape entirely would instead make the two
/// call sites for a Mac version disagree with each other and with the lookup
/// API, since only one of them would ever get a fresh page). A *transport
/// failure or non-2xx response* is NOT cached: a network blip or a server
/// hiccup must not freeze a bad answer in place for an hour. Callers keep those
/// two outcomes apart before they ever reach this cache — see
/// `MacAppStoreSource.fetchMacVersion`/`fetchMacCompatibility`, whose
/// `PageFetchOutcome.unavailable` case is exactly "don't cache this".
///
/// The outer optional in `cachedVersion`/`cachedCompatibility` distinguishes "no
/// entry, or a stale one" (nil — go fetch) from "cached, and the cached value is
/// itself nil" (`.some(nil)` — a real answer, use it). Collapsing those two
/// would re-fetch a legitimately-nil cached parse failure on every single call,
/// defeating the point of caching it at all.
public actor AppStorePageCache {

    /// The process-wide cache, and the one production actually uses.
    ///
    /// **This has to outlive the source that reads it, and by default it did
    /// not.** `AppListModel.makeSources` rebuilds the whole source stack on
    /// every check — deliberately, so a token change and the signed-in
    /// storefront region are re-read — so a `MacAppStoreSource` lives about
    /// seven seconds. A per-instance cache with a one-hour TTL is therefore
    /// born and destroyed inside a single scan and never survives to answer
    /// the next one: measured 2026-09-04, the product-page fetches per scan
    /// round did not fall at all (20.6 → 23.6 requests, 623 → 786 KB) while
    /// every other change in the same batch landed. The unit tests missed it
    /// because they exercise one instance twice, which is exactly the thing
    /// that was already working.
    ///
    /// Same shape as `ChangelogCache.shared`, `ResolvedChannelStore.shared`
    /// and `EventStore.shared` for the same reason. Tests inject their own
    /// instance (with a fake clock) through `MacAppStoreSource.init`.
    public static let shared = AppStorePageCache()

    private struct Key: Hashable {
        let trackId: Int
        let region: String
    }

    private struct Entry<Value> {
        let value: Value
        let fetchedAt: Date
    }

    /// How long a scraped page stays valid. Default is one hour: App Store
    /// listings don't update more often than that, and a scan revisits the same
    /// app every few minutes.
    let ttl: TimeInterval
    private let now: @Sendable () -> Date

    private var versionStore: [Key: Entry<MacAppStoreSource.MacVersionInfo?>] = [:]
    private var compatStore: [Key: Entry<Bool?>] = [:]

    /// `now` is injectable so tests can advance the clock past `ttl` without a
    /// real sleep.
    init(ttl: TimeInterval = 3600, now: @escaping @Sendable () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    /// Drop everything, so the next scrape is live.
    ///
    /// The TTL alone is not enough, and the gap is user-visible. For a
    /// `kind == "software"` listing the scraped page is the ONLY version source
    /// — `iosOnMacVersion` returns nil without it, and unlike `nativeMacVersion`
    /// there is no lookup answer sitting behind it to make a stale page
    /// harmless. So a user who reads a release announcement and presses Check
    /// Now would have been told the same old version for up to an hour, with no
    /// way to insist. Before this cache existed every check re-fetched. Five of
    /// the twenty Mac App Store apps on the machine this was measured on take
    /// that route (2026-09-05).
    ///
    /// Called from the explicit-recheck path only. A periodic sweep must NOT
    /// call it — that would put the cache back to fetching a page per app per
    /// round, which is the cost it exists to remove.
    public func invalidateAll() {
        versionStore.removeAll()
        compatStore.removeAll()
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
