import Foundation

public extension URLRequest {

    /// The cache policy every *version feed* request must use.
    ///
    /// A version feed is the one thing in this app that must never be answered
    /// from cache without asking the server, because a stale answer is silent:
    /// the probe succeeds, reports the old version, and the row reads "up to
    /// date" with no error anywhere. Two ways the default
    /// `.useProtocolCachePolicy` produces exactly that:
    ///
    /// - **A decade-long `max-age`.** Some vendor CDNs stamp one on an appcast
    ///   (Fork's did), pinning us to that copy essentially forever.
    /// - **No `Cache-Control` at all.** Then `URLCache` falls back to *heuristic*
    ///   freshness — roughly 10% of the document's age — so the longer a feed
    ///   sits unchanged, the longer a stale copy is served without a request.
    ///   OrbStack's appcast (ETag + Last-Modified, no `Cache-Control`) hid
    ///   2.2.1 → 2.2.2 this way.
    ///
    /// `.reloadRevalidatingCacheData` keeps the cache but always asks: the
    /// conditional request 304s when nothing changed, so this costs headers, not
    /// payload. Set it per-request rather than on the session configuration —
    /// a `URLRequest` carries `.useProtocolCachePolicy` from birth, so the
    /// request-level value is what actually takes effect.
    ///
    /// Applies to the *feed*, not the download: installer bytes are fetched by
    /// `Downloader` on its own session and are content-addressed by URL.
    static let versionFeedCachePolicy: CachePolicy = .reloadRevalidatingCacheData
}

public extension URLSession {

    /// Shared session for all update-check network requests.
    ///
    /// Kept separate from `.shared` so update-check traffic (dozens of
    /// concurrent requests during a fan-out) doesn't compete with unrelated
    /// in-process network activity. Three deliberate tweaks over the default:
    ///
    /// - **Higher per-host connection limit** (`httpMaximumConnectionsPerHost = 8`
    ///   vs. the default 6). During a full update check with `maxConcurrency = 12`,
    ///   multiple apps may hit the same host concurrently — `api.github.com` in
    ///   particular. Raising the limit avoids connection queuing on hosts that
    ///   *don't* support HTTP/2 multiplexing.
    ///
    /// - **Private URL cache** (16 MB memory / 20 MB disk). Update sources rely
    ///   on standard HTTP caching (`ETag`/`If-None-Match`, `Cache-Control:
    ///   max-age`) — Sparkle appcast feeds, the 5 MB Homebrew Cask catalog, and
    ///   GitHub's `/releases/latest` endpoint all send reuse-friendly headers.
    ///   Caveat: cache *freshness* is never trusted for a version feed — every
    ///   source sets ``URLRequest/versionFeedCachePolicy`` (see it for why).
    ///   `ChangelogService` also uses this session, and changelog pages (GitHub
    ///   Releases HTML, Homebrew formula pages) can be 1–2 MB each — 16 MB
    ///   keeps several pages in memory without evicting update-check responses.
    ///   A private cache prevents eviction by unrelated `.shared` activity and
    ///   gives all update/changelog traffic its own disk quota. Responses whose
    ///   URL carries a credential in the query are excluded from it entirely —
    ///   see `CrossHostCredentialStripper.willCacheResponse`.
    ///
    /// - **Short request timeout** (`timeoutIntervalForRequest = 15 s`). Sources
    ///   already set this per-request; the session-level setting acts as a safe
    ///   backstop for any request that forgets to.
    static let updates: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 90
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,   // 16 MB (update feeds + changelog pages)
            diskCapacity:   20 * 1024 * 1024     // 20 MB
        )
        // A redirect delegate that strips credential headers on a cross-host hop:
        // GitHub API requests carry `Authorization: Bearer <token>`, and a 3xx to a
        // different host would otherwise forward it to the redirect target.
        return URLSession(
            configuration: config,
            delegate: CrossHostCredentialStripper(),
            delegateQueue: nil)
    }()
}

/// Drops `Authorization`/`Cookie` from a redirect that crosses to a different host,
/// so a token meant for one API can't leak to a third party; otherwise follows the
/// redirect unchanged. Stateless, so safe to share across the session's tasks.
private final class CrossHostCredentialStripper: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var forwarded = request
        if request.url?.host != task.originalRequest?.url?.host {
            for field in ["Authorization", "Cookie", "Proxy-Authorization"] {
                forwarded.setValue(nil, forHTTPHeaderField: field)
            }
        }
        completionHandler(forwarded)
    }

    /// Keep credential-bearing URLs out of the on-disk cache.
    ///
    /// `URLCache` keys entries on the **full** request URL, so a feed whose licence
    /// lives in the query string — `CleanShotChannel`'s personalised appcast is the
    /// one in the tree today — would leave that key sitting in plaintext in
    /// `Cache.db`, readable by any process running as the user and copied into every
    /// unencrypted backup. Credentials passed as headers (Alcove's Bearer) never
    /// enter the cache key, so this only has to police the query.
    ///
    /// Session-wide rather than a per-source opt-out, but see `CredentialBearingURL`
    /// for what that does and does not promise: it recognizes credential-like
    /// parameter *names*, so it is a backstop, not a guarantee that any future
    /// credential in a URL is handled for free.
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping (CachedURLResponse?) -> Void
    ) {
        completionHandler(CredentialBearingURL.inQuery(dataTask.currentRequest?.url)
                          ? nil : proposedResponse)
    }
}

/// Whether a URL's query uses a **recognized** credential-like parameter name.
///
/// Deliberately not billed as "anything secret is safe automatically": this matches
/// names, and a name it has never seen (or a secret embedded in the path rather than
/// the query) slips through. It is the backstop, not the plan — a source that puts a
/// credential in a URL should still be reviewed on its own terms.
enum CredentialBearingURL {
    /// Compared after folding `_`, `-` and `.` out of the parameter name, so one
    /// entry covers `api_key`, `api-key` and `apikey` alike.
    static let sensitiveNames: Set<String> = [
        "key", "apikey", "token", "accesstoken", "refreshtoken", "idtoken",
        "secret", "clientsecret", "password", "passwd", "pwd", "credential",
        "licence", "license", "licensekey", "activationkey", "auth", "authtoken",
        "signature", "sig", "sessionid", "sessiontoken",
    ]

    static func inQuery(_ url: URL?) -> Bool {
        guard let url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return false }
        return items.contains { isSensitive($0.name) }
    }

    /// Match the folded name exactly, or as a separator-delimited tail of it, so
    /// `x_api_key` and `user-token` count while `monkey`, `keyboard` and `design`
    /// (which merely contain a sensitive word) do not.
    static func isSensitive(_ rawName: String) -> Bool {
        let folded = rawName.lowercased().filter { $0 != "_" && $0 != "-" && $0 != "." }
        if sensitiveNames.contains(folded) { return true }
        // Tail match only on a real separator boundary in the original name.
        let segments = rawName.lowercased().split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == "." })
        guard let last = segments.last, segments.count > 1 else { return false }
        return sensitiveNames.contains(String(last))
    }
}
