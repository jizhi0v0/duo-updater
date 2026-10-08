import Testing
import Foundation
@testable import DuoUpdaterCore

/// Codex's release notes: which tags are asked for, and what a release body
/// becomes. No network: every answer is handed in.
@Suite struct CodexChangelogTests {

    /// `git/matching-refs/tags/rust-v` as GitHub answers it, cut down.
    static func refs(_ tags: [String]) -> Data {
        try! JSONSerialization.data(withJSONObject: tags.map { ["ref": "refs/tags/rust-v" + $0, "object": ["sha": "0"]] })
    }

    /// rust-v0.160.0's body, shortened, with its PR list.
    static let body = """
        ## New Features

        - Browse older tasks in the agent command center with a keyboard-accessible “Show more” action. (#49106)
        - Start sessions outside a project with workspace defaults when policy permits. (#49160)

        ## Bug Fixes

        - Unsent queued messages now resume after reconnection. (#49105)

        ## Changelog

        Full Changelog: https://github.com/openai/codex/compare/rust-v0.159.0...rust-v0.160.0

        - #48983 Avoid full metadata rewrites for thread timestamp updates @jif-oai
        - #49000 Isolate the memory startup metadata test from Git enrichment @jif-oai
        """

    static func release(_ version: String, body: String = CodexChangelogTests.body) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": "rust-v" + version, "draft": false, "prerelease": false, "body": body,
            "published_at": "2026-10-01T20:19:13Z",
        ])
    }

    /// Mutation: keep the alphas.
    @Test func onlyStableTagsAreVersions() {
        let data = Self.refs(["0.159.3", "0.160.0", "0.160.0-alpha.6.2", "0.162.0-alpha.12", "garbage"])
        #expect(CodexChangelog.stableVersions(data) == ["0.159.3", "0.160.0"])
        #expect(CodexChangelog.stableVersions(Data("{}".utf8)).isEmpty)
    }

    /// Mutations: cap at `latest` the wrong way; drop the reader's own versions
    /// when fewer than `minimum` are unseen.
    @Test func windowIsTheNewestUnseenThenTheReadersOwn() {
        let versions = (140...160).map { "0.\($0).0" } + ["0.161.0"]
        let behind = CodexChangelog.window(versions: versions, installed: "0.143.0", latest: "0.160.0")
        #expect(behind == (153...160).reversed().map { "0.\($0).0" })
        let current = CodexChangelog.window(versions: versions, installed: "0.160.0", latest: "0.160.0")
        #expect(current == ["0.160.0", "0.159.0", "0.158.0", "0.157.0", "0.156.0"])
        let oneBehind = CodexChangelog.window(versions: versions, installed: "0.159.0", latest: "0.160.0")
        #expect(oneBehind == ["0.160.0", "0.159.0", "0.158.0", "0.157.0", "0.156.0"])
    }

    /// Mutation: drop `skipSections`, and the PR list becomes the notes' bulk.
    @Test func aReleaseBodyBecomesItsEntryWithoutThePRList() throws {
        let entry = try #require(CodexChangelog.parse(Self.release("0.160.0"), version: "0.160.0"))
        #expect(entry.version == "0.160.0")
        #expect(entry.date == "2026-10-01")
        #expect(entry.items.count == 3)
        #expect(!entry.items.contains { $0.contains("#48983") })
        #expect(CodexChangelog.parse(Self.release("0.160.0"), version: "0.159.3") == nil)
        #expect(CodexChangelog.parse(Self.release("0.160.0", body: "  "), version: "0.160.0") == nil)
    }

    @Test func notesAreNewestFirstAndA404IsNoNotes() async throws {
        let changelog = try await CodexChangelog.notes(
            versions: ["0.158.0", "0.159.3", "0.160.0"], installed: "0.158.0", latest: "0.160.0", force: false,
            fetch: { url, _ in
                if url.absoluteString.hasSuffix("rust-v0.159.3") { return (Data(), 404, nil) }
                let version = String(url.absoluteString.split(separator: "v").last!)
                return (Self.release(version), 200, nil)
            })
        #expect(changelog.entries.map(\.version) == ["0.160.0", "0.158.0"])
    }

    @Test func nothingAnsweredIsAnError() async {
        await #expect(throws: CLIToolReleaseNotesError.http(403)) {
            try await CodexChangelog.notes(
                versions: ["0.160.0"], installed: "0.143.0", latest: "0.160.0", force: false,
                // A 403 with budget left: not the rate limit.
                fetch: { _, _ in (Data(), 403, "12") })
        }
    }
}
