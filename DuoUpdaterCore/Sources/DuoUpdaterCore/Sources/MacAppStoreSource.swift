import Foundation

/// Resolves updates for Mac App Store apps via the public iTunes lookup API.
/// We can't install MAS updates ourselves (that's the App Store's job, and the
/// binary is DRM-bound to the purchasing Apple ID), so the result carries a
/// product link plus region info for the UI to act on.
public struct MacAppStoreSource: UpdateSource {
    public let name = "App Store"

    /// The one source that may. It IS the store's own lookup, so answering a
    /// store copy is the whole job rather than a cross-distribution offer — and
    /// `latestVersion(for:)` below already declines everything that is NOT a
    /// store copy, so the two halves meet exactly.
    public let answersAppStoreCopies = true

    private let session: URLSession
    /// The signed-in account's storefront region — what the App Store will
    /// actually let the user install.
    private let homeRegion: String
    /// Extra storefronts to probe only when the app isn't in the home store.
    private let fallbackRegions: [String]
    /// TTL-memoized product-page scrapes (Mac version + notes, Mac-compat flag).
    /// See `AppStorePageCache` for why a parse failure is cached but a transport
    /// failure isn't.
    private let pageCache: AppStorePageCache
    /// Short-TTL store for `prewarm(_:)`'s batched lookups. `lookup(bundleID:region:)`
    /// consults it first and falls through to its normal live request on a miss —
    /// see `AppStoreLookupCache`.
    private let prewarmCache = AppStoreLookupCache()

    public init(
        session: URLSession = .updates,
        region: String? = nil,
        pageCache: AppStorePageCache? = nil
    ) {
        self.session = session
        let home = region
            ?? AppStoreStorefront.currentCountry()
            ?? Locale.current.region?.identifier.lowercased()
            ?? "us"
        self.homeRegion = home
        // Probed only for zero-result apps, first match wins, so the common
        // case stays at one request per app.
        let common = ["us", "cn", "hk", "tw", "jp", "sg", "kr", "gb"]
        self.fallbackRegions = common.filter { $0 != home }
        // `.shared`, not a fresh instance: the source stack is rebuilt every
        // check, so a per-instance cache would die with it and the TTL would
        // never span two scans. See `AppStorePageCache.shared`.
        self.pageCache = pageCache ?? .shared
    }

