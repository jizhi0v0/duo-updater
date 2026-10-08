import Foundation

/// What is left of the GitHub API's `core` budget, as its last answer said:
/// `x-ratelimit-limit`, `x-ratelimit-remaining`, `x-ratelimit-reset`. Settings ▸
/// GitHub shows it.
///
/// **Read, never asked for.** Every `api.github.com` fetch goes through
/// `countedData`, so `RequestMetricsRecorder` sees each one's metrics and hands
/// them to ``Store/observe(_:)``. Nothing is fetched to refresh it: asking
/// `/rate_limit` would be one more request, from the budget it reports.
///
/// **Only the answer that crossed the network counts.** `URLSession.updates`
/// revalidates its memory cache, and a revalidated fetch reports two
/// transactions for one URL: the cache lookup, carrying the headers stored with
/// the earlier response — its `x-ratelimit-remaining` included — then the
/// conditional request that went out, carrying today's. A fetch answered from
/// cache alone has only the lookup. So the headers are read off the last
/// `networkLoad` transaction. (The response `data(for:)` hands back is the
/// cached copy; on a loopback server, 2026-10-08, it carried the 304's count
/// merged in, but nothing here relies on that.)
///
/// **The headers are the only authority.** Measured 2026-10-08: anonymously the
/// budget is 60 an hour per IP address, shared with every other program behind
/// the same address, and a 304 spends one; with a token it is 5000 and a 304
/// spends none. What DuoUpdater sent says nothing of what is left.
///
/// Kept in memory, per process: `duo` records into its own, never the app's,
/// and the app starts out knowing nothing until its first API answer.
public struct GitHubRateBudget: Sendable, Equatable {
    public let limit: Int
    public let remaining: Int
    /// When the window ends and `remaining` is back to `limit`.
    public let reset: Date

    public init(limit: Int, remaining: Int, reset: Date) {
        self.limit = limit
        self.remaining = remaining
        self.reset = reset
    }

    /// Whether the window it describes is still running. After `reset` the count
    /// is history: the budget has refilled, less whatever else spent it since.
    public func isCurrent(at now: Date) -> Bool { reset > now }

    /// The budget an answer states; nil without all three headers, or for a
    /// budget other than `core` — search and GraphQL count apart.
    init?(_ response: HTTPURLResponse) {
        guard response.value(forHTTPHeaderField: "x-ratelimit-resource")?.lowercased() == "core",
              let limit = response.value(forHTTPHeaderField: "x-ratelimit-limit").flatMap({ Int($0) }),
              let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap({ Int($0) }),
              let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap({ TimeInterval($0) })
        else { return nil }
        self.init(limit: limit, remaining: remaining, reset: Date(timeIntervalSince1970: reset))
    }

    /// The budget stated by the last transaction in `metrics` that went to the
    /// network and to the API; nil when there is none — a fetch answered from
    /// cache alone, or another host.
    static func reading(
        from metrics: URLSessionTaskMetrics, isAPI: (URL) -> Bool = ChangelogService.isGitHubAPI
    ) -> GitHubRateBudget? {
        for transaction in metrics.transactionMetrics.reversed() where transaction.resourceFetchType == .networkLoad {
            guard let url = transaction.request.url, isAPI(url),
                  let http = transaction.response as? HTTPURLResponse
            else { continue }
            return GitHubRateBudget(http)
        }
        return nil
    }

    /// What to keep when `seen` arrives with `kept` on hand. Concurrent requests
    /// finish out of order, so within one window — same limit, same reset — the
    /// lower count is the later one. A later window replaces it, an earlier one
    /// arriving late does not, and a different limit (a token added or removed)
    /// is a different budget altogether.
    static func keeping(_ kept: GitHubRateBudget?, _ seen: GitHubRateBudget) -> GitHubRateBudget {
        guard let kept, kept.limit == seen.limit else { return seen }
        if seen.reset != kept.reset { return seen.reset > kept.reset ? seen : kept }
        return seen.remaining < kept.remaining ? seen : kept
    }

    /// The process's reading.
    public final class Store: @unchecked Sendable {
        public static let shared = Store()

        private let lock = NSLock()
        private var budget: GitHubRateBudget?
        private let isAPI: @Sendable (URL) -> Bool

        /// `isAPI` is a test seam: a loopback server is not `api.github.com`.
        init(isAPI: @escaping @Sendable (URL) -> Bool = ChangelogService.isGitHubAPI) {
            self.isAPI = isAPI
        }

        /// nil until an API answer has been seen.
        public var latest: GitHubRateBudget? { lock.withLock { budget } }

        func observe(_ metrics: URLSessionTaskMetrics) {
            guard let seen = GitHubRateBudget.reading(from: metrics, isAPI: isAPI) else { return }
            lock.withLock { budget = GitHubRateBudget.keeping(budget, seen) }
        }
    }
}
