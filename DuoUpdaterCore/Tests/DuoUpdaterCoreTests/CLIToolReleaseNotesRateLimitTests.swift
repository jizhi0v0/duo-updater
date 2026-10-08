import Testing
import Foundation
@testable import DuoUpdaterCore

/// A command-line tool's release notes on the GitHub API, refused for the rate
/// limit, say so (`CLIToolReleaseNotesError.rateLimited`) instead of "HTTP 403".
/// Every fetch goes through its injected seam; nothing reaches the network.
struct CLIToolReleaseNotesRateLimitTests {

    static let api = URL(string: "https://api.github.com/repos/acme/tool/releases?per_page=30")!

    /// The app rows' rule (`GitHubReleasesSource.isRateLimited`), and only for
    /// the API. Mutations: drop the `isGitHubAPI` check; always `.http`.
    @Test func theRuleIsTheAppRowsOwnOnTheAPIOnly() {
        typealias E = CLIToolReleaseNotesError
        #expect(E.status(403, rateLimitRemaining: "0", url: Self.api) == .rateLimited)
        #expect(E.status(403, rateLimitRemaining: nil, url: Self.api) == .rateLimited)
        #expect(E.status(429, rateLimitRemaining: "9", url: Self.api) == .rateLimited)
        #expect(E.status(403, rateLimitRemaining: "12", url: Self.api) == .http(403))
        #expect(E.status(502, rateLimitRemaining: nil, url: Self.api) == .http(502))
        // Another host's 403 is its own, whatever it says.
        #expect(E.status(403, rateLimitRemaining: "0", url: URL(string: "https://herdr.dev/latest.json")!) == .http(403))
        // The response's own header is the one read.
        let limited = HTTPURLResponse(url: Self.api, statusCode: 403, httpVersion: nil,
                                      headerFields: ["X-RateLimit-Remaining": "0"])!
        #expect(E.status(limited, url: Self.api) == .rateLimited)
        let forbidden = HTTPURLResponse(url: Self.api, statusCode: 403, httpVersion: nil,
                                        headerFields: ["X-RateLimit-Remaining": "40"])!
        #expect(E.status(forbidden, url: Self.api) == .http(403))
    }

    /// OpenCode's notes, the pane in the screenshot. Mutation: throw `.http` there.
    @Test func openCodesNotesSayRateLimited() async {
        await #expect(throws: CLIToolReleaseNotesError.rateLimited) {
            try await OpencodeRelease(fetch: { _, _ in (Data(), 403, "0") }).notes(force: false)
        }
        await #expect(throws: CLIToolReleaseNotesError.http(502)) {
            try await OpencodeRelease(fetch: { _, _ in (Data(), 502, nil) }).notes(force: false)
        }
    }

    /// npm packages' GitHub releases. Mutation: throw `.http` there.
    @Test func npmPackagesNotesSayRateLimited() async {
        await #expect(throws: CLIToolReleaseNotesError.rateLimited) {
            try await NpmChangelog.fetch(
                repository: "github:acme/tool", name: "tool", versions: ["1.0.0"], force: false,
                fetch: { request in
                    (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil,
                                             headerFields: ["X-RateLimit-Remaining": "0"])!)
                },
                token: { nil })
        }
    }

    /// Junie's per-build lookups. Mutation: `.http` in `JunieChangelog.answer`.
    @Test func junieNotesSayRateLimited() async {
        await #expect(throws: CLIToolReleaseNotesError.rateLimited) {
            try await JunieChangelog.fetch(builds: ["3419.26"], installed: "3419.19", latest: "3419.26", force: false,
                                           fetch: { _, _ in (Data(), 403, "0") })
        }
    }

    /// Codex's tag list and per-version lookups. Mutations: `.http` for the tag
    /// list; `.http` in `CodexChangelog.answer`.
    @Test func codexNotesSayRateLimited() async {
        await #expect(throws: CLIToolReleaseNotesError.rateLimited) {
            try await CodexChangelog.fetch(installed: "0.150.0", latest: "0.160.0", force: false,
                                           fetch: { _, _ in (Data(), 429, nil) })
        }
        let answer = await CodexChangelog.answer(version: "0.160.0", force: false, fetch: { _, _ in (Data(), 403, "0") })
        #expect(answer.failure as? CLIToolReleaseNotesError == .rateLimited)
    }
}