    /// Batch-fetch lookups for every installed MAS app's home-store storefront
    /// before the main per-app fan-out starts, so most of those apps' `lookup()`
    /// calls hit `prewarmCache` instead of making their own request. Purely
    /// additive: a chunk that fails to fetch, or an app this never covers (a
    /// fallback-region probe, or a recheck that skips `prewarm` entirely), just
    /// falls through to the unchanged per-bundle path in `lookup(bundleID:region:)`.
    /// ⚠️ **Returns as soon as the work is STARTED, not finished.** It used to
    /// await it, and `UpdateChecker` drains this before its per-app fan-out —
    /// so an unreachable itunes.apple.com put a 15 s timeout in front of every
    /// GitHub, Sparkle and Homebrew row too. Before this hook existed that
    /// timeout delayed only the App Store rows, and in parallel with the rest;
    /// blocking here was strictly worse than not having the optimisation at
    /// all, which is the one thing it must never be.
    ///
    /// The batch is registered with `prewarmCache` instead, and
    /// `lookup(bundleID:region:)` awaits it before reading (the actual wait
    /// happens in `AppStoreLookupCache.awaitInFlight`). Registering — rather
    /// than awaiting — is what removes the global barrier this hook used to
    /// put in front of every source. So a slow batch no longer delays a
    /// GitHub or Sparkle row that never touches this cache. It does NOT give
    /// App Store rows an isolated queue: `UpdateChecker` runs the whole
    /// fan-out under one shared bounded-concurrency window, and a row
    /// waiting here still occupies one of that window's slots, the same as
    /// any other in-flight check would.
    public func prewarm(_ apps: [InstalledApp]) async {
        let bundleIDs = Array(Set(apps.compactMap { $0.isMASApp ? $0.bundleID : nil }))
        guard !bundleIDs.isEmpty else { return }
        // Chunks run CONCURRENTLY, and that is still not a micro-optimisation
        // — just not for the old reason. It no longer keeps a chunk's timeout
        // out of the main fan-out's way; `prewarm` already does that above by
        // registering `work` below rather than awaiting it — whether a chunk's
        // request happens to land first is neither ordered nor relevant, which
        // is the whole point. What concurrency still buys is how long
        // `work` itself takes to finish: `lookup(bundleID:region:)` awaits
        // exactly this Task (via `AppStoreLookupCache.awaitInFlight`), and
        // every App Store row doing so occupies one of `UpdateChecker`'s
        // shared concurrency slots for as long as it waits. At 15 s per
        // request and 30 MAS apps, a sequential loop would need two chunks —
        // up to 30 s for `work` to finish — twice as long as running them at
        // once, and that difference is spent by App Store rows (and whatever
        // else queues behind them for a free slot) waiting rather than being
        // checked.
        // Resolved once, exactly as `lookup(bundleID:region:)` resolves it, and
        // carried into both the request and the cache key.
        let lang = await LanguageSupport.shared.isRejected
            ? nil
            : Self.storeLanguage(preferred: Locale.preferredLanguages, storefront: homeRegion)
        // Unstructured on purpose: it must outlive this call. It inherits the
        // task-locals of this scope (where `RequestAttribution.appID` is nil,
        // which is what `batchLookup` wants) but not its lifetime.
        let work = Task { [self] in
        await withTaskGroup(of: (region: String, lang: String?, batch: [String: LookupResult?])?.self) { group in
            for chunk in Self.chunked(bundleIDs, size: 20) {
                group.addTask {
                    do {
                        return (self.homeRegion, lang, try await self.batchLookup(
                            bundleIDs: chunk, region: self.homeRegion, lang: lang))
                    } catch {
                        // Say so. A silently skipped batch is indistinguishable
                        // from a working one: every app just falls through to
                        // its own lookup and the only symptom is traffic that
                        // never dropped — the same shape as the prune bug that
                        // already cost a measurement round to find.
                        Log.source.error(
                            "App Store prewarm: batch of \(chunk.count, privacy: .public) failed — \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }
            for await result in group {
                guard let result else { continue }
                await prewarmCache.store(result.batch, region: result.region, lang: result.lang)
            }
        }
        }
        await prewarmCache.register(work)
    }

    /// Drops `pageCache` entries for exactly `apps` — the array `UpdateChecker`
    /// is about to check, and nothing more. Uses this source's own `pageCache`
    /// (not `.shared`): tests inject a cache into `init(pageCache:)`, and a
    /// caller that reached for `.shared` here would clear a different object
    /// than `latestVersion(for:)` actually reads, silently doing nothing.
    public func invalidateMemo(for apps: [InstalledApp]) async {
        await pageCache.invalidate(bundleIDs: apps.compactMap(\.bundleID))
    }

    private static func chunked(_ items: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [items] }
        return stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // Only applies to apps actually installed from the Mac App Store.
        guard app.isMASApp, let bundleID = app.bundleID else { return nil }

        // Try the user's own store first (the common case).
        if let result = try await lookup(bundleID: bundleID, region: homeRegion) {
            return try await resolve(result: result, app: app, region: homeRegion)
        }
        // Not in the home store — probe fallback storefronts; first hit wins.
        for region in fallbackRegions {
            if let result = try await lookup(bundleID: bundleID, region: region),
               let resolved = try await resolve(result: result, app: app, region: region) {
                return resolved
            }
        }
        return nil
    }

    /// Turn a lookup hit into a `RemoteVersion`, routing by listing kind. Shared
    /// by the home-store and fallback-store paths.
    private func resolve(result: LookupResult, app: InstalledApp, region: String) async throws -> RemoteVersion? {
        // Registered here, once, rather than in each of the three branches
        // below: this is the one place that holds both the authoritative
        // `app.bundleID` (NOT `result.bundleId` — see its doc comment, it's
        // ambiguous whether that's populated on the single-lookup path) and
        // `result.trackId`, and all three branches are dispatched from here.
        // Registering for a branch that never ends up scraping a page is a
        // harmless no-op — `invalidate(bundleIDs:)` on a bundleID with no
        // stored entries does nothing.
        if let bundleID = app.bundleID, let trackId = result.trackId {
            await pageCache.note(bundleID: bundleID, trackId: trackId, region: region)
        }
        // Native Mac listing: trust the lookup version, but cross-check the
        // product page and keep whichever is newer. Apple's per-storefront lookup
        // cache can lag a freshly-shipped build that the page already shows
        // (observed: Excel 16.109.3 live on the cn page while the cn lookup still
        // returned 16.109.2), which silently hid real updates.
        if result.isNativeMac {
            return try await nativeMacVersion(from: result, region: region)
        }
        // Wrapped iPhone/iPad app: the installed binary IS the iOS build, so the
        // lookup `version` is the right track — take it directly (with a Mac-compat
        // check, since a newer build can drop Mac support).
        if app.isiOSAppOnMac {
            return try await remoteVersion(from: result, region: region, checkMacCompat: true)
        }
        // iOS-on-Mac (kind == "software") whose Mac build is a separate release
        // line from the iOS track the lookup reports: scrape the Mac product page
        // for the platform-specific version instead.
        if let trackId = result.trackId {
            return try await iosOnMacVersion(trackId: trackId, lookupResult: result, region: region)
        }
        return nil
    }

    /// Resolve a native Mac app's latest version, cross-checking the lookup API
    /// against the product page (often fresher per storefront) and keeping the
    /// newer of the two. A page-scrape failure just leaves us on the lookup value.
    private func nativeMacVersion(from result: LookupResult, region: String) async throws -> RemoteVersion? {
        let lookupVersion = result.version
        var facts: MacPageFacts?
        if let trackId = result.trackId {
            // The lookup's own `trackViewUrl` for a `mac-software` listing already
            // lands on this same page with zero redirects (measured: 8/8, version
            // identical to the constructed `?platform=mac` URL) — using it saves
            // the 301 the constructed URL otherwise costs every scrape. It's
            // network-sourced, so it's validated before use; a URL that fails the
            // check (or is missing) falls back to the constructed URL exactly as
            // before. Only this call site does this — `iosOnMacVersion` below is a
            // *different* listing kind ("software") whose `trackViewUrl` points at
            // the iOS listing, not the Mac one, so it keeps building its own URL.
            let fallbackURL = URL(string: "https://apps.apple.com/\(region)/app/-/id\(trackId)?platform=mac")
            if let scrapeURL = validatedProductPageURL(result.trackViewUrl, trackId: trackId, region: region) ?? fallbackURL {
                facts = try? await cachedMacVersionPageFacts(trackId: trackId, region: region, url: scrapeURL)
            }
        }
        let pageInfo = facts?.version

        // The page wins only when it's strictly newer (or the lookup gave nothing).
        let usePage: Bool
        if let pageVersion = pageInfo?.version {
            usePage = lookupVersion.map { VersionComparator.isNewer(pageVersion, than: $0) } ?? true
        } else {
            usePage = false
        }

        let version: String
        let notes: String?
        var changelogURL: URL?
        if usePage, let pageInfo {
            version = pageInfo.version
            // The page's own "What's New" describes this newer build — surface it,
            // and link the page as the changelog (matching the iOS-on-Mac path).
            notes = pageInfo.notes
            changelogURL = result.trackId.flatMap {
                URL(string: "https://apps.apple.com/\(region)/app/-/id\($0)?platform=mac")
            }
        } else if let lookupVersion {
            version = lookupVersion
            notes = result.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil  // neither source produced a version
        }

        // This copy IS the Mac build (`kind == "mac-software"`), so the
        // question for `AppStoreGate` is whether the LISTING still publishes
        // one (`publishesMacBuild`) — not `macSupported`, which answers "does
        // a wrapped iOS binary run on a Mac" (branch 2's question, asked of a
        // listing that has no Mac build of its own). Both readings come off
        // the SAME scrape that already fetched the version above — no extra
        // request — which is what makes `latestMacCompatible`/
        // `latestMinimumMacOS` reachable here at all; before `MacPageFacts`
        // this branch never scraped compatibility, so `AppStoreGate
        // .macIncompatible` was unreachable for any native-Mac listing
        // (issue #545's second consequence). nil (page unreadable) fails
        // open on both.
        //
        // ⚠️ Taken from the page scrape regardless of `usePage` — i.e. even
        // when the LOOKUP API's version wins below, not the page's own. This
        // is deliberate, not a version/compat mismatch: unlike
        // `mostRecentVersion` (a per-shelf-item value the page and the lookup
        // API can disagree on by a build, per the comment above), the
        // Compatibility annotation and `appPlatforms` are not scoped to a
        // specific version number in Apple's own data model — they describe
        // whatever the listing currently states, independent of which source
        // "won" the version race this check. The scrape is the only place
        // either is ever read, so gating it on `usePage` would silently drop
        // back to nil (no signal at all, this branch's state before this PR)
        // on every check where the lookup API's cache happens to be ahead —
        // exactly the gap #545/#546 exist to close, not a staleness bound
        // worth adding.
        let macCompatible = facts?.compatibility.publishesMacBuild
        let minimumMacOS = facts?.compatibility.minimumMacOS

        let availability = result.trackId.map {
            AppStoreAvailability(trackID: $0, availableRegion: region, homeRegion: homeRegion,
                                 latestMacCompatible: macCompatible, latestMinimumMacOS: minimumMacOS,
                                 storeName: result.trackName)
        }
        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteVersion(
            shortVersion: version,
            version: nil,
            downloadURL: result.trackViewUrl.flatMap { URL(string: $0) },
            // The App Store product page — for MAS the "download URL" already is
            // a page, so both fields point at it.
            pageURL: result.trackViewUrl.flatMap { URL(string: $0) },
            sourceName: name,
            appStore: availability,
            releaseNotesHTML: (cleanNotes?.isEmpty == false) ? cleanNotes : nil,
            changelogURL: changelogURL
        )
    }

    // MARK: - iOS-on-Mac page scrape

    /// Fetch the App Store Mac product page and extract the Mac-specific version.
    /// Returns nil when the page has no Mac section or the scrape fails — callers
    /// treat nil as "no source" and fall through to `appStoreManaged`.
    private func iosOnMacVersion(
        trackId: Int,
        lookupResult: LookupResult,
        region: String
    ) async throws -> RemoteVersion? {
        // Deliberately NOT `lookupResult.trackViewUrl`: for a `kind == "software"`
        // listing (this call site) that URL has no `mt=12` and points at the iOS
        // listing, not this Mac-specific one — using it would scrape the wrong
        // page. Always build the Mac product-page URL ourselves.
        let pageURL = URL(string: "https://apps.apple.com/\(region)/app/-/id\(trackId)?platform=mac")
        guard let pageURL,
              let facts = try await cachedMacVersionPageFacts(trackId: trackId, region: region, url: pageURL),
              let info = facts.version else {
            // Deliberately no fallback to the lookup's iOS-track version here —
            // see the doc comment on issue #545's "fix that would make this
            // worse": Nowdex's `?platform=mac` page (measured 2026-09-12) has
            // no version shelf at all, and falling back would pin an iOS-track
            // version number to a Mac row that can never reach it.
            return nil
        }
        // This copy IS the Mac build — same reasoning as `nativeMacVersion`'s
        // parallel comment: `publishesMacBuild` asks whether the LISTING still
        // ships one, off the same scrape that already answered the version
        // above, at no extra request. Before `MacPageFacts` this branch never
        // read compatibility at all, so a listing installed as a native Mac
        // copy could lose Mac support with no warning (issue #545's second
        // consequence).
        let macCompatible = facts.compatibility.publishesMacBuild
        let minimumMacOS = facts.compatibility.minimumMacOS
        let availability = AppStoreAvailability(trackID: trackId, availableRegion: region, homeRegion: homeRegion,
                                                latestMacCompatible: macCompatible, latestMinimumMacOS: minimumMacOS,
                                                storeName: lookupResult.trackName)
        // The Mac-specific product page, both as the inline web fallback and the
        // "Open page" link. The lookup API's `releaseNotes` here describes the iOS
        // track, not the Mac build, so we instead surface the Mac page's own
        // "What's New" text (scraped in the same pass as the version) inline —
        // exactly what the App Store shows for this app, rather than a web view.
        let notes = info.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteVersion(
            shortVersion: info.version,
            version: nil,
            downloadURL: lookupResult.trackViewUrl.flatMap { URL(string: $0) },
            // Use the Mac-specific product page constructed and unwrapped above.
            pageURL: pageURL,
            sourceName: name,
            appStore: availability,
            releaseNotesHTML: (notes?.isEmpty == false) ? notes : nil,
            changelogURL: pageURL
        )
    }

    /// The newest Mac build's version string plus its "What's New" notes, both
    /// read from the product page's `mostRecentVersion` shelf in a single scrape.
    struct MacVersionInfo: Equatable, Sendable {
        let version: String
        /// The latest version's release-notes text, verbatim (newline-delimited,
        /// no markup — rendered as plain text). Nil when the shelf carries none.
        let notes: String?
    }

    /// Everything one product-page scrape settles, bundled into a single value
    /// rather than two independent optionals.
    ///
    /// This exists because a page can answer one half and not the other:
    /// Nowdex's `?platform=mac` page (measured 2026-09-12) has NO
    /// `mostRecentVersion` shelf at all — there is no version string anywhere
    /// on the page — yet it still carries the Mac-compatibility signals and the
    /// OS floor (`appPlatforms`, the Compatibility annotation). `version` and
    /// `compatibility` are extracted by two independent parsers
    /// (`extractMacVersionInfo` / `extractMacCompatibility`) run over the SAME
    /// html, not a merged parser — keeping each extractor's behaviour identical
    /// to what it was before this type existed is what keeps its own tests (and
    /// `duo verify`'s per-signal shape checks) reading as a diff against the
    /// pre-existing parser rather than a rewrite of it.
    struct MacPageFacts: Equatable, Sendable {
        var version: MacVersionInfo?
        var compatibility: MacCompatibilityReading
    }

    /// Validate a network-sourced product-page URL (`LookupResult.trackViewUrl`)
    /// before trusting it for a scrape. `trackViewUrl` comes off the wire, so a
    /// scheme/host check guards against following it somewhere unexpected;
    /// anything that fails returns nil so the caller falls back to the URL it
    /// would have built itself.
    private func validatedProductPageURL(_ trackViewUrl: String?, trackId: Int, region: String) -> URL? {
        guard let trackViewUrl, let url = URL(string: trackViewUrl),
              url.scheme == "https", url.host == "apps.apple.com" else { return nil }
        // The host check alone is not enough, and the gap is not theoretical:
        // scraping the wrong listing puts an uninstallable version on the row
        // and `AppStorePageCache` then holds it for an hour, because
        // `nativeMacVersion` prefers the page whenever it is strictly newer.
        //
        // ⚠️ The id alone does NOT discriminate, and a first attempt at this
        // guard got that wrong. **One trackId serves two different product
        // pages** — they differ only by the QUERY, which `url.path` excludes by
        // definition. Measured 2026-09-05, same id, same host, two answers:
        //
        //     id1465439395 (Dark Noise)  default page 3.5.2   ?platform=mac 3.4.3
        //     id1593408455 (Anybox)      default page 2.13    ?platform=mac 2.14
        //
        // So the platform marker is the load-bearing half of this check, not
        // the id: without it, a URL for the same app can still be the wrong
        // page, and the iOS track running AHEAD is what would turn that into an
        // update the Mac copy can never install.
        //
        // ⚠️ Those two apps are the EVIDENCE, not the failure. Both answer the
        // lookup with `kind: "software"` in all nine storefronts this source
        // probes, so `isNativeMac` is false and `resolve()` sends them to
        // `iosOnMacVersion`, which builds its own URL and never reads
        // `trackViewUrl` at all. They can not reach this function. An earlier
        // version of this comment claimed one of them was a live failure here;
        // it is not, and nobody should "fix" `iosOnMacVersion` on the strength
        // of it. What is measured is that the id cannot tell two pages apart.
        // That a `mac-software` lookup would ever hand back a non-Mac
        // `trackViewUrl` is UNOBSERVED — 1094 `mac-software` listings sampled
        // 2026-09-05 all carried `mt=12`, and 0 of 1865 iOS listings did. This
        // guard is defence in depth against a shape Apple has not shown us.
        //
        // Exact last-component equality rather than `contains`, because Apple
        // ids are 9-10 digits and `id975937182` is a substring of ten distinct
        // 10-digit ids. Measured against the 15 `mac-software` listings on this
        // machine: all 15 end in `id<trackId>` and all 15 carry `mt=12`, so
        // this rejects none of them and costs no extra 301.
        // Storefront too, and for the same reason as the platform marker: the
        // scrape is filed in `AppStorePageCache` under the caller's `region`, so
        // a cross-storefront URL would pin another store's answer for an hour
        // under a right-looking key. Measured `country=us`: the segment tracks
        // the storefront asked for (`/us/app/xcode/id497799835?mt=12&uo=4`).
        // Not currently firing — this closes the third way in, after host and
        // platform.
        let segments = url.path.split(separator: "/")
        guard segments.first == Substring(region) else { return nil }
        guard segments.last == "id\(trackId)" else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard query.contains(where: {
            ($0.name == "mt" && $0.value == "12") || ($0.name == "platform" && $0.value == "mac")
        }) else { return nil }
        return url
    }

    /// `fetchMacVersion`, memoized through `pageCache` (see it for the caching
    /// contract). A genuine transport exception still propagates unchanged (as it
    /// did before this cache existed). A non-2xx response or an undecodable body
    /// is `.unavailable` — we don't actually know anything, so nothing is cached
    /// and nil comes back exactly as it did before. A 2xx response that fails to
    /// PARSE a version is still `.success(facts)` with `facts.version == nil` —
    /// we asked and got a real (if partly useless) answer, so THAT is what gets
    /// cached: the page won't suddenly start parsing before the TTL expires, so
    /// there's no reason to pay for it again on every check in that window.
    private func cachedMacVersionPageFacts(trackId: Int, region: String, url: URL) async throws -> MacPageFacts? {
        if let cached = await pageCache.cachedVersionFacts(trackId: trackId, region: region) {
            return cached
        }
        switch try await fetchMacVersion(url: url) {
        case .success(let facts):
            await pageCache.storeVersionFacts(facts, trackId: trackId, region: region)
            return facts
        case .unavailable:
            return nil
        }
    }

    /// Fetches the App Store Mac page and extracts BOTH the current Mac version
    /// (+ its "What's New" notes) and the Mac-compatibility signals from the
    /// same embedded amp-api JSON, in one pass over the html — see
    /// `MacPageFacts`'s doc comment for why a page that answers one half and
    /// not the other needs a single bundled result rather than two independent
    /// optionals. The version lives at
    /// `data[0].data.shelfMapping.mostRecentVersion.items[0]`, with
    /// `primarySubtitle` = "Version X.Y.Z" and `text` = the release notes; the
    /// compatibility signals are `extractMacCompatibility`'s own (see its doc
    /// comment).
    private func fetchMacVersion(url: URL) async throws -> PageFetchOutcome<MacPageFacts> {
        try await fetchPageFacts(url: url, label: "App Store page \(url.absoluteString)")
    }

    /// Parses `<script type="application/json">` blobs in the HTML, looking for
    /// the `mostRecentVersion` shelf that Apple's amp-api inlines into the page.
    /// Internal for offline tests.
    func extractMacVersionInfo(from html: String) -> MacVersionInfo? {
        // Lightweight scan: find JSON blobs without a full HTML parser.
        var searchRange = html.startIndex..<html.endIndex
        let open = "<script type=\"application/json\""
        let close = "</script>"

        while let tagStart = html.range(of: open, range: searchRange) {
            guard let bodyStart = html.range(of: ">", range: tagStart.upperBound..<html.endIndex),
                  let bodyEnd   = html.range(of: close, range: bodyStart.upperBound..<html.endIndex) else { break }

            let jsonSlice = html[bodyStart.upperBound..<bodyEnd.lowerBound]
            if let jsonData = jsonSlice.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let info = parseMostRecentVersion(from: root) {
                return info
            }
            searchRange = bodyEnd.upperBound..<html.endIndex
        }
        return nil
    }

    private func parseMostRecentVersion(from root: [String: Any]) -> MacVersionInfo? {
        guard let dataArr  = root["data"] as? [[String: Any]],
              let first    = dataArr.first,
              let inner    = first["data"] as? [String: Any],
              let shelves  = inner["shelfMapping"] as? [String: Any],
              let mrv      = shelves["mostRecentVersion"] as? [String: Any],
              let items    = mrv["items"] as? [[String: Any]],
              let item     = items.first,
              let subtitle = item["primarySubtitle"] as? String else { return nil }

        // The label is localized ("Version 26.21.73", "版本 16.109.3", "버전 …") —
        // pull the numeric version out directly rather than stripping an English
        // prefix, which left non-English subtitles unparsed.
        guard let version = Self.versionNumber(in: subtitle) else { return nil }
        let notes = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MacVersionInfo(version: version, notes: (notes?.isEmpty == false) ? notes : nil)
    }

    /// Extract the first dotted-numeric version run from a (possibly localized)
    /// "Version X.Y.Z" subtitle. Falls back to a bare integer for single-component
    /// versions. Internal for offline tests.
    static func versionNumber(in text: String) -> String? {
        let range = text.range(of: #"\d+(\.\d+)+"#, options: .regularExpression)
            ?? text.range(of: #"\d+"#, options: .regularExpression)
        return range.map { String(text[$0]) }
    }

    // MARK: - Mac compatibility (wrapped iOS apps)

    /// What one product page says about running the LATEST build on a Mac.
    ///
    /// Two readings, because `isIOSBinaryMacOSCompatible` on its own answers a
    /// narrower question than its name suggests: it says whether the *iOS
    /// binary* runs on macOS — i.e. whether this listing is installable on
    /// Apple Silicon as a wrapped iPhone/iPad app. A listing that ships its own
    /// **Mac** binary answers `false` there and is nevertheless fully supported
    /// on Macs; the Mac build, not the wrapper, is what a Mac installs. So the
    /// flag flips to `false` on the day a developer ADDS Mac support natively,
    /// which reads exactly like the day one drops it.
    ///
    /// `appPlatforms` is the other half: the platforms the listing publishes
    /// binaries for. `"mac"` in it means a real Mac build exists.
    ///
    /// Measured 2026-09-12 against 18 live listings (`us` storefront, Aqara Home
    /// also `cn`): the page's own "Compatibility" section names Mac exactly when
    /// `isIOSBinaryMacOSCompatible == true || appPlatforms.contains("mac")`, with
    /// no exception in either direction.
    ///   - flag `true`, no `"mac"` platform, Mac listed: Overcast, Aqara Home.
    ///   - flag `false`, `"mac"` platform, Mac listed: nowdex, GoodNotes,
    ///     WhatsApp, Kindle, CARROT Weather, Home Assistant, Bear, Things 3,
    ///     Day One, Todoist, Microsoft To Do.
    ///   - flag `false`, no `"mac"` platform, Mac NOT listed: Instagram,
    ///     Discord, Facebook, Scriptable, ChatGPT, Telegram, Fantastical,
    ///     Microsoft Edge.
    struct MacCompatibilityReading: Equatable, Sendable {
        /// `data[0].data.lockup.isIOSBinaryMacOSCompatible`.
        var iosBinaryRunsOnMac: Bool?
        /// `data[0].data.appPlatforms`.
        var appPlatforms: [String]?
        /// The macOS floor the listing states for its Mac build, reduced to the
        /// bare numeric run ("15.6"), or nil when the page states none.
        ///
        /// Read from `data[0].data.shelfMapping.information.items[*].items[*]`,
        /// the one item whose `heading` is the literal string `"Mac"` — never
        /// the first digit run anywhere in the shelf, which can be a street
        /// address or phone number in an EU merchant-disclosure section
        /// (measured 2026-09-12, Kindle's `de` page: an `'Adresse'` item reading
        /// `'1209 Orange St Wilmington Delaware 19801...'` and a
        /// `'Telefonnummer'` item reading `'+1 5712344460'` sit in the same
        /// `information` shelf as the Compatibility annotation).
        ///
        /// `heading` is the literal ASCII string `"Mac"` on every storefront
        /// measured 2026-09-12 (us/cn/jp/de/fr/ru) — only `text` is localized,
        /// e.g. cn `"设备需装有 macOS 15.6 或更高版本。"`, de
        /// `"Erfordert macOS\u{00A0}13.0 oder neuer."`. Non-English storefronts
        /// put a U+00A0 (no-break space) between "macOS" and the number, which
        /// is why this reuses `versionNumber(in:)` (a plain digit-run scan)
        /// rather than anchoring on the literal substring `"macOS "`. Xcode's
        /// text carries a trailing chip clause ("...and a Mac with Apple M1
        /// chip or later.") — `versionNumber(in:)`'s "first dotted-numeric run"
        /// still picks out the OS number correctly because the chip name has
        /// none of its own.
        var minimumMacOS: String?

        /// Both shapes were found. Only `verifyMacCompatPageShape` cares: the
        /// verdict below stays useful when either one alone survives, so a
        /// half-drifted page would still answer correctly — and silently — if
        /// the sweep settled for `macSupported != nil`.
        var readBothSignals: Bool { iosBinaryRunsOnMac != nil && appPlatforms != nil }

        /// Whether the latest build is installable on a Mac at all. `nil` means
        /// "couldn't tell" and callers treat it as compatible, so a scrape
        /// failure never hides a real update.
        ///
        /// Fails open in one more place than the shape of the data strictly
        /// forces: a `false` verdict needs BOTH readings, because a lone
        /// `isIOSBinaryMacOSCompatible == false` is the majority shape above and
        /// says nothing on its own. If Apple renames `appPlatforms`, every app
        /// with a native Mac build lands here as `nil` (offer the update, maybe
        /// wrongly) rather than as `false` (refuse it, definitely wrongly).
        var macSupported: Bool? {
            if iosBinaryRunsOnMac == true { return true }
            guard let appPlatforms else { return nil }
            if appPlatforms.contains("mac") { return true }
            return iosBinaryRunsOnMac == false ? false : nil
        }

        /// Whether the listing still PUBLISHES a Mac build — the question a
        /// copy that IS the Mac build has to ask (`resolve()`'s branches 1 and
        /// 3: `nativeMacVersion`, `iosOnMacVersion`), as opposed to
        /// `macSupported`'s "does the wrapped iOS binary run on a Mac at all"
        /// (branch 2, a listing with no Mac build of its own). nil (unreadable)
        /// means "assume it does" — a scrape failure must never hide a real
        /// update.
        var publishesMacBuild: Bool? { appPlatforms.map { $0.contains("mac") } }
    }

    /// Reads the compatibility signals (and, in the same pass, the version
    /// shelf — see `MacPageFacts`) off the product page's inline amp-api JSON.
    /// nil when the page can't be read; `compatibility`'s own fields are nil
    /// when what it carries doesn't settle the question — callers treat those
    /// as "assume compatible" so a scrape failure never hides a real update.
    /// Memoized through `pageCache`, same contract as `cachedMacVersionPageFacts`
    /// above: a non-2xx/undecodable response is `.unavailable` (not cached, nil
    /// returned exactly as before this cache existed); a 2xx response with
    /// nothing readable still caches a `MacPageFacts` whose fields are nil.
    private func cachedMacCompatibilityPageFacts(trackId: Int, region: String) async throws -> MacPageFacts? {
        if let cached = await pageCache.cachedCompatibilityFacts(trackId: trackId, region: region) {
            return cached
        }
        guard let url = URL(string: "https://apps.apple.com/\(region)/app/id\(trackId)") else {
            return nil  // malformed URL never happens for a real trackId/region; nothing to cache
        }
        switch try await fetchMacCompatibility(url: url) {
        case .success(let facts):
            await pageCache.storeCompatibilityFacts(facts, trackId: trackId, region: region)
            return facts
        case .unavailable:
            return nil
        }
    }

    /// Fetches the App Store's plain (non `?platform=mac`) product page and
    /// extracts BOTH the Mac-compatibility signals and — in the same pass over
    /// the html — the version shelf, via the same two independent extractors
    /// `fetchMacVersion` uses. See `MacPageFacts`'s doc comment for why the two
    /// are bundled into one cached result rather than fetched separately.
    private func fetchMacCompatibility(url: URL) async throws -> PageFetchOutcome<MacPageFacts> {
        try await fetchPageFacts(url: url, label: "App Store compat \(url.absoluteString)")
    }

    /// The GET + parse both `fetchMacVersion` and `fetchMacCompatibility` do —
    /// identical apart from the URL and the request label — factored out so a
    /// future change to the request itself (the UA string, the timeout, the
    /// non-2xx/undecodable handling) can't be applied to only one of the two
    /// pages by accident. Still runs both extractors regardless of which page
    /// was fetched, per `MacPageFacts`'s doc comment: a page answering only
    /// half is the shape this exists to carry, not to special-case away here.
    private func fetchPageFacts(url: URL, label: String) async throws -> PageFetchOutcome<MacPageFacts> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        // Apple's servers gate the full JSON blobs behind a browser UA.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.versionFeedData(for: request, label: label)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return .unavailable
        }
        guard let html = String(data: data, encoding: .utf8) else {
            return .unavailable
        }
        return .success(MacPageFacts(
            version: extractMacVersionInfo(from: html),
            compatibility: extractMacCompatibility(from: html)))
    }

    /// Finds `data[0].data.lockup.isIOSBinaryMacOSCompatible` and
    /// `data[0].data.appPlatforms` in the page's `<script type="application/json">`
    /// blobs. Internal for offline tests and for `verifyMacCompatPageShape`,
    /// which asserts both shapes are still there.
    ///
    /// The pages carry more than one lockup — `moreByDeveloper` items have the
    /// same flag, for other apps entirely — so the path is anchored at
    /// `data[0].data`, which is this listing's own. (Measured on nowdex's page,
    /// 2026-09-12: four `isIOSBinaryMacOSCompatible` occurrences, three of them
    /// the developer's other apps.)
    func extractMacCompatibility(from html: String) -> MacCompatibilityReading {
        var searchRange = html.startIndex..<html.endIndex
        let open = "<script type=\"application/json\""
        let close = "</script>"

        while let tagStart = html.range(of: open, range: searchRange) {
            guard let bodyStart = html.range(of: ">", range: tagStart.upperBound..<html.endIndex),
                  let bodyEnd   = html.range(of: close, range: bodyStart.upperBound..<html.endIndex) else { break }

            let jsonSlice = html[bodyStart.upperBound..<bodyEnd.lowerBound]
            if let jsonData = jsonSlice.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let dataArr = root["data"] as? [[String: Any]],
               let inner   = dataArr.first?["data"] as? [String: Any] {
                let reading = MacCompatibilityReading(
                    iosBinaryRunsOnMac: (inner["lockup"] as? [String: Any])?["isIOSBinaryMacOSCompatible"] as? Bool,
                    appPlatforms: inner["appPlatforms"] as? [String],
                    minimumMacOS: Self.minimumMacOS(from: inner))
                // Keep scanning when this blob carried none of the three — an
                // earlier blob on the page can be some other payload entirely.
                if reading.iosBinaryRunsOnMac != nil || reading.appPlatforms != nil
                    || reading.minimumMacOS != nil { return reading }
            }
            searchRange = bodyEnd.upperBound..<html.endIndex
        }
        return MacCompatibilityReading()
    }

    /// Finds the "Requires macOS X.Y or later." annotation in
    /// `data[0].data.shelfMapping.information.items[*].items[*]` and reduces it
    /// to the bare numeric run — the item whose `heading` is the literal string
    /// `"Mac"`, never the first item in the shelf or the first digit run
    /// anywhere in it. See `MacCompatibilityReading.minimumMacOS`'s doc comment
    /// for the EU-merchant-disclosure trap that anchoring on `heading` avoids.
    private static func minimumMacOS(from inner: [String: Any]) -> String? {
        guard let shelves = inner["shelfMapping"] as? [String: Any],
              let information = shelves["information"] as? [String: Any],
              let sections = information["items"] as? [[String: Any]] else { return nil }
        for section in sections {
            guard let items = section["items"] as? [[String: Any]] else { continue }
            for item in items {
                guard (item["heading"] as? String) == "Mac", let text = item["text"] as? String
                else { continue }
                // Keep scanning rather than committing to nil here: this
                // item's heading matched, but if its own text doesn't yield a
                // number (an unseen phrasing, say), a LATER "Mac" item
                // elsewhere in the shelf might still have one. Unmeasured
                // whether Apple ever emits more than one — this costs nothing
                // when there's only the usual single match, and fails open
                // (nil) only after every candidate has been tried.
                if let version = versionNumber(in: text) { return version }
            }
        }
        return nil
    }


    // MARK: -

    /// Build a `RemoteVersion` from a lookup hit. For wrapped iPhone/iPad apps
    /// (`checkMacCompat`), also fetch the product page once to learn whether the
    /// newest build still runs on Macs — a newer version can exist yet be
    /// uninstallable here ("Not compatible with this device").
    private func remoteVersion(from result: LookupResult, region: String, checkMacCompat: Bool) async throws -> RemoteVersion? {
        guard let version = result.version else { return nil }
        var macCompatible: Bool?
        var minimumMacOS: String?
        if checkMacCompat, let trackId = result.trackId {
            // This IS a wrapped iOS binary (the guard on `checkMacCompat` at
            // both call sites), so `macSupported` — "does the wrapped binary
            // run on a Mac at all" — is still the right question, unlike
            // branches 1/3 above which ask `publishesMacBuild` instead.
            let facts = try await cachedMacCompatibilityPageFacts(trackId: trackId, region: region)
            macCompatible = facts?.compatibility.macSupported
            minimumMacOS = facts?.compatibility.minimumMacOS
        }
        let availability = result.trackId.map {
            AppStoreAvailability(trackID: $0, availableRegion: region, homeRegion: homeRegion,
                                 latestMacCompatible: macCompatible, latestMinimumMacOS: minimumMacOS,
                                 storeName: result.trackName)
        }
        // `releaseNotes` is the "What's New" text for the latest version. Safe to
        // trust here: we only reach this for native Mac listings or wrapped iOS
        // apps (guarded upstream), where the notes match the actual installed
        // build — not an unrelated track. Plain text (newline-delimited).
        let notes = result.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteVersion(
            shortVersion: version,
            version: nil,
            downloadURL: result.trackViewUrl.flatMap { URL(string: $0) },
            // The App Store product page — for MAS the "download URL" already is
            // a page, so both fields point at it.
            pageURL: result.trackViewUrl.flatMap { URL(string: $0) },
            sourceName: name,
            appStore: availability,
            releaseNotesHTML: (notes?.isEmpty == false) ? notes : nil
        )
    }

    /// One lookup against a single storefront. Returns nil when the app isn't
    /// listed there (resultCount == 0).
    ///
    /// Asks for the user's own language when we can name it, because the listing is
    /// localised and two things read it: the "What's New" text we show, and
    /// `AppStoreAXInstaller`, which has to recognise the name App Store.app renders
    /// on screen. Without `lang` the API answers in the storefront's default —
    /// measured 2026-09-05, same app and storefront:
    ///
    ///     lookup?id=1435447041&country=us            → "DingDing: Redefine Work in AI"
    ///     lookup?id=1435447041&country=us&lang=zh_cn → "钉钉 - AI时代的工作方式"
    ///
    /// A language the app doesn't have is harmless (`lang=ja_jp` on that app answers
    /// in its default, 200). A language *code* the API doesn't accept is not: it is a
    /// **400**, and this method turns any non-2xx into a throw — which would take out
    /// version detection for every Mac App Store app, not just the AX route. So a
    /// rejected code is retried once without `lang` and then not sent again for the
    /// life of the process.
    private func lookup(bundleID: String, region: String) async throws -> LookupResult? {
        let lang = await LanguageSupport.shared.isRejected
            ? nil
            : Self.storeLanguage(preferred: Locale.preferredLanguages, storefront: region)
        // Prewarm is consulted AFTER `lang` is resolved and keyed on it, not
        // just on (bundleID, region). The batch and the single request have to
        // agree on the language or the cache quietly undoes the localisation:
        // `AppStoreAXInstaller` matches `storeName` against what App Store.app
        // renders on screen, so a hit carrying the storefront's default name
        // would break the AX route on every non-English Mac — with no error and
        // no changed version number to notice it by.
        // Wait for the batch here rather than in `UpdateChecker`: only the rows
        // that would otherwise pay for their own lookup should pay its latency.
        await prewarmCache.awaitInFlight()
        if let cached = await prewarmCache.lookup(
            bundleID: bundleID, region: region, lang: lang) {
            return cached
        }
        do {
            return try await lookup(bundleID: bundleID, region: region, lang: lang)
        } catch MASError.badStatus(let code) where code == 400 && lang != nil {
            // 400 ONLY, and it used to be any non-2xx. That was a process-wide,
            // permanent, silent latch on an unrelated failure: one 403 from rate
            // limiting or one 503 and every later lookup drops `lang`, so every
            // `trackName` falls back to the storefront default — the name
            // `AppStoreAXInstaller` has to find on screen. Nothing errors, no
            // version changes, and the App Store install route just stops
            // working on a non-English Mac until the app is restarted.
            await LanguageSupport.shared.markRejected(code: code, lang: lang ?? "?")
            return try await lookup(bundleID: bundleID, region: region, lang: nil)
        }
    }

    private func lookup(bundleID: String, region: String, lang: String?) async throws -> LookupResult? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: region),
            URLQueryItem(name: "entity", value: "macSoftware")
        ] + (lang.map { [URLQueryItem(name: "lang", value: $0)] } ?? [])
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy

        let (data, response) = try await session.versionFeedData(
            for: request, label: "App Store lookup \(bundleID)")
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MASError.badStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
        // What the store actually said, next to the exact URL it was asked. Added
        // 2026-09-06 after Nowdex, where the batched lookup and this one answered
        // different versions for the same app seconds apart: the success path
        // recorded neither the URL nor the answer, so the disagreement could only
        // be inferred from a verdict two layers up, and "we asked the wrong thing"
        // could not be told apart from "we were told the wrong thing". The byte
        // count is here because it is what settled that — two different lengths
        // for one URL are two documents. `.debug`, so it costs nothing when nobody
        // is looking.
        Log.source.debug(
            "app store lookup: \(url.absoluteString, privacy: .public) → \(data.count) bytes, \(decoded.results.count) result(s), version=\(decoded.results.first?.version ?? "-", privacy: .public), kind=\(decoded.results.first?.kind ?? "-", privacy: .public)")
        return decoded.results.first
    }

