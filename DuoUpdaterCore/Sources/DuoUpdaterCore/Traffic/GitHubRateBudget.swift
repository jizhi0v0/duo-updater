import Foundation

/// The GitHub REST API's `core` quota, as stated in a network response's
/// `x-ratelimit-*` headers. Settings retains up to three recent reset-time
/// groups as timestamped response samples, without treating them as allowances.
///
/// GitHub documents that regions may report different counts and that the
/// remaining count may increase between responses. The headers are authoritative
/// for that response; a different reset second does not identify another budget.
/// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
///
/// Cache-only loads do not update this snapshot. A revalidation reports both the
/// cached response and a network transaction; only the latter supplies a reading.
/// State is per process, and is invalidated when the credentials change.
public struct GitHubRateBudget: Sendable, Equatable {
    public let limit: Int
    public let remaining: Int
    /// The reset time reported in the response.
    public let reset: Date

    public init(limit: Int, remaining: Int, reset: Date) {
        self.limit = limit
        self.remaining = remaining
        self.reset = reset
    }

    /// A response's remaining count expires at its reported reset time.
    public func isCurrent(at now: Date) -> Bool { reset > now }

    /// Under a fifth of the limit left: Settings draws the window's bar orange.
    public var isRunningLow: Bool { remaining * 5 < limit }

    /// A budget answered without a token. GitHub's documentation: "The primary
    /// rate limit for unauthenticated requests is 60 requests per hour"; a
    /// personal token's is 5,000, some Enterprise Cloud apps' 15,000
    /// (docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api,
    /// read 2026-10-11).
    public var isAnonymous: Bool { limit <= 60 }

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

    /// A response snapshot. The reception time is the network transaction's
    /// response end, so a delayed metrics callback cannot replace a newer reply.
    public struct Observation: Sendable, Equatable {
        public let budget: GitHubRateBudget
        public let receivedAt: Date
    }

    static func observation(
        from metrics: URLSessionTaskMetrics, isAPI: (URL) -> Bool = ChangelogService.isGitHubAPI
    ) -> Observation? {
        for transaction in metrics.transactionMetrics.reversed() where transaction.resourceFetchType == .networkLoad {
            guard let url = transaction.request.url, isAPI(url),
                  let http = transaction.response as? HTTPURLResponse
            else { continue }
            guard let budget = GitHubRateBudget(http), let receivedAt = transaction.responseEndDate else { return nil }
            return Observation(budget: budget, receivedAt: receivedAt)
        }
        return nil
    }

    /// Recent snapshots under the process's current credentials. A request
    /// captures its generation when it is made; a late reply under replaced
    /// credentials never becomes the current snapshot.
    public final class Store: @unchecked Sendable {
        public static let shared = Store()

        private let lock = NSLock()
        private var observation: Observation?
        private var observations: [Observation] = []
        private static let readingCap = 3
        private var readingGeneration: Int
        private let isAPI: @Sendable (URL) -> Bool
        private let credentials: GitHubCredentials

        init(
            isAPI: @escaping @Sendable (URL) -> Bool = ChangelogService.isGitHubAPI,
            credentials: GitHubCredentials = .shared
        ) {
            self.isAPI = isAPI
            self.credentials = credentials
            self.readingGeneration = credentials.generation
        }

        /// Latest response per reported reset time, earliest reset first. The
        /// key bounds duplicate display rows; it does not identify a quota pool.
        /// The latest snapshot is also returned after it expires, so Settings
        /// can show when GitHub last responded while waiting for a new count.
        public func readings(at now: Date) -> (current: [Observation], latest: Observation?) {
            lock.withLock {
                guard readingGeneration == credentials.generation else { return ([], nil) }
                let current = observations.filter { $0.budget.isCurrent(at: now) }
                    .sorted { $0.budget.reset < $1.budget.reset }
                return (current, observation)
            }
        }

        public func current(at now: Date) -> [GitHubRateBudget] {
            readings(at: now).current.map(\.budget)
        }

        /// The latest reset time among the response groups retained in the store.
        public var lastReset: Date? {
            lock.withLock {
                guard readingGeneration == credentials.generation else { return nil }
                return observations.map(\.budget.reset).max()
            }
        }

        func requestGeneration() -> Int { credentials.requestGeneration() }

        func observe(_ metrics: URLSessionTaskMetrics, generation: Int) {
            guard let seen = GitHubRateBudget.observation(from: metrics, isAPI: isAPI) else { return }
            record(seen.budget, now: seen.receivedAt, generation: generation)
        }

        /// `now` is when the response was received, not when its callback ran.
        /// Within a reset-time group, keep the latest raw response, including
        /// increases in remaining count. Retain the three most recently received
        /// groups; expired samples and superseded credential limits are omitted.
        func record(_ seen: GitHubRateBudget, now: Date, generation: Int? = nil) {
            lock.withLock {
                let current = credentials.generation
                guard (generation ?? current) == current else { return }
                if readingGeneration != current {
                    observation = nil
                    observations = []
                    readingGeneration = current
                }
                let sample = Observation(budget: seen, receivedAt: now)
                if observation.map({ now >= $0.receivedAt }) ?? true {
                    if observation?.budget.limit != seen.limit { observations = [] }
                    observation = sample
                }
                guard let latest = observation, seen.limit == latest.budget.limit else { return }
                observations.removeAll { !$0.budget.isCurrent(at: latest.receivedAt) }
                guard seen.isCurrent(at: latest.receivedAt) else { return }
                if let index = observations.firstIndex(where: { $0.budget.reset == seen.reset }) {
                    if now >= observations[index].receivedAt { observations[index] = sample }
                } else {
                    observations.append(sample)
                }
                observations.sort {
                    if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
                    return $0.budget.reset > $1.budget.reset
                }
                observations = Array(observations.prefix(Self.readingCap))
            }
        }
    }
}
