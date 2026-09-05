import Foundation

/// TTL-memoized cache for the two things `MacAppStoreSource` scrapes off an App
/// Store product page: the Mac-track version (+ "What's New" notes) and the
/// `isIOSBinaryMacOSCompatible` flag.
///
/// **All of the value is across scans, none of it within one.** An earlier
/// version of this comment claimed the pages are "read from more than one call
/// site per app per check" and justified the class on that. They are not:
/// `resolve()` is a three-way dispatch with early returns, so exactly one of
/// `nativeMacVersion` / `remoteVersion(checkMacCompat:)` / `iosOnMacVersion`
/// runs per app per check — and the version and compatibility pages use
/// different URLs *and* different dictionaries, so neither can serve the other.
///
/// What this actually removes is the SECOND scan's fetch, and the third's, up
/// to the TTL. Which means the benefit is `1 − interval / ttl` and nothing
/// else: at a five-minute interval eleven rounds in twelve are free (measured:
/// 23.6 → 3.0 product-page requests a round), and at the six-hour default —
/// which is what most installs run — an interval longer than the TTL means
/// **every round is a cold miss and this class saves nothing at all**. What it
/// still buys there is the second scan of an app launch: the scheduler ticks
/// immediately on a cold start and opening the workbench forces another
/// refresh, so the pair costs one round of pages instead of two.
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

    /// How long a scraped page stays valid.
    ///
    /// ⚠️ One hour was chosen on a machine set to check every five minutes, and
    /// an earlier version of this comment wrote that setting down as a property
    /// of the product ("a scan revisits the same app every few minutes"). It is
    /// not: the default is six hours (`Preferences`), and at that interval this
    /// TTL never spans two scans. The number is a staleness bound, not a
    /// tuning: an iOS-on-Mac listing has no source but this page, so an hour is
    /// how long a user can be told yesterday's answer — bounded now by
    /// `invalidateAll`, which any user-present refresh calls.
    ///
    /// The claim that App Store listings don't change more often than an hour is
    /// UNVERIFIED; nobody has measured it.
    let ttl: TimeInterval
    private let now: @Sendable () -> Date

    private var versionStore: [Key: Entry<MacAppStoreSource.MacVersionInfo?>] = [:]
    private var compatStore: [Key: Entry<Bool?>] = [:]

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
    /// way to insist. Before this cache existed every check re-fetched. The
    /// machine this was measured on has 21 Mac App Store apps that scrape a
    /// product page (counted 2026-09-05 off the event store, `select
    /// count(distinct app_id) ... where host='apps.apple.com'`); an earlier
    /// version of this sentence said twenty. How many of those take the
    /// `kind == "software"` route specifically is UNVERIFIED — the events do
    /// not record which branch of `resolve` ran.
    ///
    /// Called from the one remaining full-wipe path: a refresh the user asked
    /// for (`RefreshIntent.restartsChangelogs`), which is about to re-check
    /// every app anyway. A periodic sweep must NOT call it — that would put
    /// the cache back to fetching a page per app per round, which is the cost
    /// it exists to remove.
    ///
    /// `recheckMany` used to call this too, and that was the bug: measured
    /// 2026-09-05 in a live 45-minute window, a single row's channel flip
    /// (`recheckChannelSwitches` → `recheckMany`, 3 requests, 1 app) wiped
    /// every OTHER App Store app's entry, and the next scheduled sweep paid
    /// for it — 21/21 apps re-scraped, 975 KB and 52 extra requests where
    /// every other steady-state round cost ~0. `recheckMany` now calls
    /// `invalidate(bundleIDs:)` with just the rows it re-checked instead.
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
    /// when this runs will `storeVersion` a fresh entry afterwards, and the
    /// recheck's own fan-out then reads it — so a recheck racing a sweep can
    /// still be answered from a memo. The window is one page fetch. This is
    /// not new (`invalidateAll` lost the same race) and closing it needs a
    /// per-key generation counter checked in `storeVersion`, which nobody has
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
