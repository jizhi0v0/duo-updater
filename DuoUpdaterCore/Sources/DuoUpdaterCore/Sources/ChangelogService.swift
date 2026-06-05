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
        // and concurrent-miss coalescing in one place.
        return await ChangelogCache.shared.load(for: resolved) {
            Log.source.debug(
                "changelog cache miss: \(resolved.host ?? "?", privacy: .public)")
            guard let pageURL = await resolveDetailURL(recipe, source: resolved, session: session),
                  let text = await fetchBody(pageURL, session: session)
            else { return nil }
            return ChangelogExtractor.extract(from: text, using: recipe)
        }
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