    /// One batched lookup across up to 20 bundle ids (`itunes.apple.com/lookup`
    /// accepts a comma-separated `bundleId`; 20 in one request measured at 557
    /// URL characters / ~31.8 KB response, vs. ~54 KB for 20 separate requests).
    /// Maps every id that was IN the batch to what came back for it — including
    /// nil for one the store didn't have — so `AppStoreLookupCache` can record a
    /// definite miss and `lookup(bundleID:region:)` doesn't repeat the question.
    /// ⚠️ Takes the SAME `lang` the single lookup resolved, and must keep doing
    /// so. The batch is what fills `prewarmCache`, and the single path reads it:
    /// if the two disagree on language, every prewarmed app silently gets the
    /// storefront's default `trackName` instead of the user's, which is the name
    /// `AppStoreAXInstaller` has to match on screen. Nothing errors and no
    /// version changes — the App Store install route just stops finding its
    /// button on a non-English Mac. See `lookup(bundleID:region:)`.
    private func batchLookup(
        bundleIDs: [String], region: String, lang: String?
    ) async throws -> [String: LookupResult?] {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIDs.joined(separator: ",")),
            URLQueryItem(name: "country", value: region),
            URLQueryItem(name: "entity", value: "macSoftware")
        ] + (lang.map { [URLQueryItem(name: "lang", value: $0)] } ?? [])
        guard let url = components.url else { return [:] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy

        // Attributed to NO app, explicitly. One request answers twenty of them,
        // so there is no honest per-app owner — the same reasoning that files
        // the Homebrew catalog under nobody. Explicit rather than relying on
        // this happening to run outside a `withApp` scope: `prewarm` is called
        // from `UpdateChecker` today, and a future caller inside one would
        // otherwise bill twenty apps' bytes to whichever one it happened to be.
        //
        // ⚠️ This CHANGES what a per-app traffic row means for a Mac App Store
        // app. Its lookup bytes used to land on its own row; they are now in an
        // unattributed pool, so those rows read lower for a reason that has
        // nothing to do with the app. Kept as `.versionCheck` on purpose:
        // `.catalog` would be a better-shaped bucket but it already means "the
        // Homebrew index" to every stored row and every `duo requests` query,
        // and redefining it retroactively would make the log lie about its own
        // history.
        let (data, response) = try await RequestAttribution.withApp(nil) {
            try await session.versionFeedData(
                for: request, label: "App Store prewarm lookup (\(bundleIDs.count))")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MASError.badStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
        var byBundleID: [String: LookupResult] = [:]
        for result in decoded.results {
            if let bundleID = result.bundleId { byBundleID[bundleID] = result }
        }
        var out: [String: LookupResult?] = [:]
        for bundleID in bundleIDs { out[bundleID] = byBundleID[bundleID] }
        // The other half of the pair above: the batch is what a scheduled check
        // answers from, the single lookup is what a click answers from, and the
        // whole point is to be able to compare the two for one app.
        Log.source.debug(
            "app store prewarm lookup: \(url.absoluteString, privacy: .public) → \(data.count) bytes, \(decoded.results.count)/\(bundleIDs.count) result(s): \(byBundleID.map { "\($0.key)=\($0.value.version ?? "-")" }.sorted().joined(separator: " "), privacy: .public)")
        return out
    }

    /// The `lang` code to ask the lookup API for, or nil when we can't name one.
    ///
    /// The API wants `language_region` (`en_us`, `zh_cn`), which is not what
    /// `Locale.preferredLanguages` hands out — Chinese in particular is identified by
    /// *script* there ("zh-Hans-US" is Simplified Chinese on a US-region Mac), and the
    /// script is what picks the listing, not the region. Everything else takes the
    /// identifier's own region, falling back to the storefront we are asking.
    ///
    /// Pure so the mapping is assertable; a wrong code costs one 400 and a retry (see
    /// the caller), never a silently wrong answer.
    static func storeLanguage(preferred: [String], storefront: String) -> String? {
        guard let first = preferred.first else { return nil }
        let locale = Locale(identifier: first)
        guard let language = locale.language.languageCode?.identifier.lowercased(),
              !language.isEmpty else { return nil }
        if language == "zh" {
            switch locale.language.script?.identifier {
            case "Hant": return "zh_tw"
            default:     return "zh_cn"
            }
        }
        let region = (locale.language.region?.identifier ?? storefront).lowercased()
        guard !region.isEmpty else { return nil }
        return "\(language)_\(region)"
    }

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    struct LookupResult: Decodable {
        let version: String?
        let trackViewUrl: String?
        let trackId: Int?
        /// The store's own listing title ("DingDing: Redefine Work in AI"), which is
        /// what the product page renders — and is NOT the installed bundle's name
        /// ("DingTalk"). `AppStoreAXInstaller` binds the offer button by that title,
        /// so it has to come from here; see `AppStoreAvailability.storeName`.
        let trackName: String?
        /// "What's New in Version X" text for the latest release. Plain text with
        /// embedded newlines (no markup). nil/absent for some listings.
        let releaseNotes: String?
        /// "mac-software" for native Mac apps; "software" for iOS apps offered
        /// on Apple Silicon (whose `version` is the unrelated iOS version).
        let kind: String?
        /// The listing's own bundle id — absent from a single-bundleId lookup's
        /// use (that caller already knows which bundle it asked about), but
        /// needed by `batchLookup` to map a comma-separated response's several
        /// results back to the ids that produced them.
        let bundleId: String?

        var isNativeMac: Bool { kind == "mac-software" }
    }

    /// A page fetch's outcome, in the vocabulary `AppStorePageCache`'s callers
    /// need: `.success` (even with a nil payload) means "we got a real answer,
    /// worth memoizing"; `.unavailable` means "a non-2xx response or an
    /// undecodable body — we don't actually know anything, don't cache this".
    private enum PageFetchOutcome<T> {
        case success(T)
        case unavailable
    }

    enum MASError: Error { case badStatus(Int) }

    /// Remembers, for the life of the process, that the lookup API rejected the language
    /// code we derived — so the fallback costs one wasted request in total rather than
    /// one per app per check. Deliberately not persisted: the answer belongs to the API,
    /// and a stale "rejected" on disk would keep a user on the wrong listing language
    /// long after Apple started accepting their code.
    private actor LanguageSupport {
        static let shared = LanguageSupport()
        private(set) var isRejected = false
        /// Latched for the life of the process, so say so once. Without a line
        /// here the only evidence that localisation stopped is that it stopped.
        func markRejected(code: Int, lang: String) {
            guard !isRejected else { return }
            isRejected = true
            Log.source.error(
                "App Store lookup rejected lang=\(lang, privacy: .public) (HTTP \(code, privacy: .public)) — dropping it for the rest of this process; trackName will be the storefront default")
        }
    }
}

