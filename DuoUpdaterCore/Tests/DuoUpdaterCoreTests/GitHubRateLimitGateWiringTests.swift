import Foundation
import Testing
@testable import DuoUpdaterCore

/// The rate-limit gate as `countedData` and `countedBytes` apply it: what
/// reaches the network while GitHub has said the budget is spent. Driven
/// against a `URLProtocol` stub that plays `api.github.com`, so nothing leaves
/// the process, and that counts every request that reached it. Each test hands
/// in a gate of its own. Each case names the mutation it fails under.
@Suite(.serialized)
struct GitHubRateLimitGateWiringTests {
    /// Answers `/rate_limit` with `probeRemaining`, and every other path with
    /// `status` and the headers of a spent or roomy budget.
    private final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var probeRemaining = 100
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var remaining = 50
        nonisolated(unsafe) private static var paths: [String] = []
        static let reset: TimeInterval = Date().timeIntervalSince1970 + 1800
        private static let lock = NSLock()

        static func script(probe: Int, status: Int, remaining: Int) {
            lock.withLock { probeRemaining = probe; self.status = status; self.remaining = remaining; paths = [] }
        }

        /// Every path that reached the stub, in order.
        static var seen: [String] { lock.withLock { paths } }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let path = request.url?.path ?? ""
            let (status, body, headers): (Int, String, [String: String]) = Self.lock.withLock {
                Self.paths.append(path)
                if path == "/rate_limit" {
                    let body = #"{"resources":{"core":{"limit":5000,"remaining":\#(Self.probeRemaining),"reset":\#(Int(Self.reset))}}}"#
                    return (200, body, [:])
                }
                return (Self.status, #"{"tag_name":"v1.0.0"}"#, [
                    "x-ratelimit-resource": "core",
                    "x-ratelimit-remaining": String(Self.remaining),
                    "x-ratelimit-reset": String(Int(Self.reset)),
                ])
            }
            var fields = headers
            fields["Content-Type"] = "application/json"
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: fields)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private static func request(_ path: String = "/repos/zzfixture/app/releases/latest",
                                host: String = "api.github.com", token: String? = "Bearer placeholder-a") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        return request
    }

    /// A probe that finds the budget spent: the request is refused, and the
    /// only thing that reached GitHub is the probe — free of the primary budget.
    ///
    /// Mutation: `Pass` not consulting the gate (`gatedData` sending directly).
    @Test func aSpentBudgetSendsNothingButTheProbe() async {
        Stub.script(probe: 0, status: 200, remaining: 0)
        let gate = GitHubRateLimitGate.Store()
        await #expect(throws: GitHubRateLimitGate.Refused.self) {
            _ = try await Self.session().countedData(for: Self.request(), purpose: .versionCheck, gate: gate)
        }
        #expect(Stub.seen == ["/rate_limit"])
    }

    /// The round a full check sends at once, with the budget spent but the
    /// probe still showing room (another window, or another program spent it
    /// since): one canary meets the 403, the other nine are refused unsent,
    /// and the refusal says "rate limit" — what the row's rate-limited state
    /// matches on.
    ///
    /// Mutation: no canary (open straight after the probe).
    @Test func aBurstMeetsASpentBudgetWithOneRequest() async {
        Stub.script(probe: 10, status: 403, remaining: 0)
        let gate = GitHubRateLimitGate.Store()
        let session = Self.session()
        let results = await withTaskGroup(of: String.self) { group in
            for index in 0..<10 {
                group.addTask {
                    do {
                        let (_, response) = try await session.countedData(
                            for: Self.request("/repos/zzfixture/app\(index)/releases/latest"),
                            purpose: .versionCheck, gate: gate)
                        return "sent \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    } catch let refused as GitHubRateLimitGate.Refused {
                        return refused.localizedDescription.localizedCaseInsensitiveContains("rate limit")
                            ? "refused" : "refused without the phrase"
                    } catch {
                        return "other \(error)"
                    }
                }
            }
            return await group.reduce(into: [String]()) { $0.append($1) }
        }
        #expect(results.filter { $0 == "sent 403" }.count == 1)
        #expect(results.filter { $0 == "refused" }.count == 9)
        #expect(Stub.seen.filter { $0 != "/rate_limit" }.count == 1)
        #expect(Stub.seen.filter { $0 == "/rate_limit" }.count == 1)
    }

    /// With room, requests go through as before: the first probe, then every
    /// request answered.
    ///
    /// Mutation: the canary's answer not opening the gate.
    @Test func withRoomEveryRequestGoes() async throws {
        Stub.script(probe: 100, status: 200, remaining: 99)
        let gate = GitHubRateLimitGate.Store()
        let session = Self.session()
        for _ in 0..<3 {
            _ = try await session.countedData(for: Self.request(), purpose: .versionCheck, gate: gate)
        }
        #expect(Stub.seen == ["/rate_limit", "/repos/zzfixture/app/releases/latest",
                              "/repos/zzfixture/app/releases/latest", "/repos/zzfixture/app/releases/latest"])
    }

    /// Another token is another budget, probed afresh: switching to a token
    /// with room goes; switching back to the spent one sends nothing but its
    /// probe. Anonymous requests are their own budget too.
    ///
    /// Mutation: the identity ignoring the token (one entry per credential kind).
    @Test func switchingTokensProbesEachOne() async throws {
        let gate = GitHubRateLimitGate.Store()
        let session = Self.session()
        Stub.script(probe: 0, status: 200, remaining: 0)
        await #expect(throws: GitHubRateLimitGate.Refused.self) {
            _ = try await session.countedData(for: Self.request(token: "Bearer spent"), purpose: .versionCheck, gate: gate)
        }
        Stub.script(probe: 100, status: 200, remaining: 99)
        _ = try await session.countedData(for: Self.request(token: "Bearer fresh"), purpose: .versionCheck, gate: gate)
        #expect(Stub.seen == ["/rate_limit", "/repos/zzfixture/app/releases/latest"])

        Stub.script(probe: 0, status: 200, remaining: 0)
        await #expect(throws: GitHubRateLimitGate.Refused.self) {
            _ = try await session.countedData(for: Self.request(token: "Bearer spent"), purpose: .versionCheck, gate: gate)
        }
        #expect(Stub.seen == ["/rate_limit"])
    }

    /// Hosts other than the API — downloads, raw files, release feeds — are
    /// not the REST budget and never pass the gate, closed or not; nor does
    /// Settings verifying a pasted token, whose budget is not the one in use.
    ///
    /// Mutations: gate every github host; gate `followsTokenRejection: false`.
    @Test func onlyTheAPIInUseIsGated() async throws {
        let gate = GitHubRateLimitGate.Store()
        let session = Self.session()
        Stub.script(probe: 0, status: 200, remaining: 0)
        await #expect(throws: GitHubRateLimitGate.Refused.self) {
            _ = try await session.countedData(for: Self.request(), purpose: .versionCheck, gate: gate)
        }
        for host in ["raw.githubusercontent.com", "github.com", "objects.githubusercontent.com"] {
            _ = try await session.countedData(for: Self.request(host: host), purpose: .versionCheck, gate: gate)
        }
        _ = try await session.countedData(for: Self.request("/user"), purpose: .other,
                                          followsTokenRejection: false, gate: gate)
        #expect(Stub.seen.count == 1 + 3 + 1)
    }

    /// `countedBytes` passes the same gate.
    ///
    /// Mutation: `countedBytes` not building a `Pass`.
    @Test func countedBytesIsGatedToo() async {
        Stub.script(probe: 0, status: 200, remaining: 0)
        let gate = GitHubRateLimitGate.Store()
        await #expect(throws: GitHubRateLimitGate.Refused.self) {
            _ = try await Self.session().countedBytes(for: Self.request(), purpose: .versionCheck, gate: gate)
        }
        #expect(Stub.seen == ["/rate_limit"])
    }
}
