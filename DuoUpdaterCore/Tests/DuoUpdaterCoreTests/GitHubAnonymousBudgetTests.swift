import Testing
import Foundation
@testable import DuoUpdaterCore

/// Reading the anonymous budget off GitHub's `/rate_limit`. Nothing here reaches
/// the network.
@Suite struct GitHubAnonymousBudgetTests {

    /// An anonymous answer as GitHub gave it on 2026-10-11 (budget spent), less
    /// the resources this does not read. `search` counts apart and must not be
    /// taken for `core`.
    static let spent = Data("""
        {"resources": {"core": {"limit": 60, "remaining": 0, "reset": 1791709754, "used": 60}, \
        "search": {"limit": 10, "remaining": 10, "reset": 1791708555, "used": 0}}, \
        "rate": {"limit": 60, "remaining": 0, "reset": 1791709754, "used": 60}}
        """.utf8)

    /// Kills: reading `search`, or `rate` alone.
    @Test func readsCore() async throws {
        let budget = try await GitHubAnonymousBudget(fetch: { _ in (Self.spent, 200) }).current()
        #expect(budget == GitHubRateBudget(limit: 60, remaining: 0, reset: Date(timeIntervalSince1970: 1791709754)))
        #expect(GitHubAnonymousBudget.parse(Data(#"{"rate": {"limit": 60, "remaining": 5, "reset": 1}}"#.utf8)) == nil)
    }

    /// Never the token, never a cached count. Kills: a request that carries
    /// `Authorization`, or may be answered from URLSession's or a proxy's cache.
    @Test func asksWithNoTokenAndFromNoCache() async throws {
        let seen = Seen()
        _ = try await GitHubAnonymousBudget(fetch: { request in seen.request = request; return (Self.spent, 200) }).current()
        let request = try #require(seen.request)
        #expect(request.url?.absoluteString == "https://api.github.com/rate_limit")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
    }

    @Test func anythingButAReadable200IsAFailure() async {
        await #expect(throws: GitHubAnonymousBudget.Failure.http(503)) {
            try await GitHubAnonymousBudget(fetch: { _ in (Self.spent, 503) }).current()
        }
        await #expect(throws: GitHubAnonymousBudget.Failure.unreadable) {
            try await GitHubAnonymousBudget(fetch: { _ in (Data("<html>".utf8), 200) }).current()
        }
    }

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var value: URLRequest?
        var request: URLRequest? {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }
}