// MARK: - `duo verify` diagnostics
//
// Everything below is read-only plumbing for `duo verify`'s App Store sweep
// (see `MacAppStoreProbeRegistry`). It calls the SAME private lookup/fetch
// helpers `latestVersion(for:)` itself uses — never a reimplementation — but
// reports SHAPE (did the endpoint answer the question we asked) rather than
// VALUE (what version it answered with). Asserting a specific version string
// here would make this sweep something that has to be touched on every
// vendor release, which is exactly the kind of check nobody keeps green —
// see `MacAppStoreProbeRegistry`'s doc comment.
//
// Deliberately UN-cached: `pageCache`/`prewarmCache` exist so the shipping
// app doesn't re-fetch a page it just scraped a minute ago. A verify run
// wants a live answer on every sweep, not whatever the last check happened to
// leave cached — so these bypass both caches and call the private fetch
// helpers directly.

/// The two fields `duo verify` actually checks off a lookup hit. Never the
/// version or release notes, which change on every release and are not the
/// premise anything here depends on.
public struct AppStoreLookupShape: Sendable, Equatable {
    public let kind: String?
    public let trackId: Int?
}

/// One product-page fetch's outcome, in the vocabulary `duo verify` needs.
/// `.reachable(found: false)` is the finding worth having: a 2xx page the
/// production parser can no longer read is A2/A3's silent-failure mode.
public enum AppStorePageShapeCheck: Sendable {
    case reachable(found: Bool)
    case unreachable(httpStatus: Int?)
}

