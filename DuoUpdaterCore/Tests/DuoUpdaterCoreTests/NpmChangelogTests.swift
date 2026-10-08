import Testing
import Foundation
@testable import DuoUpdaterCore

/// A global npm package's release notes: which repository, which releases, and
/// what is asked of GitHub. The fetch and the token are injected — nothing here
/// reaches the network or runs `gh`.
@Suite struct NpmChangelogTests {

    @Test func repositoryForms() {
        let expected = NpmChangelog.Repository(owner: "openclaw", name: "openclaw")
        for raw in ["git+https://github.com/openclaw/openclaw.git", "https://github.com/openclaw/openclaw",
                    "github:openclaw/openclaw", "openclaw/openclaw", "git://github.com/openclaw/openclaw.git",
                    "git+ssh://git@github.com/openclaw/openclaw.git", "git@github.com:openclaw/openclaw.git",
                    "https://github.com/openclaw/openclaw#main"] {
            #expect(NpmChangelog.gitHubRepository(raw) == expected, "\(raw)")
        }
        for raw in [nil, "", "gitlab:a/b", "https://gitlab.com/a/b", "https://github.com/a", "bitbucket:a/b",
                    "https://github.com/a/b/tree/main/pkg"] {
            #expect(NpmChangelog.gitHubRepository(raw) == nil, "\(raw ?? "nil")")
        }
    }

    func release(_ tag: String, _ body: String, draft: Bool = false) -> [String: Any] {
        ["tag_name": tag, "body": body, "draft": draft, "prerelease": false, "published_at": "2026-09-30T04:44:14Z"]
    }

