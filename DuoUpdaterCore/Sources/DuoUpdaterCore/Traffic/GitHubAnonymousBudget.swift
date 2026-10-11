import Foundation

/// What is left of the anonymous GitHub API budget of this Mac's network
/// address: 60 an hour, shared with every program behind that address that asks
/// without a token — zoxide's installer and `atuin update` among them, which can
/// take no token (`CLIToolGitHubToken`). Settings ▸ GitHub shows it beside the
/// budget the app's own requests report (`GitHubRateBudget`), which once a token
/// is in use is the token's and says nothing of this one.
///
/// **Asked for, and free.** `GET /rate_limit` with no token. GitHub's
/// documentation: "Accessing this endpoint does not count against your REST API
/// rate limit" (https://docs.github.com/en/rest/rate-limit/rate-limit, read
/// 2026-10-11). The figures are the body's `resources.core`; `rate` is the same
/// figures under a name GitHub is retiring.
///
/// **Not the token's budget.** The answer is logged as a request like any other,
/// but its reading never reaches `GitHubRateBudget.Store.shared`: it states
/// another limit, and a reading with another limit drops every window kept
/// there. **Never cached:** URLSession's cache is skipped and a proxy is asked
/// not to answer from its own (`Cache-Control: no-cache`) — a stale count is
/// worse than none.
public struct GitHubAnonymousBudget: Sendable {

    /// The body and the status.
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    public enum Failure: Error, Equatable {
        case http(Int)
        case unreadable
    }

    static let endpoint = URL(string: "https://api.github.com/rate_limit")!

    /// Where the reading the request log's recorder takes is dropped.
    private static let unread = GitHubRateBudget.Store()

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { request in
            let (data, response) = try await session.data(
                for: request, delegate: RequestMetricsRecorder(.other, store: .shared, rateBudget: Self.unread))
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// The request: no `Authorization`, from no cache.
    static var request: URLRequest {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    public func current() async throws -> GitHubRateBudget {
        let (data, status) = try await fetch(Self.request)
        guard status == 200 else { throw Failure.http(status) }
        guard let budget = Self.parse(data) else { throw Failure.unreadable }
        return budget
    }

    /// `resources.core` of a `/rate_limit` body; nil without its three numbers.
    static func parse(_ data: Data) -> GitHubRateBudget? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let core = (json["resources"] as? [String: Any])?["core"] as? [String: Any],
              let limit = core["limit"] as? Int, let remaining = core["remaining"] as? Int,
              let reset = core["reset"] as? Double
        else { return nil }
        return GitHubRateBudget(limit: limit, remaining: remaining, reset: Date(timeIntervalSince1970: reset))
    }
}