extension MacAppStoreSource {
    /// Un-cached single-bundle lookup. Same request `latestVersion(for:)`
    /// itself makes (bypassing `prewarmCache`, which a verify run never
    /// populates — there is no `prewarm(_:)` call in this sweep).
    public func verifyLookup(bundleID: String, region: String) async throws -> AppStoreLookupShape? {
        // Three-argument form on purpose: the two-argument wrapper consults
        // `prewarmCache` first, and a sweep whose whole job is to get a LIVE
        // answer must not be able to report a cached shape as one. It is inert
        // today only because nothing in the sweep populates that cache — which
        // is a fact about today's call graph, not a property of this function.
        let lang = await LanguageSupport.shared.isRejected
            ? nil
            : Self.storeLanguage(preferred: Locale.preferredLanguages, storefront: region)
        guard let result = try await lookup(bundleID: bundleID, region: region, lang: lang)
        else { return nil }
        return AppStoreLookupShape(kind: result.kind, trackId: result.trackId)
    }

    /// `trackViewUrl` off the same single lookup, for the case that wants to
    /// test the redirect path.
    public func verifyTrackViewURL(bundleID: String, region: String) async throws -> URL? {
        guard let result = try await lookup(bundleID: bundleID, region: region) else { return nil }
        return result.trackViewUrl.flatMap { URL(string: $0) }
    }