    func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    /// Exact tags only, in the order asked; a release listed out of version
    /// order (openclaw's maintenance lines) lands where its version is.
    ///
    /// Mutation: match by "tag contains the version" → `v2026.6.35-beta.1`'s
    /// notes would stand in for 2026.6.35's missing release.
    @Test func releasesAreMatchedByExactTag() throws {
        let list = data([
            release("v2026.9.7", "- nine seven"),
            release("v2026.6.35-beta.1", "- a beta of six"),
            release("linux-stable", "- not a version"),
            release("v2026.8.33", "- eight"),
            release("openclaw@2026.6.34", "- monorepo tag"),
            release("2026.6.33", "- bare tag"),
            release("v2026.6.32", "- draft", draft: true),
        ])
        let (changelog, missing) = try #require(NpmChangelog.parse(
            list, name: "openclaw", versions: ["2026.9.7", "2026.8.33", "2026.6.35", "2026.6.34", "2026.6.33", "2026.6.32"]))
        #expect(changelog.entries.map(\.version) == ["2026.9.7", "2026.8.33", "2026.6.34", "2026.6.33"])
        #expect(changelog.entries.first?.items == ["nine seven"])
        #expect(changelog.entries.first?.date == "2026-09-30")
        #expect(missing == ["2026.6.35", "2026.6.32"])
        #expect(changelog.itemSyntax == .markdown)
    }

    final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(url: String, auth: String?)] = []
        func add(_ r: URLRequest) {
            lock.withLock { items.append((r.url!.absoluteString, r.value(forHTTPHeaderField: "Authorization"))) }
        }
        var all: [(url: String, auth: String?)] { lock.withLock { items } }
    }

    func response(_ url: String, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    @Test func noRepositoryIsAnEmptyChangelogAndNoRequest() async throws {
        let requests = Requests()
        let changelog = try await NpmChangelog.fetch(
            repository: nil, name: "@tencent-qqmail/agently-cli", versions: ["1.0.18"], force: false,
            fetch: { requests.add($0); throw URLError(.badURL) }, token: { nil })
        #expect(changelog.entries.isEmpty)
        #expect(requests.all.isEmpty)
    }

    @Test func aShortListIsOneRequest() async throws {
        let requests = Requests()
        let changelog = try await NpmChangelog.fetch(
            repository: "git+https://github.com/vercel-labs/agent-browser.git", name: "agent-browser",
            versions: ["0.38.1", "0.38.0"], force: false,
            fetch: { request in
                requests.add(request)
                return (self.data([self.release("v0.38.1", "- one"), self.release("v0.37.0", "- old")]),
                        self.response(request.url!.absoluteString, 200))
            }, token: { "t0ken" })
        #expect(changelog.entries.map(\.version) == ["0.38.1"])
        #expect(requests.all.map(\.url) == ["https://api.github.com/repos/vercel-labs/agent-browser/releases?per_page=100"])
        #expect(requests.all.first?.auth == "Bearer t0ken")
    }

    /// A full first page may not reach older versions: those are asked by tag,
    /// at the address the (renamed repository's) redirect named, with the token.
    @Test func versionsBeyondTheFirstPageAreAskedByTagAtTheRedirectedAddress() async throws {
        let requests = Requests()
        let page = data((0..<100).map { release("v0.14.\($0 + 100)", "- filler") })
        let changelog = try await NpmChangelog.fetch(
            repository: "https://github.com/geelen/mcp-remote", name: "mcp-remote",
            versions: ["0.14.200", "0.13.0"], force: true,
            fetch: { request in
                requests.add(request)
                let url = request.url!.absoluteString
                if url.hasSuffix("/releases?per_page=100") {
                    // What URLSession hands back after following the 301.
                    return (page, self.response("https://api.github.com/repositories/951601187/releases?per_page=100", 200))
                }
                if url.hasSuffix("/tags/0.13.0") {
                    return (self.data(self.release("0.13.0", "- thirteen")), self.response(url, 200))
                }
                return (Data("{}".utf8), self.response(url, 404))
            }, token: { "t0ken" })
        #expect(changelog.entries.map(\.version) == ["0.13.0"])
        #expect(requests.all.map(\.url) == [
            "https://api.github.com/repos/geelen/mcp-remote/releases?per_page=100",
            "https://api.github.com/repositories/951601187/releases/tags/v0.14.200",
            "https://api.github.com/repositories/951601187/releases/tags/0.14.200",
            "https://api.github.com/repositories/951601187/releases/tags/mcp-remote@0.14.200",
            "https://api.github.com/repositories/951601187/releases/tags/v0.13.0",
            "https://api.github.com/repositories/951601187/releases/tags/0.13.0",
        ])
        #expect(requests.all.allSatisfy { $0.auth == "Bearer t0ken" })
    }

    /// Mutation: drop `followUpLimit` → one request per tag candidate of every missing version.
    @Test func followUpsAreCapped() async throws {
        let requests = Requests()
        let page = data((0..<100).map { release("v9.0.\($0)", "- filler") })
        let versions = (1...20).map { "1.0.\($0)" }
        _ = try await NpmChangelog.fetch(
            repository: "o/r", name: "r", versions: versions, force: false,
            fetch: { request in
                requests.add(request)
                let url = request.url!.absoluteString
                return (url.contains("per_page") ? page : Data("{}".utf8),
                        self.response(url, url.contains("per_page") ? 200 : 404))
            }, token: { nil })
        #expect(requests.all.count == 1 + NpmChangelog.followUpLimit)
    }

    @Test func aMissingRepositoryIsEmptyAndOtherErrorsThrow() async throws {
        let gone = try await NpmChangelog.fetch(
            repository: "o/r", name: "r", versions: ["1.0.0"], force: false,
            fetch: { (Data(), self.response($0.url!.absoluteString, 404)) }, token: { nil })
        #expect(gone.entries.isEmpty)
        // A 403 with budget left: not the rate limit (`CLIToolReleaseNotesRateLimitTests`).
        await #expect(throws: CLIToolReleaseNotesError.http(403)) {
            _ = try await NpmChangelog.fetch(
                repository: "o/r", name: "r", versions: ["1.0.0"], force: false,
                fetch: {
                    (Data(), HTTPURLResponse(url: $0.url!, statusCode: 403, httpVersion: nil,
                                             headerFields: ["X-RateLimit-Remaining": "12"])!)
                }, token: { nil })
        }
    }
}
