import Foundation

/// Fetches a changelog page and runs its recipe — the thin network wrapper around
/// the pure `ChangelogExtractor`. Called lazily by the detail window when the user
/// opens an app that has a recipe, so we only ever hit a vendor's changelog page
/// on demand (never during the bulk update check).
///
/// Results are cached in ``ChangelogCache/shared`` for ``ChangelogCache/ttl``
/// seconds so re-opening the same app's detail window within a session skips the
/// network entirely. Concurrent opens of the same app are coalesced onto a single
/// in-flight fetch. The cache is cleared by ``AppListModel`` on every manual refresh.
///
/// Best-effort, mirroring the vendor-probe philosophy: any failure (network,
/// non-2xx, parse miss) returns nil, and the UI falls back to embedding the page
/// in a web view. It never throws to the caller.
public enum ChangelogService {

    /// A browser-like UA — same reasoning as `VendorProbeSource`: some vendor
    /// sites reject unfamiliar agents.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Resolve the page to parse, fetch it, and extract a `Changelog`, or nil on
    /// any failure. When `recipe.indexLinkPattern` is set the source is a
    /// newest-first index: we fetch it, follow its first link to the latest
    /// version's detail page, and parse that (see `resolveDetailURL`).
    ///
    /// Results are cached in ``ChangelogCache/shared`` for 15 minutes (keyed on
    /// `recipe.source`) so the detail window opens instantly on repeat visits.
    /// Concurrent callers for the same recipe are coalesced onto one network
    /// fetch. Cache is cleared on manual refresh — see ``AppListModel/refresh()``.
    public static func load(
        _ recipe: ChangelogRecipe, version: String? = nil, session: URLSession = .updates
    ) async -> Changelog? {
        // The page to fetch: the per-version URL when the recipe is templated and a
        // version is supplied, otherwise the fixed `source`. Cache on THIS resolved
        // URL so different versions never serve each other's notes.
        let resolved = recipe.resolvedSource(forVersion: version)
        // Delegate to the cache's fetch-through helper, which handles hit, miss,
        // and concurrent-miss coalescing in one place. Structured recipes that pack
        // every channel into one endpoint (Warp) get a per-channel cache key so the
        // channels don't serve each other's notes from this shared slot.
        let cacheURL = cacheKeyURL(for: recipe, resolved: resolved)
        let diskCacheKey = diskKey(for: recipe, version: version)
        return await ChangelogCache.shared.load(for: cacheURL) {
            Log.source.debug(
                "changelog cache miss: \(resolved.host ?? "?", privacy: .public)")
            let parsed: Changelog?
            if let format = recipe.structuredFormat {
                guard let text = await fetchBody(resolved, session: session) else { return nil }
                parsed = StructuredChangelogDecoder.decode(
                    text, format: format, channel: recipe.channel, maxEntries: recipe.maxEntries)
            } else {
                guard let pageURL = await resolveDetailURL(recipe, source: resolved, session: session),
                      let text = await fetchBody(pageURL, session: session)
                else { return nil }
                parsed = ChangelogExtractor.extract(from: text, using: recipe)
            }
            // Persist to the cross-launch disk cache, keyed by version (immutable
            // notes), so the next launch paints instantly and the periodic pre-warm
            // can skip the network for versions we already hold. This lives INSIDE the
            // fetch closure so it runs only on an actual network fetch (a cache miss) —
            // an in-memory hit must not re-encode + re-write + re-prune on every open.
            if let parsed, let diskCacheKey {
                await ChangelogDiskCache.shared.set(parsed, for: diskCacheKey)
            }
            return parsed
        }
    }

    /// Drop every in-memory ``ChangelogCache`` slot this recipe could occupy: the
    /// plain resolved page URL plus, for structured per-channel recipes (Warp), the
    /// channel-fragmented key (`…#stable`). Called after an app updates on disk so the
    /// next open re-fetches fresh notes instead of serving the prior version's from
    /// the still-warm in-memory cache.
    public static func invalidateMemoryCache(for recipe: ChangelogRecipe) async {
        let resolved = recipe.source
        await ChangelogCache.shared.invalidate(resolved)
        let keyURL = cacheKeyURL(for: recipe, resolved: resolved)
        if keyURL != resolved { await ChangelogCache.shared.invalidate(keyURL) }
    }

