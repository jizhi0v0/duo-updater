import Testing
import Foundation
@testable import DuoUpdaterCore

/// End-to-end coverage for three additive changes to `MacAppStoreSource`:
///
/// - **A1** TTL-memoized product-page scrapes (`AppStorePageCache`), and the
///   rule that a parse failure is cached but a transport failure/non-2xx is
///   not.
/// - **A2** `nativeMacVersion` scraping the lookup's own `trackViewUrl`
///   (validated) instead of always building `.../id{trackId}?platform=mac`,
///   saving the redirect that URL costs — while `iosOnMacVersion`, a different
///   call site for a different listing kind, keeps building its own URL.
/// - **A3** `prewarm(_:)` batching iTunes lookups ahead of the per-app
///   fan-out, purely additively: a hit skips the live per-bundle request, a
///   miss falls through to it unchanged.
///
/// Each test's doc comment names the production line(s) it pins. Every one was
/// run against the described mutation to confirm it goes red — see the task
/// notes for the mutation log.
@Suite(.serialized)
struct MacAppStorePageCacheTests {

    // MARK: - Fixtures

    private static func nativeMacApp(bundleID: String) -> InstalledApp {
        InstalledApp(
            name: "Demo", bundleID: bundleID,
            shortVersion: "1.0.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/Demo.app"),
            isMASApp: true,
            sparkleFeedURL: nil)
    }

    private static let versionPageHTML = """
    <html><script type="application/json" id="shoebox">
    {"data":[{"data":{"shelfMapping":{"mostRecentVersion":{"items":[
      {"primarySubtitle":"Version 2.0.0","text":"What's new"}
    ]}}}}]}
    </script></html>
    """

    private static let unparsablePageHTML = "<html><body>no shelf item here</body></html>"

    private static func lookupJSON(
        version: String, trackId: Int, trackViewUrl: String, kind: String = "mac-software",
        bundleId: String? = nil
    ) -> Data {
        let bundleField = bundleId.map { ",\"bundleId\":\"\($0)\"" } ?? ""
        return Data("""
        {"resultCount":1,"results":[{"version":"\(version)","trackViewUrl":"\(trackViewUrl)",
        "trackId":\(trackId),"kind":"\(kind)","releaseNotes":"notes"\(bundleField)}]}
        """.utf8)
    }

    // MARK: - A1: TTL memoization

    /// Two `latestVersion` calls within the TTL window scrape the product page
    /// only once, and a third call past the TTL scrapes it again.
    ///
    /// Pins `cachedMacVersion` actually consulting `pageCache.cachedVersion`
    /// before calling `fetchMacVersion`, and `AppStorePageCache`'s TTL check.
    /// Mutation run: making `cachedMacVersion` call `fetchMacVersion`
    /// unconditionally (deleting the cache-hit early return) turns the first
    /// assertion red (2 fetches, not 1). Making the TTL check always report
    /// "fresh" turns the second assertion red (still 1 fetch after advancing
    /// past the TTL, not 2).
    @Test func withinTTLThePageIsScrapedOnlyOnce() async throws {
        ScriptedHTTP.reset()
        let trackId = 4001
        let pageURL = "https://apps.apple.com/us/app/-/id\(trackId)?platform=mac"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: "not-a-product-url"))
            }
            if url.absoluteString == pageURL {
                return (200, Data(Self.versionPageHTML.utf8))
            }
            return (404, Data())
        }

        let clock = MutableClock()
        let cache = AppStorePageCache(now: { clock.now })
        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us", pageCache: cache)
        let app = Self.nativeMacApp(bundleID: "com.example.ttl")

        _ = try await source.latestVersion(for: app)
        _ = try await source.latestVersion(for: app)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == pageURL }) == 1)

        clock.now = clock.now.addingTimeInterval(3601)  // past the 1-hour default TTL
        _ = try await source.latestVersion(for: app)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == pageURL }) == 2)
    }

    /// A 2xx page that fails to parse a version IS cached (one fetch across two
    /// calls); a transport failure is NOT cached (fetched again every call).
    ///
    /// Pins the `PageFetchOutcome` split in `fetchMacVersion`/`cachedMacVersion`.
    /// Mutation run: wrapping `cachedMacVersion`'s switch in a `do`/`catch` that
    /// swallows the transport exception and caches nil too turns the second
    /// assertion red (1 fetch instead of 2 for the transport-failure case).
    /// Dropping the `storeVersion` call in the `.success` branch (never caching
    /// a parse result) turns the first assertion red (2 fetches instead of 1
    /// for the parse-failure case).
    @Test func parseFailureIsCachedButTransportFailureIsNot() async throws {
        ScriptedHTTP.reset()
        let unparsableTrackId = 4101
        let failingTrackId = 4102
        let unparsableBundleID = "com.example.unparsable"
        let failingBundleID = "com.example.failing"
        let unparsableURL = "https://apps.apple.com/us/app/-/id\(unparsableTrackId)?platform=mac"
        let failingURL = "https://apps.apple.com/us/app/-/id\(failingTrackId)?platform=mac"

        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                let bundleId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "bundleId" }?.value
                let trackId = (bundleId == unparsableBundleID) ? unparsableTrackId : failingTrackId
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: "not-a-product-url"))
            }
            if url.absoluteString == unparsableURL {
                return (200, Data(Self.unparsablePageHTML.utf8))
            }
            if url.absoluteString == failingURL {
                return nil  // transport failure
            }
            return (404, Data())
        }

        let cache = AppStorePageCache(now: { Date(timeIntervalSince1970: 0) })
        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us", pageCache: cache)

        let unparsableApp = Self.nativeMacApp(bundleID: unparsableBundleID)
        _ = try await source.latestVersion(for: unparsableApp)
        _ = try await source.latestVersion(for: unparsableApp)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == unparsableURL }) == 1)

        let failingApp = Self.nativeMacApp(bundleID: failingBundleID)
        _ = try await source.latestVersion(for: failingApp)
        _ = try await source.latestVersion(for: failingApp)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == failingURL }) == 2)
    }

    // MARK: - A2: trackViewUrl shortcut

    /// `nativeMacVersion` scrapes the lookup's `trackViewUrl` instead of
    /// building `.../id{trackId}?platform=mac`, when it validates.
    ///
    /// Pins the one call site A2 touches. Mutation run: reverting
    /// `nativeMacVersion` to always build its own URL (ignore `trackViewUrl`)
    /// turns this red — the constructed URL gets hit (count 1) and
    /// `trackViewUrl` doesn't (count 0), the opposite of both assertions here.
    @Test func nativeMacVersionScrapesTrackViewUrl() async throws {
        ScriptedHTTP.reset()
        let trackId = 4201
        let trackViewURL = "https://apps.apple.com/us/app/demo/id\(trackId)?mt=12"
        let constructedURL = "https://apps.apple.com/us/app/-/id\(trackId)?platform=mac"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: trackViewURL))
            }
            if url.absoluteString == trackViewURL { return (200, Data(Self.versionPageHTML.utf8)) }
            return (404, Data())
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        _ = try await source.latestVersion(for: Self.nativeMacApp(bundleID: "com.example.usestrackviewurl"))

        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == trackViewURL }) == 1)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == constructedURL }) == 0)
    }

    /// `iosOnMacVersion` (the `kind == "software"` call site) must keep
    /// building its own Mac product-page URL — that listing's `trackViewUrl`
    /// has no `mt=12` and points at the iOS listing, not the Mac one (see its
    /// doc comment).
    ///
    /// Pins that A2 did NOT touch this call site. Mutation run: changing
    /// `iosOnMacVersion` to also prefer `trackViewUrl` turns this red — it
    /// would hit `trackViewUrl` (count 1, expected 0) instead of the
    /// constructed URL (count 0, expected 1).
    @Test func iosOnMacVersionIgnoresTrackViewUrl() async throws {
        ScriptedHTTP.reset()
        let trackId = 4301
        // Per the recorded fact: a "software" listing's trackViewUrl has no
        // mt=12 and lands on the iOS listing — modeled here with `?uo=4`.
        let trackViewURL = "https://apps.apple.com/us/app/demo/id\(trackId)?uo=4"
        let constructedURL = "https://apps.apple.com/us/app/-/id\(trackId)?platform=mac"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(
                    version: "9.9.9-ios", trackId: trackId, trackViewUrl: trackViewURL, kind: "software"))
            }
            if url.absoluteString == constructedURL { return (200, Data(Self.versionPageHTML.utf8)) }
            return (404, Data())
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        let app = InstalledApp(
            name: "Demo", bundleID: "com.example.iosonmac",
            shortVersion: "1.0.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/Demo.app"),
            isMASApp: true, isiOSAppOnMac: false,
            sparkleFeedURL: nil)
        _ = try await source.latestVersion(for: app)

        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == constructedURL }) == 1)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == trackViewURL }) == 0)
    }

    /// A `trackViewUrl` whose host isn't `apps.apple.com` — network-sourced,
    /// untrusted — must not be fetched; `nativeMacVersion` falls back to the
    /// constructed URL.
    ///
    /// Pins `validatedProductPageURL`'s scheme/host check. Mutation run:
    /// removing that check (trusting `trackViewUrl` unconditionally) turns
    /// this red — the untrusted host gets a request.
    @Test func untrustedTrackViewUrlHostFallsBackToConstructedURL() async throws {
        ScriptedHTTP.reset()
        let trackId = 4401
        let evilURL = "https://evil.example.com/id\(trackId)"
        let constructedURL = "https://apps.apple.com/us/app/-/id\(trackId)?platform=mac"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: evilURL))
            }
            if url.absoluteString == constructedURL { return (200, Data(Self.versionPageHTML.utf8)) }
            return (404, Data())
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        _ = try await source.latestVersion(for: Self.nativeMacApp(bundleID: "com.example.evilhost"))

        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == constructedURL }) == 1)
        #expect(ScriptedHTTP.count(matching: { $0.host == "evil.example.com" }) == 0)
    }

    /// A `trackViewUrl` on the right HOST but naming a DIFFERENT listing is
    /// refused too.
    ///
    /// The host check alone let this through, and the consequence is the worst
    /// failure this file guards: Apple hands back the app's iOS listing for a
    /// `mac-software` lookup, we scrape it, and `nativeMacVersion` prefers the
    /// page whenever it is strictly newer. An iOS track runs far ahead of a Mac
    /// one (Discord's iOS listing reports 343.x), so the row would show an
    /// update that can never be installed — and the page cache would hold it
    /// for an hour. Nothing about it looks like an error.
    ///
    /// Mutation run: dropping the `url.path.contains("id\(trackId)")` guard in
    /// `validatedProductPageURL` turns this red — the foreign listing gets the
    /// request and the constructed URL gets none.
    @Test func trackViewUrlNamingAnotherListingFallsBackToConstructedURL() async throws {
        ScriptedHTTP.reset()
        let trackId = 4801
        let foreignURL = "https://apps.apple.com/us/app/some-other-app/id999999"
        let constructedURL = "https://apps.apple.com/us/app/-/id\(trackId)?platform=mac"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: foreignURL))
            }
            if url.absoluteString == constructedURL { return (200, Data(Self.versionPageHTML.utf8)) }
            return (404, Data())
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        _ = try await source.latestVersion(for: Self.nativeMacApp(bundleID: "com.example.foreignlisting"))

        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == constructedURL }) == 1,
                "the constructed URL must be used when trackViewUrl names another listing")
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == foreignURL }) == 0,
                "a URL naming a different trackId must never be scraped")
    }

    /// SAME trackId, no platform marker — the case that actually happens.
    ///
    /// A Universal Purchase app's iOS and Mac listings share one trackId and
    /// differ only by the query, so an id check cannot tell them apart. The
    /// first version of this guard compared ids and shipped believing it had
    /// closed the class; it had not. Measured 2026-09-05: `id1465439395`
    /// (Dark Noise) answers 3.5.2 on its default page and 3.4.3 under
    /// `?platform=mac`. The iOS track being AHEAD is what makes it dangerous —
    /// `nativeMacVersion` prefers a strictly-newer page, so the row would offer
    /// a version the Mac copy can never install, cached for an hour.
    ///
    /// Mutation run: dropping the `mt=12`/`platform=mac` query check turns this
    /// red (the unmarked URL gets scraped) while
    /// `trackViewUrlNamingAnotherListingFallsBackToConstructedURL` stays green —
    /// which is exactly how the gap survived the first fix.
    @Test func trackViewUrlWithoutAPlatformMarkerFallsBackToConstructedURL() async throws {
        ScriptedHTTP.reset()
        let trackId = 4901
        // Same id, right host, no `mt=12` — an iOS listing for a Universal
        // Purchase app looks exactly like this.
        let iosListingURL = "https://apps.apple.com/us/app/demo/id\(trackId)?uo=4"
        let constructedURL = "https://apps.apple.com/us/app/-/id\(trackId)?platform=mac"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: iosListingURL))
            }
            if url.absoluteString == constructedURL { return (200, Data(Self.versionPageHTML.utf8)) }
            return (404, Data())
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        _ = try await source.latestVersion(for: Self.nativeMacApp(bundleID: "com.example.universalpurchase"))

        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == constructedURL }) == 1,
                "a trackViewUrl with no Mac platform marker must not be trusted")
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == iosListingURL }) == 0,
                "scraping the unmarked listing is the phantom-update bug")
    }

    /// A `trackViewUrl` for ANOTHER storefront is refused.
    ///
    /// Right host, right id, right marker — wrong store. The scrape is filed in
    /// `AppStorePageCache` under the caller's `region`, so trusting this would
    /// pin one storefront's answer for an hour under another's key. Third and
    /// last way into the same failure, after host and platform.
    ///
    /// Mutation run: dropping the `segments.first == region` guard turns this
    /// red — the foreign storefront gets scraped.
    @Test func trackViewUrlForAnotherStorefrontFallsBackToConstructedURL() async throws {
        ScriptedHTTP.reset()
        let trackId = 5101
        let foreignStore = "https://apps.apple.com/jp/app/demo/id\(trackId)?mt=12"
        let constructedURL = "https://apps.apple.com/us/app/-/id\(trackId)?platform=mac"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: foreignStore))
            }
            if url.absoluteString == constructedURL { return (200, Data(Self.versionPageHTML.utf8)) }
            return (404, Data())
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        _ = try await source.latestVersion(for: Self.nativeMacApp(bundleID: "com.example.wrongstore"))

        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == constructedURL }) == 1)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == foreignStore }) == 0,
                "a URL for another storefront must never be scraped")
    }

    /// `invalidateAll` really makes the next scrape live.
    ///
    /// This is what an explicit recheck relies on: for an iOS-on-Mac listing the
    /// page is the only version source, so without a way to clear it the user
    /// pressing Check Now is told the same thing for up to an hour.
    ///
    /// Mutation run: making `invalidateAll` a no-op turns this red (1 fetch, not 2).
    @Test func invalidateAllForcesTheNextScrapeLive() async throws {
        ScriptedHTTP.reset()
        let trackId = 5201
        let pageURL = "https://apps.apple.com/us/app/demo/id\(trackId)?mt=12"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: pageURL))
            }
            if url.absoluteString == pageURL { return (200, Data(Self.versionPageHTML.utf8)) }
            return (404, Data())
        }
        let cache = AppStorePageCache()
        let app = Self.nativeMacApp(bundleID: "com.example.invalidate")
        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us", pageCache: cache)

        _ = try await source.latestVersion(for: app)
        _ = try await source.latestVersion(for: app)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == pageURL }) == 1,
                "the second call inside the TTL must be served from cache")

        await cache.invalidateAll()
        _ = try await source.latestVersion(for: app)
        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == pageURL }) == 2,
                "after invalidateAll the page must be fetched again")
    }

    // MARK: - A3: prewarm

    /// After `prewarm([app])`, resolving that same app must not make a second,
    /// single-bundle lookup request — the batched one from `prewarm` already
    /// answered it.
    ///
    /// Pins `lookup(bundleID:region:)` consulting `prewarmCache` before making
    /// its own request. Mutation run: deleting that early-return (falling
    /// through unconditionally) turns this red — total itunes.apple.com request
    /// count goes to 2 instead of staying at 1.
    @Test func prewarmedAppSkipsIndividualLookup() async throws {
        ScriptedHTTP.reset()
        let trackId = 4501
        let bundleID = "com.example.prewarmed"
        ScriptedHTTP.serve { request in
            guard let url = request.url, url.host == "itunes.apple.com" else { return nil }
            let bundleIdParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "bundleId" }?.value ?? ""
            guard bundleIdParam.split(separator: ",").map(String.init).contains(bundleID) else {
                return (200, Data("{\"resultCount\":0,\"results\":[]}".utf8))
            }
            return (200, Self.lookupJSON(
                version: "1.5.0", trackId: trackId, trackViewUrl: "not-a-product-url", bundleId: bundleID))
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        let app = Self.nativeMacApp(bundleID: bundleID)

        // The count is checked AFTER the lookup, not between: `prewarm` returns
        // once the batch is started, so counting here would be racing it. The
        // assertion is the same one either way — one iTunes request in total,
        // the batch, with the per-app lookup served from its answer.
        await source.prewarm([app])
        let remote = try await source.latestVersion(for: app)
        #expect(remote?.shortVersion == "1.5.0")
        #expect(ScriptedHTTP.count(matching: { $0.host == "itunes.apple.com" }) == 1)  // no new lookup request
    }

    /// An app `prewarm` never saw still resolves via the normal live lookup —
    /// the additive design's other half: a miss must fall through unchanged.
    ///
    /// Pins that `lookup(bundleID:region:)`'s existing body still runs on a
    /// cache miss. Mutation run: making a prewarm-cache miss return nil instead
    /// of falling through turns this red — `remote` comes back nil and no
    /// lookup request is made.
    @Test func uncoveredAppFallsThroughToLiveLookup() async throws {
        ScriptedHTTP.reset()
        let trackId = 4601
        let bundleID = "com.example.notprewarmed"
        ScriptedHTTP.serve { request in
            guard let url = request.url, url.host == "itunes.apple.com" else { return nil }
            return (200, Self.lookupJSON(
                version: "1.5.0", trackId: trackId, trackViewUrl: "not-a-product-url", bundleId: bundleID))
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        let app = Self.nativeMacApp(bundleID: bundleID)

        // `prewarm` deliberately never called for this app/source.
        let remote = try await source.latestVersion(for: app)
        #expect(remote?.shortVersion == "1.5.0")
        #expect(ScriptedHTTP.count(matching: { $0.host == "itunes.apple.com" }) == 1)
    }

    /// A REBUILT source stack still sees the cached page.
    ///
    /// This is the case whose absence let the original bug ship. The two TTL
    /// cases above exercise one `MacAppStoreSource` twice and the rest make a
    /// single call each — so nothing here ever built a SECOND source, which is
    /// the only thing that would have caught it. (An earlier version of this
    /// comment said all seven reused a source; only two do.) Production never
    /// reuses one: `AppListModel.makeSources`
    /// rebuilds the whole stack on every check (deliberately, so a token
    /// change and the storefront region are re-read), so the source that
    /// scraped a page is gone by the next scan. With a per-instance cache the
    /// one-hour TTL therefore never spanned two scans, and the product-page
    /// traffic did not drop at all in production (measured 2026-09-04:
    /// 20.6 → 23.6 requests per round, 623 → 786 KB) while every other change
    /// in the same batch landed exactly as predicted.
    ///
    /// So this constructs the source the way production does — twice, with the
    /// DEFAULT cache — rather than reusing one. `trackId` is unique to this
    /// test because that default is process-wide.
    ///
    /// Mutation run: restoring `pageCache ?? AppStorePageCache(...)` as the
    /// default turns this red (2 page fetches, not 1) and leaves every other
    /// test in this file green — which is precisely the asymmetry that made
    /// the bug invisible.
    @Test func aRebuiltSourceStackStillSeesTheCachedPage() async throws {
        ScriptedHTTP.reset()
        let trackId = 4701
        let trackViewURL = "https://apps.apple.com/us/app/demo/id\(trackId)?mt=12"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(version: "1.5.0", trackId: trackId, trackViewUrl: trackViewURL))
            }
            if url.absoluteString == trackViewURL { return (200, Data(Self.versionPageHTML.utf8)) }
            return (404, Data())
        }
        let app = Self.nativeMacApp(bundleID: "com.example.rebuiltstack")

        // Two separate stacks, exactly as two consecutive checks build them.
        _ = try await MacAppStoreSource(session: ScriptedHTTP.session(), region: "us")
            .latestVersion(for: app)
        _ = try await MacAppStoreSource(session: ScriptedHTTP.session(), region: "us")
            .latestVersion(for: app)

        #expect(ScriptedHTTP.count(matching: { $0.absoluteString == trackViewURL }) == 1,
                "the second stack re-scraped the page — the cache did not outlive the source")
    }

    /// The batch must ask for the SAME language the single lookup would.
    ///
    /// This is the interaction that a merge nearly shipped: `main` grew a
    /// `lang=` parameter so `trackName` comes back localised — the name
    /// `AppStoreAXInstaller` matches against what App Store.app draws on screen
    /// — while this branch grew a batched prewarm that fills the cache the
    /// single path reads. Resolve the textual conflict by keeping both hunks and
    /// every prewarmed app silently gets the storefront's default name on a
    /// non-English Mac: nothing throws, no version changes, the App Store
    /// install route just stops finding its button.
    ///
    /// Mutation run: dropping the `lang` query item from `batchLookup` turns
    /// this red. Dropping `lang` from `AppStoreLookupCache.Key` does not — that
    /// one is covered by `aPrewarmUnderOneLanguageIsNotServedToAnother`.
    @Test func theBatchAsksForTheSameLanguageAsTheSingleLookup() async throws {
        ScriptedHTTP.reset()
        let bundleID = "com.example.localised"
        ScriptedHTTP.serve { request in
            guard let url = request.url else { return nil }
            if url.host == "itunes.apple.com" {
                return (200, Self.lookupJSON(
                    version: "1.0", trackId: 5001, trackViewUrl: "not-a-product-url",
                    bundleId: bundleID))
            }
            return (404, Data())
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        // `prewarm` returns once the batch is STARTED, so drive a lookup to
        // join it — which is what the fan-out does, and the only way a caller
        // can observe the batch at all now that it is not awaited in place.
        let app = Self.nativeMacApp(bundleID: bundleID)
        await source.prewarm([app])
        _ = try await source.latestVersion(for: app)

        let expected = MacAppStoreSource.storeLanguage(
            preferred: Locale.preferredLanguages, storefront: "us")
        if let expected {
            #expect(ScriptedHTTP.count(matching: {
                $0.host == "itunes.apple.com" && ($0.query ?? "").contains("lang=\(expected)")
            }) >= 1, "the batched lookup dropped the lang the single lookup sends")
        } else {
            #expect(ScriptedHTTP.count(matching: {
                $0.host == "itunes.apple.com" && ($0.query ?? "").contains("lang=")
            }) == 0, "no language could be named, so the batch must not invent one")
        }
    }

    /// A prewarm fetched under one language is not served to another.
    ///
    /// Mutation run: removing `lang` from `AppStoreLookupCache.Key` turns this
    /// red — the entry stored under one language answers a lookup for another.
    @Test func aPrewarmUnderOneLanguageIsNotServedToAnother() async throws {
        // ⚠️ Store a REAL entry. The first version passed `[:]`, and `store`
        // iterates its argument — so it wrote nothing, `lookup` returned nil
        // whatever the key looked like, and the mutation this case names could
        // never redden it. It was the only coverage `Key.lang` had.
        let cache = AppStoreLookupCache()
        await cache.store(["com.example.x": nil], region: "us", lang: "zh_cn")
        #expect(await cache.lookup(bundleID: "com.example.x", region: "us", lang: "zh_cn") != nil,
                "the entry must answer for the language it was fetched under")
        #expect(await cache.lookup(bundleID: "com.example.x", region: "us", lang: "en_us") == nil,
                "an entry keyed on one language must not answer for another")
    }

    /// `prewarm` must NOT wait for its own batch.
    ///
    /// `UpdateChecker` drains prewarm before the per-app fan-out, so anything
    /// this call waits on is waited on by every GitHub, Sparkle and Homebrew row
    /// too. With a 15 s request timeout that made an unreachable
    /// itunes.apple.com strictly worse than not having the optimisation — the
    /// one thing it must never be. The batch is registered instead, and
    /// `lookup` joins it, so only the rows that would otherwise pay for their
    /// own lookup pay its latency.
    ///
    /// Mutation run: awaiting the task inside `prewarm` (instead of registering
    /// it) turns this red — `prewarm` no longer returns before the request
    /// lands.
    @Test func prewarmDoesNotBlockOnItsOwnBatch() async throws {
        ScriptedHTTP.reset()
        let bundleID = "com.example.nonblocking"
        let gate = AsyncGate()
        ScriptedHTTP.serve { request in
            guard let url = request.url, url.host == "itunes.apple.com" else { return nil }
            gate.markRequestStarted()
            return (200, Self.lookupJSON(
                version: "1.0", trackId: 5301, trackViewUrl: "not-a-product-url", bundleId: bundleID))
        }

        let source = MacAppStoreSource(session: ScriptedHTTP.session(), region: "us",
                                       pageCache: AppStorePageCache())
        await source.prewarm([Self.nativeMacApp(bundleID: bundleID)])
        // If `prewarm` awaited the batch, the request would necessarily have
        // been served by now. Returning before it is the property under test.
        #expect(!gate.requestFinishedBeforePrewarmReturned,
                "prewarm waited for its own batch — the fan-out is blocked behind it again")
    }

    /// Records whether the scripted request had already been served at the
    /// moment `prewarm` returned. A plain counter would race; this only ever
    /// moves one way and is read after the fact.
    final class AsyncGate: @unchecked Sendable {
        private let lock = NSLock()
        private var started = false
        func markRequestStarted() { lock.lock(); started = true; lock.unlock() }
        var requestFinishedBeforePrewarmReturned: Bool {
            lock.lock(); defer { lock.unlock() }; return started
        }
}

// MARK: - Test doubles

/// A mutable box for `AppStorePageCache`'s injected `now`, so a test can
/// advance the clock past the TTL without a real sleep.
private final class MutableClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 0)
}

/// A scriptable `URLProtocol`: `serve` installs a handler that inspects each
/// request and returns `(statusCode, body)`, or nil to simulate a transport
/// failure. Every request URL is recorded, queryable via `count(matching:)`,
/// so tests can assert exactly which endpoints were (or weren't) hit.
private final class ScriptedHTTP: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> (Int, Data)?)?
    nonisolated(unsafe) private static var calls: [URL] = []

    static func reset() {
        lock.lock(); handler = nil; calls = []; lock.unlock()
    }

    static func serve(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)?) {
        lock.lock(); Self.handler = handler; lock.unlock()
    }

    static func count(matching predicate: (URL) -> Bool) -> Int {
        lock.lock(); let snapshot = calls; lock.unlock()
        return snapshot.filter(predicate).count
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedHTTP.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        if let url = request.url { Self.calls.append(url) }
        let handler = Self.handler
        Self.lock.unlock()

        guard let url = request.url, let result = handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}



    }
}