    /// One batched lookup — production's `batchLookup`, exposed read-only.
    /// Maps every id in the batch to what came back for it, including nil for
    /// one the store legitimately didn't have.
    public func verifyBatchLookup(
        bundleIDs: [String], region: String
    ) async throws -> [String: AppStoreLookupShape?] {
        // The SAME shape `prewarm(_:)` sends, `lang` included. Verifying a
        // request production no longer makes would leave the multi-id + `lang`
        // combination — the one prewarm actually uses — unexercised, and its
        // failure is silent by construction: `prewarm` logs a 400 and every app
        // falls through to its own lookup, so the only symptom is traffic that
        // never dropped. (`kind` and `trackId`, the two fields check 5 compares,
        // are language-independent — measured 2026-09-05, same ids under
        // `lang=zh_cn` and no lang — so this cannot introduce a false break.)
        let lang = await LanguageSupport.shared.isRejected
            ? nil
            : Self.storeLanguage(preferred: Locale.preferredLanguages, storefront: region)
        let raw = try await batchLookup(bundleIDs: bundleIDs, region: region, lang: lang)
        var out: [String: AppStoreLookupShape?] = [:]
        for (id, result) in raw {
            out[id] = result.map { AppStoreLookupShape(kind: $0.kind, trackId: $0.trackId) }
        }
        return out
    }