    /// The cross-launch disk-cached notes for this recipe+version, with no network
    /// fetch. The workbench reads this for an instant first paint before kicking off
    /// the stale-while-revalidate network load. nil when nothing is cached (or no
    /// version is known to key on).
    public static func diskCached(
        _ recipe: ChangelogRecipe, version: String?
    ) async -> Changelog? {
        guard let key = diskKey(for: recipe, version: version) else { return nil }
        return await ChangelogDiskCache.shared.get(for: key)
    }

    /// The in-memory cache slot for a recipe. Normally just the resolved page URL,
    /// but structured recipes whose channels share one endpoint (Warp's
    /// `channel_versions.json`) append the channel as a fragment so each channel
    /// owns a distinct slot — the fragment never reaches the network (we always
    /// fetch the un-fragmented `resolved`).
    static func cacheKeyURL(for recipe: ChangelogRecipe, resolved: URL) -> URL {
        guard recipe.structuredFormat != nil else { return resolved }
        let token = recipe.channel?.rawValue ?? "default"
        return URL(string: resolved.absoluteString + "#" + token) ?? resolved
    }

    /// The disk-cache key for a recipe+version, or nil when no version is known
    /// (the disk layer is keyed by the immutable per-version notes, so a versionless
    /// load can't be cached there — it still uses the in-memory cache).
    static func diskKey(
        for recipe: ChangelogRecipe, version: String?
    ) -> ChangelogDiskCache.Key? {
        guard let version, !version.isEmpty else { return nil }
        return ChangelogDiskCache.Key(
            bundleID: recipe.bundleID,
            channel: recipe.channel?.rawValue ?? "default",
            version: version)
    }

    /// The page the entry/item patterns run against, given the already-resolved
    /// source. Without an `indexLinkPattern` that's just `source`; with one, it's
    /// the first link on the index page (= the latest release), resolved to an
    /// absolute URL. Nil when the index can't be fetched or yields no link — the
    /// caller then falls back.
    static func resolveDetailURL(
        _ recipe: ChangelogRecipe, source: URL, session: URLSession = .updates
    ) async -> URL? {
        guard let pattern = recipe.indexLinkPattern else { return source }
        guard let indexBody = await fetchBody(source, session: session) else { return nil }
        return firstLink(in: indexBody, pattern: pattern, base: source)
    }

    /// Pure (no network): the first `link` named group (else capture group 1) of
    /// `pattern` in `body`, resolved against `base`. Matched with the same options
    /// as `ChangelogExtractor` so a single pattern behaves identically here.
    /// Unit-testable against a saved index fixture.
    static func firstLink(in body: String, pattern: String, base: URL) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }
        let range = NSRange(body.startIndex..., in: body)
        guard let match = regex.firstMatch(in: body, range: range) else { return nil }
        let named = match.range(withName: "link")
        let nsRange = named.location != NSNotFound
            ? named
            : (match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0))
        guard nsRange.location != NSNotFound, let r = Range(nsRange, in: body) else { return nil }
        return URL(string: String(body[r]), relativeTo: base)?.absoluteURL
    }

    /// Fetch a URL with the browser-like UA and return its body as a string, or
    /// nil on network error / non-2xx. Shared by the index and detail fetches.
    private static func fetchBody(_ url: URL, session: URLSession) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Same reason as a version feed: a changelog *index* page gains its newest
        // entry in place, so a cached copy held "fresh" silently hides the release
        // we're trying to show notes for. (Per-version detail pages are immutable
        // and just 304 here.)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Convenience: look up a recipe by bundle id (and channel, for apps whose
    /// channels share a bundle id — Thunderbird Stable/ESR) and run it. Nil when
    /// there's no recipe for the app or the load fails.
    public static func load(
        forBundleID bundleID: String?,
        channel: ReleaseChannel? = nil,
        version: String? = nil,
        session: URLSession = .updates
    ) async -> Changelog? {
        guard let recipe = ChangelogRecipeRegistry.recipe(
            forBundleID: bundleID, channel: channel)
        else { return nil }
        return await load(recipe, version: version, session: session)
    }
}
