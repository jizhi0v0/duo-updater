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
            let parsed = await fetchAndParse(recipe, resolved: resolved, session: session)
            // Recipe health is recorded here, inside the cache-miss closure, so an
            // in-memory hit doesn't re-assert an outcome it never re-tested.
            await recordHealth(recipe, parsed: parsed)
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

    /// Fetch and parse with **both** caches bypassed, for verification sweeps.
    ///
    /// `load` is the right entry point for the UI and the wrong one for a
    /// checker: a warm in-memory slot or a disk-cached entry would let a recipe
    /// that has been broken for weeks keep reporting success without a single
    /// request leaving the machine.
    public static func loadUncached(
        _ recipe: ChangelogRecipe, version: String? = nil, session: URLSession = .updates
    ) async -> Changelog? {
        await loadDiagnostic(recipe, version: version, session: session).changelog
    }

    /// What a changelog load actually did, for a verifier that has to decide
    /// whether a human should be paged.
    ///
    /// Without this every failure looks like "the pattern stopped matching",
    /// because that's the only shape `load` can express. The first sweep flagged
    /// Typeless as a pattern failure when in fact `www.typeless.com/changelog`
    /// now returns 404 — a completely different fix, and one the report was
    /// actively pointing away from.
    public struct ChangelogDiagnostic: Sendable {
        public let changelog: Changelog?
        /// The page actually requested, after `{version}` templating.
        public let resolvedURL: URL
        /// Non-nil when the request completed; nil when it never got that far.
        public let httpStatus: Int?
        public let fetchFailed: Bool
        /// Present on a parse failure — the evidence needed to repair a pattern.
        public let bodySample: String?
        /// For a two-stage recipe (`indexLinkPattern`), the per-release page the
        /// index pointed at — the request the patterns actually run against. Nil
        /// for a one-stage recipe, and nil when the index yielded no link.
        public let detailURL: URL?
        /// True when that second request failed outright. Without this a stalled
        /// or moved detail page is indistinguishable from a pattern that stopped
        /// matching: `resolvedURL` fetched fine, so the report blamed the entry
        /// pattern and quoted a regex that was never even run. (HBuilderX Alpha,
        /// 2026-08-16: a 15 s timeout on a 632 KB detail page, reported as
        /// `noEntriesExtracted` against a pattern that still matched the page.)
        public let detailFetchFailed: Bool
        /// Status of that second request, when it completed with a non-2xx.
        public let detailHTTPStatus: Int?

        public init(
            changelog: Changelog?, resolvedURL: URL, httpStatus: Int?, fetchFailed: Bool,
            bodySample: String?, detailURL: URL? = nil, detailFetchFailed: Bool = false,
            detailHTTPStatus: Int? = nil
        ) {
            self.changelog = changelog
            self.resolvedURL = resolvedURL
            self.httpStatus = httpStatus
            self.fetchFailed = fetchFailed
            self.bodySample = bodySample
            self.detailURL = detailURL
            self.detailFetchFailed = detailFetchFailed
            self.detailHTTPStatus = detailHTTPStatus
        }
    }

    public static func loadDiagnostic(
        _ recipe: ChangelogRecipe, version: String? = nil, session: URLSession = .updates
    ) async -> ChangelogDiagnostic {
        let resolved = recipe.resolvedSource(forVersion: version)
        // Fetch the entry page directly so a transport/status failure is
        // distinguishable; `fetchAndParse` collapses both into nil. Pass the
        // recipe through so a POST recipe (Notion) sends its body on this,
        // its ONLY request — there is no second stage for a structured recipe.
        let fetched = await fetch(resolved, recipe: recipe, session: session)
        guard fetched.body != nil else {
            await recordHealth(recipe, parsed: nil)
            return ChangelogDiagnostic(
                changelog: nil, resolvedURL: resolved, httpStatus: fetched.status,
                fetchFailed: true, bodySample: nil)
        }
        // Reuse the body already in hand and run the second stage here, so its
        // outcome survives into the diagnostic instead of collapsing to nil.
        let indexBody = fetched.body ?? ""
        var detailURL: URL?
        var detailFetch: (body: String?, status: Int?) = (indexBody, fetched.status)
        if recipe.structuredFormat == nil, let linkPattern = recipe.indexLinkPattern {
            detailURL = firstLink(in: indexBody, pattern: linkPattern, base: resolved)
            if let detailURL {
                detailFetch = await fetch(detailURL, session: session)
            } else {
                // The index fetched but carried no link: a real pattern failure,
                // and one about the INDEX pattern rather than the entry pattern.
                detailFetch = (nil, nil)
            }
        }
        let parsed = parse(recipe, body: detailFetch.body)
        await recordHealth(recipe, parsed: parsed)
        return ChangelogDiagnostic(
            changelog: parsed, resolvedURL: resolved, httpStatus: fetched.status,
            // The body is returned even when parsing succeeded. "Extracted
            // entries, but the newest one trails the version the app is being
            // offered" is a real finding about *this page*, and answering it
            // needs the page — without it the report says a recipe is reading a
            // stale section and then withholds the section. Callers keep the
            // sample only for findings worth acting on.
            fetchFailed: false, bodySample: detailFetch.body ?? fetched.body,
            detailURL: detailURL,
            detailFetchFailed: detailURL != nil && detailFetch.body == nil,
            detailHTTPStatus: detailURL == nil ? nil : detailFetch.status)
    }

    /// The fetch + parse half, shared by the cached and uncached entry points so
    /// a sweep exercises exactly the path the app does.
    private static func fetchAndParse(
        _ recipe: ChangelogRecipe, resolved: URL, session: URLSession
    ) async -> Changelog? {
        if recipe.structuredFormat != nil {
            return parse(recipe, body: await fetchBody(resolved, recipe: recipe, session: session))
        }
        guard let pageURL = await resolveDetailURL(recipe, source: resolved, session: session)
        else { return nil }
        return parse(recipe, body: await fetchBody(pageURL, recipe: recipe, session: session))
    }

    /// Turn a fetched page into entries, by whichever route the recipe declares.
    /// Pure: both the cached path and the diagnostic path go through it, so a
    /// sweep can never parse differently from the app.
    private static func parse(_ recipe: ChangelogRecipe, body: String?) -> Changelog? {
        guard let body else { return nil }
        if let format = recipe.structuredFormat {
            return StructuredChangelogDecoder.decode(
                body, format: format, channel: recipe.channel, maxEntries: recipe.maxEntries)
        }
        return ChangelogExtractor.extract(from: body, using: recipe)
    }

    /// A changelog recipe is as fragile as a probe recipe and, until now,
    /// recorded nothing at all: a vendor restyling their release-notes page made
    /// `extract` return nil, the UI quietly fell back to embedding the raw page
    /// in a web view, and no diagnostic anywhere said the recipe had died.
    private static func recordHealth(_ recipe: ChangelogRecipe, parsed: Changelog?) async {
        let id = recipe.recipeID
        if parsed != nil {
            await RecipeHealth.shared.recordSuccess(id: id, source: "Changelog")
        } else {
            await RecipeHealth.shared.recordMiss(
                id: id, source: "Changelog",
                detail: "fetched \(recipe.source.host ?? "?") but extracted no entries")
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


    /// STRICTLY api.github.com. The Authorization header must never ride along to
    /// some other vendor's changelog host just because a recipe happens to point
    /// at a URL containing "github" (raw.githubusercontent.com hosts TablePro's
    /// appcast, for one) — a credential leak is a much worse failure than a rate
    /// limit.
    static func isGitHubAPI(_ url: URL) -> Bool {
        // Scheme checked too: `URL.host` is scheme-agnostic, so without this an
        // `http://api.github.com/…` recipe would send the token in the clear. No
        // such recipe exists and ATS would refuse the load anyway — but a CLI
        // binary's ATS posture is not the app's, and this is one comparison.
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "api.github.com"
    }

    /// The token the user pasted into Settings ▸ GitHub, pushed down by the app.
    ///
    /// `GitHubToken.resolve()` on its own reads only the process environment and
    /// `gh auth token`. Neither exists for the shipped app: launchd starts it with
    /// no shell environment, and a machine without `gh` installed keeps the token
    /// in the Keychain, where only `Preferences` can reach it. Resolving without
    /// an explicit value therefore came back nil for exactly the users who
    /// configured a token the supported way, leaving the whole Authorization path
    /// dead while Settings showed the token verified green. The CLI has no
    /// Settings, so it keeps the env/`gh` path and nothing is set here.
    private nonisolated(unsafe) static var explicitToken: String?

    /// Hand the Settings token to the changelog fetcher. Called on load and from
    /// `Preferences.githubToken`'s `didSet`, so pasting or clearing a token takes
    /// effect without a relaunch (the next resolve sees a different explicit value
    /// and re-resolves rather than serving the cached one).
    public static func setExplicitGitHubToken(_ token: String?) {
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        tokenLock.lock()
        defer { tokenLock.unlock() }
        explicitToken = (normalized?.isEmpty ?? true) ? nil : normalized
    }

    /// A resolved token, remembered so `gh auth token` isn't re-spawned on every
    /// changelog open. Keyed by the explicit value it was resolved from, and aged
    /// out: a token revoked mid-session (`gh auth logout`, a rotated PAT) makes
    /// GitHub answer 401, which is *worse* than sending nothing — the pane goes
    /// empty where anonymous would still have rendered. A menubar app runs for
    /// weeks, so "resolved once per process" would strand it there until relaunch.
    private struct ResolvedToken {
        let explicit: String?
        let token: String?
        let at: Date
    }
    private nonisolated(unsafe) static var cachedToken: ResolvedToken?
    private static let tokenLock = NSLock()
    /// Long enough that a burst of changelog opens shares one resolve, short
    /// enough that a rotation recovers on its own within a coffee break.
    static let tokenTTL: TimeInterval = 600

    /// Lock-taking halves kept out of the async function on purpose: `NSLock`'s
    /// `unlock()` is unavailable from an async context (holding a lock across a
    /// suspension point is exactly the bug this whole change is about), so the
    /// critical sections are these two synchronous calls with the `await` between
    /// them, never inside them.
    private static func rememberedToken(now: Date) -> (explicit: String?, hit: String??) {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        let explicit = explicitToken
        if let cached = cachedToken,
           cached.explicit == explicit,
           now.timeIntervalSince(cached.at) < tokenTTL {
            return (explicit, .some(cached.token))
        }
        return (explicit, nil)
    }

    private static func rememberToken(_ token: String?, explicit: String?, at now: Date) {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        cachedToken = ResolvedToken(explicit: explicit, token: token, at: now)
    }

    static func gitHubToken(now: Date = Date()) async -> String? {
        let (explicit, hit) = rememberedToken(now: now)
        if let hit { return hit }

        // Resolved *outside* the lock and off the cooperative pool, with a
        // deadline. `GitHubToken.resolve` runs `gh auth token` to completion with
        // no timeout of its own, so a wedged credential helper (a keychain prompt
        // nobody answers) would otherwise pin the lock forever and pile the whole
        // changelog prewarm fan-out up behind it. `AppListModel.resolveGitHubToken`
        // learned this already — "don't let a wedged `gh auth token` hold the
        // whole refresh hostage forever" — and the lesson belongs here too.
        let loader = Task.detached(priority: .utility) { GitHubToken.resolve(explicit: explicit) }
        guard let resolved = await firstResult(of: loader, within: .seconds(2)) else {
            // Timed out: deliberately *not* cached. Caching would extend one
            // wedged `gh` into ten minutes of unauthenticated fetches; falling
            // through unauthenticated for this one request is enough.
            Log.source.error("changelog GitHub token resolve timed out — continuing anonymous")
            return nil
        }

        rememberToken(resolved, explicit: explicit, at: now)

        // `.notice`, not `.debug`: a third-party subsystem's debug/info lines are
        // not persisted, and this one answers "am I exposed to the 60/hour
        // unauthenticated limit right now?" — exactly what you want to be able to
        // read back after the fact. At most once per TTL, so it costs nothing.
        Log.source.notice(
            "changelog GitHub auth: \(resolved != nil ? "token" : "anonymous", privacy: .public)")
        return resolved
    }

    /// The value of `task` if it lands within `timeout`, else nil. The task is a
    /// detached one on purpose (see the call site) so its blocking `waitUntilExit`
    /// never occupies a cooperative-pool thread; cancelling the group cannot stop
    /// it, and doesn't need to — it finishes into a discarded result.
    private static func firstResult<T: Sendable>(
        of task: Task<T, Never>, within timeout: Duration
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Test seam: the normalized explicit token, without resolving anything.
    static var explicitGitHubTokenForTesting: String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return explicitToken
    }

    /// Test seam: forget any resolved token so the next call re-resolves.
    static func resetGitHubTokenCache() {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        cachedToken = nil
    }

    /// Fetch a URL with the browser-like UA and return its body as a string, or
    /// nil on network error / non-2xx. Shared by the index and detail fetches.
    /// `recipe` is nil for a plain GET (every regex/HTML recipe, and both stages
    /// of a two-stage index/detail recipe); pass it only for the single request a
    /// structured recipe makes, so a `.post` recipe's method/body actually rides
    /// along (see `fetch(_:recipe:session:)`).
    private static func fetchBody(
        _ url: URL, recipe: ChangelogRecipe? = nil, session: URLSession
    ) async -> String? {
        await fetch(url, recipe: recipe, session: session).body
    }

    /// The same request, but keeping the status code so a verifier can tell a
    /// moved page from a restyled one.
    ///
    /// `recipe` supplies the HTTP method and body (see `ChangelogRecipe.httpMethod`/
    /// `requestBody`) — nil means the plain-GET default every recipe used before
    /// Notion. Only the one request a caller explicitly threads a recipe through
    /// can ever be a POST; every other fetch in this file (the two-stage index
    /// page, its detail page) is hard-coded to GET by simply not passing one.
    private static func fetch(
        _ url: URL, recipe: ChangelogRecipe? = nil, session: URLSession
    ) async -> (body: String?, status: Int?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Same reason as a version feed: a changelog *index* page gains its newest
        // entry in place, so a cached copy held "fresh" silently hides the release
        // we're trying to show notes for. (Per-version detail pages are immutable
        // and just 304 here.)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let recipe, recipe.httpMethod == .post {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = recipe.requestBody
        }
        // A recipe may read the GitHub API (Zed's notes come from the same
        // `/releases` endpoint the version check already uses). Unauthenticated
        // that is 60 requests/hour PER IP, shared with every GitHub-sourced
        // version check on the machine — and a full `duo verify` sweep spends two
        // of them on Zed alone, so the recipes turned up as HTTP 403 "BROKEN"
        // while a perfectly good token sat in `gh` unused. Same token the
        // GitHub source sends; 5000/hour once attached.
        if isGitHubAPI(url) {
            // The same two headers `GitHubReleasesSource` sends: without them the
            // API answers from whatever version it currently defaults to, which is
            // exactly the kind of silent drift a pinned version exists to prevent.
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let token = await gitHubToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        guard let (data, response) = try? await session.data(for: request) else {
            return (nil, nil)
        }
        guard let http = response as? HTTPURLResponse else { return (nil, nil) }
        guard (200..<300).contains(http.statusCode) else { return (nil, http.statusCode) }
        return (String(decoding: data, as: UTF8.self), http.statusCode)
    }

    /// Convenience: look up a recipe by bundle id (and channel, for apps whose
    /// channels share a bundle id — Thunderbird Stable/ESR) and run it. Nil when
    /// there's no recipe for the app or the load fails.
    ///
    /// `version` reaches the LOOKUP as well as the load: an app can fork its notes
    /// across two pages that share a bundle id and a channel, and then the version
    /// is the only thing that says which page describes this build (Raycast v1/v2).
    public static func load(
        forBundleID bundleID: String?,
        channel: ReleaseChannel? = nil,
        version: String? = nil,
        session: URLSession = .updates
    ) async -> Changelog? {
        guard let recipe = ChangelogRecipeRegistry.recipe(
            forBundleID: bundleID, channel: channel, version: version)
        else { return nil }
        return await load(recipe, version: version, session: session)
    }
}
