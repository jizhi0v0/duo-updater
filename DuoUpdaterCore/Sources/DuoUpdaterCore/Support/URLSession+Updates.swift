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
    /// - **Private, memory-only URL cache** (16 MB). Update sources rely on
    ///   standard HTTP caching (`ETag`/`If-None-Match`, `Cache-Control:
    ///   max-age`) — Sparkle appcast feeds and GitHub's `/releases/latest`
    ///   endpoint all send reuse-friendly headers. Caveat: cache *freshness* is
    ///   never trusted for a version feed — every source sets
    ///   ``URLRequest/versionFeedCachePolicy`` (see it for why). `ChangelogService`
    ///   also uses this session, and 16 MB keeps several pages resident without
    ///   evicting update-check responses. A private cache prevents eviction by
    ///   unrelated `.shared` activity.
    ///
    ///   **`diskCapacity` is 0, and that is a security boundary, not a tuning
    ///   knob.** This session carries credentials: a GitHub PAT as `Authorization`
    ///   (`GitHubReleasesSource`, `BrewFormulaReleaseService`, `GitHubToken`),
    ///   Alcove's Bearer and the licence key it POSTs to get one, and CleanShot's
    ///   activation key in a feed's query string. CFNetwork archives the **whole**
    ///   `URLRequest` — URL, headers, body — into `cfurl_cache_blob_data`, so a
    ///   disk store means those secrets sit in plaintext SQLite under
    ///   `~/Library/Caches`, readable by anything running as the user and copied
    ///   into every unencrypted backup. That is not hypothetical: 85 blobs holding
    ///   a live PAT were found across this app's and the CLI's caches on
    ///   2026-08-22.
    ///
    ///   The obvious fix — refuse the write in `willCacheResponse` — **cannot
    ///   work here**, which is exactly how this went unnoticed. Every request on
    ///   this session goes out through `data(for:)`, and `NSURLSession.h` is
    ///   explicit about what that costs: "If you create a task using a method that
    ///   takes a completion handler block, the delegate methods for response and
    ///   data delivery are not called." `willCacheResponse` is one of those, so
    ///   the guard below never runs for this session — measured, not inferred, and
    ///   pinned by `CredentialCacheDelegateBypassTests`. The response is cached
    ///   anyway; only the *veto* is skipped. With no disk store there is nothing
    ///   to veto: the cost is that a fresh process re-fetches small feeds it could
    ///   have revalidated, and nothing more. Bodies big enough to matter were
    ///   never on disk regardless — `URLCache` refuses anything over ~5% of
    ///   capacity, which already excluded the 5 MB Homebrew Cask catalog.
    ///
    /// - **Short request timeout** (`timeoutIntervalForRequest = 15 s`). Sources
    ///   already set this per-request; the session-level setting acts as a safe
    ///   backstop for any request that forgets to.
    /// The largest body a version probe pulls, measured rather than guessed:
    /// `download.scdn.co/SpotifyInstaller.zip`, 1,868,156 bytes on 2026-09-04.
    ///
    /// Spotify publishes no cheap version API, so its recipe reads the version
    /// out of a zip entry inside this stub installer — see `VendorProbeRecipe`.
    static let largestProbeBody = 1_868_156

    /// Sized so the largest probe body is actually cached.
    ///
    /// **`URLCache` silently refuses to store a response larger than about 5% of
    /// its capacity.** Measured on 2026-09-04 against this exact object: not
    /// stored at 32 MB (5.6% of capacity), stored at 40 MB (4.5%). Apple does
    /// not document the ratio, so the guard below pins the measurement rather
    /// than the rule.
    ///
    /// This is not a tuning preference. With the old 16 MB the Spotify probe was
    /// never cached, so `reloadRevalidatingCacheData` had no validator to send
    /// and every single check re-downloaded the whole 1.87 MB: 92 checks on one
    /// machine came to **160 MB**, the largest update-check cost by an order of
    /// magnitude and more than every other app's checks put together. With the
    /// response cached, the same check is a 304 — **238 wire bytes**, measured.
    ///
    /// A capacity is a ceiling, not an allocation: the session holds only what
    /// it has actually fetched.
    static let updatesCacheCapacity = 64 * 1024 * 1024

    static let updates: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 90
        config.urlCache = URLCache(
            memoryCapacity: URLSession.updatesCacheCapacity,
            diskCapacity:   0                    // see above — credentials must not reach disk
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

    /// Backstop only — **this is not what keeps credentials out of the cache.**
    ///
    /// It reads like the load-bearing guard and was treated as one for a long
    /// time, so start with what it cannot do: `URLSession` does not call
    /// response-delivery delegate methods for a task created with a completion
    /// handler, and `data(for:)` is that path. `NSURLSession.h` states it flatly —
    /// "If you create a task using a method that takes a completion handler block,
    /// the delegate methods for response and data delivery are not called" — and a
    /// probe against a loopback server confirms it: zero calls here, response
    /// cached anyway. Every request on this session uses `data(for:)`, so this
    /// method never runs for `URLSession.updates`. `URLSession.updates` is safe
    /// because its cache has no disk store, not because of anything below.
    ///
    /// Kept because it is free and correct wherever it *does* run — a
    /// delegate-driven `dataTask` on this session, should one ever be added — and
    /// because `Downloader` has the same guard on a session where tasks really are
    /// delegate-driven, so the predicate earns its keep there.
    ///
    /// See `CredentialBearingURL` for what the query half does and does not
    /// promise: it recognizes credential-like parameter *names*, so it is a
    /// backstop, not a guarantee that any future credential in a URL is handled
    /// for free.
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping (CachedURLResponse?) -> Void
    ) {
        completionHandler(CredentialBearingRequest.isCredentialed(
            original: dataTask.originalRequest, current: dataTask.currentRequest)
                          ? nil : proposedResponse)
    }
}

/// Whether an exchange carried a credential in any of the three places one can
/// hide in a request CFNetwork archives: the query, an `Authorization`-style
/// header, or the body.
enum CredentialBearingRequest {
    /// Headers that are a credential by definition. `Proxy-Authorization` is here
    /// for completeness — URLSession sets it when a proxy demands auth, and the
    /// user's own proxy password has no business in a version-feed cache either.
    static let credentialHeaders = ["Authorization", "Proxy-Authorization"]

    static func isCredentialed(original: URLRequest?, current: URLRequest?) -> Bool {
        [original, current].compactMap { $0 }.contains(where: isCredentialed)
    }

    static func isCredentialed(_ request: URLRequest) -> Bool {
        if CredentialBearingURL.inQuery(request.url) { return true }
        if credentialHeaders.contains(where: { request.value(forHTTPHeaderField: $0) != nil }) {
            return true
        }
        // A body is the third hiding place, and unlike the other two we can't
        // inspect it by name: `AlcoveUpdateSource.issueToken` POSTs the licence key
        // and instance id as JSON, and that blob was landing in `Cache.db` too.
        // Nothing here depends on a cached POST — every feed already sets
        // `versionFeedCachePolicy`, so the cost of dropping these entries is a full
        // body instead of a 304 on the one Omaha-style probe that posts at all.
        return request.httpBody != nil || request.httpBodyStream != nil
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
