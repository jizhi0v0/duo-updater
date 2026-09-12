import Foundation

/// TTL-memoized cache for the two App Store product pages `MacAppStoreSource`
/// scrapes: the `?platform=mac` page (`versionStore`) and the plain product
/// page (`compatStore`). Each fetch runs BOTH extractors
/// (`extractMacVersionInfo` + `extractMacCompatibility`) over whichever page
/// it fetched, bundling everything that one scrape settled into one
/// `MacAppStoreSource.MacPageFacts` value — see that type's doc comment for
/// why a page can answer one half and not the other (Nowdex's `?platform=mac`
/// page has no version shelf at all, yet still carries the compatibility
/// signals and the OS floor).
///
/// **All of the value is across scans, none of it within one.** `resolve()` is
/// a three-way dispatch with early returns, so exactly one of
/// `nativeMacVersion` / `remoteVersion(checkMacCompat:)` / `iosOnMacVersion`
/// runs per app per check, and each of those fetches at most ONE of the two
/// pages — so a given app's check populates at most one of `versionStore` /
/// `compatStore` this round, never both. The two stores are kept separate
/// (not merged, even though they now hold the same value type) precisely
/// because they answer for two different URLs: Nowdex's `?platform=mac`
/// scrape and its plain-page scrape can and do disagree about what they can
/// settle. What this class removes is a second app-launch scan's fetch, up to
/// the TTL — so the benefit is `1 − interval/ttl`, and at the six-hour default
/// interval (`Preferences`) an interval longer than the TTL means every
/// scheduled round is a cold miss and this class saves nothing there. (How
/// many installs leave that default alone is not something this repo can see,
/// so the claim stops at the default itself.) What it still buys is the
/// second scan inside one app launch: the scheduler ticks immediately on a
/// cold start and opening the workbench forces another refresh, so that pair
/// costs one round of pages instead of two. See
/// `docs/engine-notes/app-store-page-cache.md` §1 for the measurements this
/// is based on and the wrong assumption an earlier version of this comment
/// made.
///
/// Deliberately caches a *parse failure* (2xx response, nothing either
/// extractor could read) the same as a *parse success* — an unparseable page
/// costs full price again only once per TTL window, not once per check, which
/// is the failure mode this exists to fix (skipping the scrape entirely would
/// instead make the two call sites for a Mac version disagree with each other
/// and with the lookup API, since only one of them would ever get a fresh
/// page). A *transport failure or non-2xx response* is NOT cached: a network
/// blip or a server hiccup must not freeze a bad answer in place for an hour.
/// Callers keep those two outcomes apart before they ever reach this cache —
/// see `MacAppStoreSource.fetchMacVersion`/`fetchMacCompatibility`, whose
/// `PageFetchOutcome.unavailable` case is exactly "don't cache this".
///
/// `cachedVersionFacts`/`cachedCompatibilityFacts` need only a single Optional
/// (not the `MacPageFacts??` an earlier, per-field version of this cache
/// needed): the cached VALUE is a `MacPageFacts` struct, which a page that
/// answered but parsed nothing useful still produces (with nil fields) —
/// there is no "real answer that is itself nil" to distinguish from "no entry
/// yet", the way there was when the cached value type was `MacVersionInfo?`/
/// `Bool?` directly.
public actor AppStorePageCache {

    /// The process-wide cache, and the one production actually uses.
    ///
    /// **Has to outlive the source that reads it.** `AppListModel.makeSources`
    /// rebuilds the whole source stack on every check — deliberately, so a
    /// token change and the signed-in storefront region are re-read — so a
    /// `MacAppStoreSource` lives about seven seconds. A per-instance cache
    /// would be born and destroyed inside a single scan and never survive to
    /// answer the next one. See `docs/engine-notes/app-store-page-cache.md`
    /// §2 for the incident where this was a per-instance cache instead, the
    /// production traffic that didn't move, and why the unit tests didn't
    /// catch it.
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

    /// How long a scraped page stays valid.
    ///
    /// This is a staleness bound, not a tuning knob: the default check
    /// interval is six hours (`Preferences`), longer than this TTL, so in
    /// normal operation the TTL never spans two scheduled scans (see the
    /// class doc's cost model). An iOS-on-Mac listing has no source but this
    /// page, so an hour is how long a user can be told yesterday's answer —
    /// bounded now by `invalidateAll`, which any user-present refresh calls.
    ///
    /// The claim that App Store listings don't change more often than an hour
    /// is UNVERIFIED; nobody has measured it. See
    /// `docs/engine-notes/app-store-page-cache.md` §3 for how this number was
    /// originally chosen and why that reasoning doesn't hold today.
    let ttl: TimeInterval
    private let now: @Sendable () -> Date

    /// Keyed by URL, same as `compatStore` below — and deliberately NOT merged
    /// with it, even though both now hold the same `MacPageFacts` value type.
    /// They are two different pages (`?platform=mac` here, the plain product
    /// page below): Nowdex's `?platform=mac` page has no version shelf at all
    /// while the plain page's own scrape can still answer compatibility, so
    /// collapsing the two stores would make one page's cache miss look like
    /// the other's.
    private var versionStore: [Key: Entry<MacAppStoreSource.MacPageFacts>] = [:]
    private var compatStore: [Key: Entry<MacAppStoreSource.MacPageFacts>] = [:]

    /// Reverse index from an installed app's bundle id to every `(trackId,
    /// region)` key its scrapes have been filed under, so `invalidate(bundleIDs:)`
    /// can drop just that app's entries instead of everyone's. Populated by
    /// `MacAppStoreSource.resolve`, the one call site that has both the
    /// authoritative `app.bundleID` and `result.trackId` in hand — see its doc
    /// comment for why registration lives there and not in the three branches
    /// it dispatches to.
    ///
    /// A bundleID can accumulate more than one key: the home-store and a
    /// fallback-store probe file under different regions, and a Universal
    /// Purchase app can carry two bundleIDs over one trackId (see
    /// `invalidate(bundleIDs:)`).
    private var keysByBundleID: [String: Set<Key>] = [:]

    /// `now` is injectable so tests can advance the clock past `ttl` without a
    /// real sleep.
    init(ttl: TimeInterval = 3600, now: @escaping @Sendable () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    /// Record that `bundleID`'s scrape was filed under `(trackId, region)`, so
    /// a later `invalidate(bundleIDs:)` for this bundleID can find and drop it.
    /// Called once per `resolve()`, regardless of which branch ends up
    /// scraping (or not) — see `MacAppStoreSource.resolve`.
    func note(bundleID: String, trackId: Int, region: String) {
        keysByBundleID[bundleID, default: []].insert(Key(trackId: trackId, region: region))
    }

    /// Drop everything, so the next scrape is live.
    ///
    /// The TTL alone is not enough, and the gap is user-visible. For a
    /// `kind == "software"` listing the scraped page is the ONLY version source
    /// — `iosOnMacVersion` returns nil without it, and unlike `nativeMacVersion`
    /// there is no lookup answer sitting behind it to make a stale page
    /// harmless. So a user who reads a release announcement and presses Check
    /// Now would have been told the same old version for up to an hour, with no
    /// way to insist. Before this cache existed every check re-fetched. Which
    /// installed apps take the `kind == "software"` route specifically is not
    /// something the event log can answer — it does not record which branch of
    /// `resolve` ran.
    ///
    /// Called from the one remaining full-wipe path: a refresh the user asked
    /// for (`RefreshIntent.restartsChangelogs`), which is about to re-check
    /// every app anyway. A periodic sweep must NOT call it — that would put
    /// the cache back to fetching a page per app per round, which is the cost
    /// it exists to remove.
    ///
    /// `recheckMany` used to call this too, and that was a real bug: a single
    /// row's channel-flip recheck wiped every OTHER App Store app's entry, and
    /// the next scheduled sweep paid full price for all of them. See
    /// `docs/engine-notes/app-store-page-cache.md` §4.2 for the measured
    /// incident. `recheckMany` now calls `invalidate(bundleIDs:)` with just
    /// the rows it re-checked instead.
    public func invalidateAll() {
        versionStore.removeAll()
        compatStore.removeAll()
    }

    /// Drop the cached entries for exactly these bundleIDs, so an explicit
    /// per-row recheck (`AppListModel.recheckMany`) scrapes live for the rows
    /// it actually re-checked without paying for every other App Store app's
    /// page too — see `invalidateAll`'s doc comment for the incident this
    /// replaced.
    ///
    /// ⚠️ "Forces a live scrape" only absent an overlapping sweep. A scheduled
    /// check that missed the cache for app X and is still awaiting X's page
    /// when this runs will `storeVersionFacts` a fresh entry afterwards, and the
    /// recheck's own fan-out then reads it — so a recheck racing a sweep can
    /// still be answered from a memo. The window is one page fetch. This is
    /// not new (`invalidateAll` lost the same race) and closing it needs a
    /// per-key generation counter checked in `storeVersionFacts`, which nobody has
    /// written; the guarantee is stated here so the next reader doesn't take
    /// the absolute wording at face value.
    ///
    /// `keysByBundleID`'s own entries are left in place (only the store
    /// entries they point at are cleared), so this doesn't depend on `note`
    /// having run again since the last invalidation. Nothing prunes that index
    /// — not this, not `invalidateAll` — so its real bound is "every MAS
    /// bundleID resolved since launch, times the storefronts probed for it"
    /// (up to 9: the home store plus `MacAppStoreSource.fallbackRegions`,
    /// which is a fixed list of 8 minus the home store if it is one of them —
    /// so 8 keys for a us/cn/hk/tw/jp/sg/kr/gb storefront and 9 for any
    /// other), and an uninstalled app
    /// stays in it for the life of the process. That is memory only, and
    /// trivial at this scale, but it is not the "bounded by the number of
    /// installed MAS apps" this comment used to claim.
    ///
    /// A bundleID with no noted keys (never scraped, or not a MAS app at all)
    /// is a harmless no-op. A Universal Purchase app can have two bundleIDs
    /// sharing one trackId — the iOS and Mac copies of the same purchase — so
    /// invalidating one of them can also drop the other's entry. That is
    /// bounded over-invalidation (costs the other copy one extra fetch on its
    /// next check, nothing more) and is deliberately accepted rather than
    /// tracked per-bundleID, which the store isn't keyed for.
    public func invalidate(bundleIDs: [String]) {
        for id in bundleIDs {
            for key in keysByBundleID[id] ?? [] {
                versionStore[key] = nil
                compatStore[key] = nil
            }
        }
    }

    /// The cached `?platform=mac` page scrape for (trackId, region), if a
    /// fresh entry exists. A single optional is enough now (unlike the earlier
    /// `MacVersionInfo??`/`Bool??` shape this replaced): the cached VALUE is a
    /// `MacPageFacts` struct, which is never itself absent — a page that
    /// answered but parsed nothing useful is still a real `MacPageFacts` (with
    /// nil fields), not a Swift `nil`. So `nil` here means only "not cached
    /// (or expired) — go fetch it".
    func cachedVersionFacts(trackId: Int, region: String) -> MacAppStoreSource.MacPageFacts? {
        let key = Key(trackId: trackId, region: region)
        guard let entry = versionStore[key], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.value
    }

    func storeVersionFacts(_ value: MacAppStoreSource.MacPageFacts, trackId: Int, region: String) {
        versionStore[Key(trackId: trackId, region: region)] = Entry(value: value, fetchedAt: now())
    }

    /// Same shape as `cachedVersionFacts`, for the plain product page.
    func cachedCompatibilityFacts(trackId: Int, region: String) -> MacAppStoreSource.MacPageFacts? {
        let key = Key(trackId: trackId, region: region)
        guard let entry = compatStore[key], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.value
    }

    func storeCompatibilityFacts(_ value: MacAppStoreSource.MacPageFacts, trackId: Int, region: String) {
        compatStore[Key(trackId: trackId, region: region)] = Entry(value: value, fetchedAt: now())
    }
}
