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
/// **One reading per window, not one reading.** Observed 2026-10-08 with a gh
/// token: GitHub answered from two `core` windows at once for the same token,
/// both limit 5000, chosen by endpoint — `/repos/{o}/{r}/releases/latest`
/// (remaining ~3,945, reset 15:30:50 UTC+8) against `/repos/{o}/{r}`,
/// `releases?per_page=1` and `/rate_limit` (remaining ~4,200, reset 15:10:57),
/// each stable over repeated samples. Anonymous answers showed one window. GitHub's
/// documentation does not describe this; it is an observation. A single reading
/// that let the later reset win showed one of the two budgets and flipped at the
/// other's rollover, so each window (a reset time, within one limit) is kept on
/// its own until it ends.
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

    /// Under a fifth of the limit left: Settings draws the window's bar orange.
    public var isRunningLow: Bool { remaining * 5 < limit }

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

    /// Windows kept at most. Two have been seen at once (2026-10-08); a reset
    /// that ever drifted between answers would make each its own window, and
    /// this keeps that from growing without end.
    static let windowCap = 3

    /// The windows to keep when `seen` arrives at `now` with `kept` on hand,
    /// earliest reset first.
    ///
    /// - A window is a reset time within one limit. Concurrent requests finish
    ///   out of order, so within one the lower count is the later answer.
    /// - A different limit (a token added or removed) is another budget: every
    ///   window kept is dropped.
    /// - A window whose reset has passed is over, and an answer from one is not
    ///   kept.
    /// - Past `windowCap`, the windows that end soonest go.
    static func keeping(_ kept: [GitHubRateBudget], _ seen: GitHubRateBudget, now: Date) -> [GitHubRateBudget] {
        var windows = kept.filter { $0.limit == seen.limit && $0.isCurrent(at: now) }
        if seen.isCurrent(at: now) {
            if let index = windows.firstIndex(where: { $0.reset == seen.reset }) {
                if seen.remaining < windows[index].remaining { windows[index] = seen }
            } else {
                windows.append(seen)
            }
        }
        windows.sort { $0.reset < $1.reset }
        return Array(windows.suffix(windowCap))
    }

    /// The process's windows.
    ///
    /// **Only the credentials in use now.** A change in Settings (the token
    /// saved or removed, the GitHub CLI switch flipped) starts a new
    /// `GitHubCredentials` generation, and every window read under an older one
    /// goes: the store reads as empty — "No answer from GitHub yet" — until an
    /// answer to a request made under the new credentials lands. Each request is
    /// tagged with its generation where it is made (`RequestMetricsRecorder`), so
    /// an answer that lands after the change from a request made before it is
    /// ignored, and so is one from a round still checking with the old token,
    /// which runs under the generation it started in
    /// (`GitHubCredentials.pinnedGeneration`). Without this the card flipped
    /// between the old round's limit and the new one's until that round drained,
    /// since a different limit drops every window.
    public final class Store: @unchecked Sendable {
        public static let shared = Store()

        private let lock = NSLock()
        /// Earliest reset first. Some may have ended since they were kept.
        private var windows: [GitHubRateBudget] = []
        /// The credentials generation `windows` were read under.
        private var windowsGeneration: Int
        private let isAPI: @Sendable (URL) -> Bool
        private let credentials: GitHubCredentials

        /// `isAPI` is a test seam: a loopback server is not `api.github.com`.
        /// So is `credentials`, which only `.shared` changes in the app.
        init(
            isAPI: @escaping @Sendable (URL) -> Bool = ChangelogService.isGitHubAPI,
            credentials: GitHubCredentials = .shared
        ) {
            self.isAPI = isAPI
            self.credentials = credentials
            self.windowsGeneration = credentials.generation
        }

        /// The windows still running at `now`, earliest reset first; empty
        /// before any API answer, once every window seen has ended, and after a
        /// credential change until the new credentials' first answer.
        public func current(at now: Date) -> [GitHubRateBudget] {
            let generation = credentials.generation
            return lock.withLock {
                windowsGeneration == generation ? windows.filter { $0.isCurrent(at: now) } : []
            }
        }

        /// The latest reset among the windows kept; nil before any API answer,
        /// and after a credential change until the new credentials' first one.
        /// Once `current` is empty, when the budget last refilled.
        public var lastReset: Date? {
            let generation = credentials.generation
            return lock.withLock { windowsGeneration == generation ? windows.map(\.reset).max() : nil }
        }

        /// The generation a request made now, in the calling task, is sent under.
        func requestGeneration() -> Int { credentials.requestGeneration() }

        func observe(_ metrics: URLSessionTaskMetrics, generation: Int) {
            guard let seen = GitHubRateBudget.reading(from: metrics, isAPI: isAPI) else { return }
            record(seen, now: Date(), generation: generation)
        }

        /// `generation` is the one the request was made under; nil, for a test
        /// with no request, means the current one.
        func record(_ seen: GitHubRateBudget, now: Date, generation: Int? = nil) {
            let current = credentials.generation
            // Read under credentials since replaced: not the budget in use now.
            guard (generation ?? current) == current else { return }
            lock.withLock {
                if windowsGeneration != current {
                    windows = []
                    windowsGeneration = current
                }
                let next = GitHubRateBudget.keeping(windows, seen, now: now)
                // Empty only when `seen` had itself ended: the windows that ended
                // before it still say when the budget last refilled.
                if !next.isEmpty { windows = next }
            }
        }
    }
}