    /// Does `url` still land with ZERO redirects? A2's optimization (skip the
    /// constructed `?platform=mac` URL's 301 by trusting the lookup's own
    /// `trackViewUrl`) is only a win while this holds. If Apple stops handing
    /// back a canonical URL, `validatedProductPageURL` already falls back
    /// safely — but silently pays the 301 again on every check, which is
    /// exactly what this is here to surface instead of leaving unmeasured.
    public func verifyZeroRedirect(
        _ url: URL
    ) async throws -> (finalHost: String?, statusCode: Int?, zeroRedirects: Bool) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return (nil, nil, false) }
        return (http.url?.host, http.statusCode, http.url == url)
    }

    /// Un-cached fetch + parse of the Mac-track version shelf at `trackId`'s
    /// `?platform=mac` product page — the same page `nativeMacVersion` and
    /// `iosOnMacVersion` both scrape, bypassing `pageCache`.
    public func verifyVersionPageShape(trackId: Int, region: String) async throws -> AppStorePageShapeCheck {
        guard let url = URL(string: "https://apps.apple.com/\(region)/app/-/id\(trackId)?platform=mac")
        else { return .unreachable(httpStatus: nil) }
        switch try await fetchMacVersion(url: url) {
        // `found` stays keyed on the version shelf alone, not on `minimumMacOS`
        // too. Measured live 2026-09-12 against this function's three registry
        // cases (`.nativeMac` Bear/Things 3, `.iosOnMac` WhatsApp): all three
        // carry a parseable `heading == "Mac"` floor on the `?platform=mac`
        // page (12.4, 13.3, 12.1) — 3/3. See `verifyMacCompatPageShape` below
        // for the case that measured differently and is why `found` there
        // stays untouched too.
        case .success(let facts): return .reachable(found: facts.version != nil)
        case .unavailable: return .unreachable(httpStatus: nil)
        }
    }

    /// Un-cached fetch + parse of both Mac-compatibility signals at `trackId`'s
    /// plain (non `?platform=mac`) product page — the page
    /// `remoteVersion(checkMacCompat: true)` scrapes, bypassing `pageCache`.
    ///
    /// `found` requires BOTH, not just a usable verdict: either signal drifting
    /// away on its own still leaves `macSupported` answering — the remaining one
    /// covers most listings — so a sweep that asked only for a non-nil verdict
    /// would go quiet on exactly the half-drift it exists to catch.
    public func verifyMacCompatPageShape(trackId: Int, region: String) async throws -> AppStorePageShapeCheck {
        guard let url = URL(string: "https://apps.apple.com/\(region)/app/id\(trackId)")
        else { return .unreachable(httpStatus: nil) }
        switch try await fetchMacCompatibility(url: url) {
        // `found` is still `readBothSignals` alone — `minimumMacOS` is
        // deliberately NOT folded in. Measured live 2026-09-12 against this
        // route's one registry case, Discord (`.wrappedIOS`): its plain
        // product page carries no `heading == "Mac"` annotation at all,
        // because Discord's App Store listing genuinely publishes no Mac
        // build (`appPlatforms == ["phone", "pad"]`) — there is no
        // Compatibility line for Mac to have a floor in the first place. A
        // `nil` floor there is the CORRECT reading, not a shape drift, so
        // adding it to `found` would report this case `.broken` every night
        // for a reason that has nothing to do with the parser. Left to
        // `MacAppStoreNotesTests`/`UpdateRouteResolutionTests` instead — see
        // `MacAppStoreProbeRegistry`'s cases for why this sweep has no case
        // that both publishes a Mac build AND takes this route (today's
        // registry has no such app named).
        case .success(let facts): return .reachable(found: facts.compatibility.readBothSignals)
        case .unavailable: return .unreachable(httpStatus: nil)
        }
    }
}
