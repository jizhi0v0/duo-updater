import Foundation
import Testing
@testable import DuoUpdaterCore

/// A 403 from `api.github.com` has two quite different causes, and reporting both
/// as the rate limit sends half of them to the wrong fix.
///
/// The budget-exhausted 403 is the common one and a token really does cure it.
/// The other 403 — a repo gone private, deleted, renamed away, or a token whose
/// scopes don't cover it — is not a waiting-out-the-hour problem: the banner
/// telling the user to add a token is advice that cannot work, on a row that will
/// still be broken in an hour. `X-RateLimit-Remaining` is on the response and
/// separates them.
@Suite(.serialized)
struct GitHubForbiddenTests {
    private final class ForbiddenProtocol: URLProtocol, @unchecked Sendable {
        /// Status to answer with, and the `X-RateLimit-Remaining` header to carry
        /// (nil = send no such header).
        nonisolated(unsafe) static var status = 403
        nonisolated(unsafe) static var remaining: String?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            var headers: [String: String] = [:]
            if let remaining = Self.remaining { headers["X-RateLimit-Remaining"] = remaining }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: Self.status,
                httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"message":"Forbidden"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private let rule = GitHubReleaseRule(
        bundleID: "com.zzfixture.forbidden", owner: "zzfixture", repo: "app",
        versionPattern: #"^v([0-9.]+)$"#)

    private func message(status: Int, remaining: String?) async -> String {
        ForbiddenProtocol.status = status
        ForbiddenProtocol.remaining = remaining
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ForbiddenProtocol.self]
        let source = GitHubReleasesSource(
            rules: [rule], session: URLSession(configuration: configuration))
        let app = InstalledApp(
            name: "ZZFixture", bundleID: rule.bundleID, shortVersion: "1.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Forbidden.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
        #expect(!FileManager.default.fileExists(atPath: app.path.path))
        do {
            _ = try await source.latestVersion(for: app)
            Issue.record("a \(status) must reach the caller as an error")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    @Test func aBudgetExhausted403IsReportedAsTheRateLimit() async throws {
        let exhausted = await message(status: 403, remaining: "0")
        #expect(UpdateStatus.error(exhausted).isRateLimitError)
        // A 403 that never reached the API carries no budget header at all, and
        // "no evidence" must not quietly become "not rate limited" — that is the
        // one case where the nudge is the whole explanation.
        let headerless = await message(status: 403, remaining: nil)
        #expect(UpdateStatus.error(headerless).isRateLimitError)
        let tooManyRequests = await message(status: 429, remaining: "57")
        #expect(UpdateStatus.error(tooManyRequests).isRateLimitError)
    }

    @Test func anAccess403IsNotReportedAsTheRateLimit() async throws {
        let forbidden = await message(status: 403, remaining: "57")

        #expect(!UpdateStatus.error(forbidden).isRateLimitError,
                "a 403 with budget left is an access problem; a token cannot fix it")
        #expect(forbidden.contains("403"))
        // The row has to say something a user can act on instead.
        #expect(forbidden.localizedCaseInsensitiveContains("forbidden"))
    }

    /// Whatever the words, the classification the sweep files must stay a status
    /// code — a rate limit is infrastructure, not a broken recipe, and both 403s
    /// have to keep arriving as `.httpStatus`.
    @Test func bothKindsStillReachTheSweepAsAStatusCode() async throws {
        for remaining in ["0", "57"] {
            ForbiddenProtocol.status = 403
            ForbiddenProtocol.remaining = remaining
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ForbiddenProtocol.self]
            let source = GitHubReleasesSource(
                rules: [rule], session: URLSession(configuration: configuration))

            let outcome = await source.resolveDiagnostic(rule)

            #expect(outcome.httpStatus == 403)
            guard case .httpStatus(403)? = outcome.failure else {
                Issue.record("remaining=\(remaining) produced \(String(describing: outcome.failure))")
                return
            }
        }
    }
}
