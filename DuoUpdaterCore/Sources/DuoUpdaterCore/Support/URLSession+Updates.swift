import Foundation

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
    ///   `ChangelogService` also uses this session, and changelog pages (GitHub
    ///   Releases HTML, Homebrew formula pages) can be 1–2 MB each — 16 MB
    ///   keeps several pages in memory without evicting update-check responses.
    ///   A private cache prevents eviction by unrelated `.shared` activity and
    ///   gives all update/changelog traffic its own disk quota.
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
        return URLSession(configuration: config)
    }()
}
