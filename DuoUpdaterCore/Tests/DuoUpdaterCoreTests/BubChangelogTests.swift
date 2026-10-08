import Testing
import Foundation
@testable import DuoUpdaterCore

/// bub's release notes: the GitHub Releases list, through the production decoder
/// and `GitHubMarkdownParser`.
///
/// The bodies are excerpts of the real ones (`api.github.com/repos/bubbuild/bub/
/// releases`, fetched 2026-10-01), cut down but byte-for-byte in the lines kept —
/// changelogithub's headings, attribution tails and nested scopes are the point.
@Suite struct BubChangelogTests {

    static let v050 = """
        ### &nbsp;&nbsp;&nbsp;🚀 Features

        - Document and bundle Agent Plugins &nbsp;-&nbsp; by @PsiACE in https://github.com/bubbuild/bub/issues/307 [<samp>(4eeee)</samp>](https://github.com/bubbuild/bub/commit/4eeee69)
        - Support embedding Agent with instance tools, skills, and storage &nbsp;-&nbsp; in https://github.com/bubbuild/bub/issues/311 [<samp>(e4578)</samp>](https://github.com/bubbuild/bub/commit/e4578a4)
        - Check provider connections and discover models during onboarding &nbsp;-&nbsp; by @LuYanFCP and **Frost Ming** in https://github.com/bubbuild/bub/issues/316 [<samp>(25185)</samp>](https://github.com/bubbuild/bub/commit/251850f)
        - Enhance code mode functionality and tool handling &nbsp;-&nbsp; by @frostming [<samp>(a363a)</samp>](https://github.com/bubbuild/bub/commit/a363a1d)

        ### &nbsp;&nbsp;&nbsp;🐞 Bug Fixes

        - Spill oversized tool errors &nbsp;-&nbsp; by @PsiACE in https://github.com/bubbuild/bub/issues/306 [<samp>(151eb)</samp>](https://github.com/bubbuild/bub/commit/151ebb5)
        - **auth**: Handle Codex OAuth expiry and refresh errors &nbsp;-&nbsp; by @PsiACE in https://github.com/bubbuild/bub/issues/323 [<samp>(f2624)</samp>](https://github.com/bubbuild/bub/commit/f262400)

        ##### &nbsp;&nbsp;&nbsp;&nbsp;[View changes on GitHub](https://github.com/bubbuild/bub/compare/0.4.4...0.5.0)
        """

    static let v043 = """
        ### &nbsp;&nbsp;&nbsp;🚀 Features

        - Add continue prompt hook &nbsp;-&nbsp; by @frostming in https://github.com/bubbuild/bub/issues/281 [<samp>(3888d)</samp>](https://github.com/bubbuild/bub/commit/3888dea)

        ### &nbsp;&nbsp;&nbsp;🐞 Bug Fixes

        - Add missing license information in pyproject.toml &nbsp;-&nbsp; by @frostming [<samp>(46dc3)</samp>](https://github.com/bubbuild/bub/commit/46dc32e)
        - **agent**:
          - Recover unknown tool calls before they abort the turn &nbsp;-&nbsp; by @PsiACE in https://github.com/bubbuild/bub/issues/273 [<samp>(9c0da)</samp>](https://github.com/bubbuild/bub/commit/9c0da67)
          - Remove default step limit &nbsp;-&nbsp; by @PsiACE in https://github.com/bubbuild/bub/issues/276 [<samp>(5e0ff)</samp>](https://github.com/bubbuild/bub/commit/5e0ffba)
        - **codex**:
          - Forward output token limit &nbsp;-&nbsp; by @PsiACE in https://github.com/bubbuild/bub/issues/272 [<samp>(e39b2)</samp>](https://github.com/bubbuild/bub/commit/e39b299)

        ##### &nbsp;&nbsp;&nbsp;&nbsp;[View changes on GitHub](https://github.com/bubbuild/bub/compare/0.4.2...0.4.3)
        """

    static func release(_ tag: String, _ body: String, prerelease: Bool = false, date: String) -> [String: Any] {
        ["tag_name": tag, "prerelease": prerelease, "draft": false, "published_at": date, "body": body]
    }

    static var releasesJSON: String {
        let releases: [[String: Any]] = [
            release("0.5.0", v050, date: "2026-09-30T11:28:37Z"),
            release("0.4.4", "### Features\n\n- Add gateway service lifecycle commands &nbsp;-&nbsp; by @frostming in https://github.com/bubbuild/bub/issues/295 [<samp>(2aa95)</samp>](https://github.com/bubbuild/bub/commit/2aa951b)", date: "2026-09-14T13:11:36Z"),
            release("0.4.3", v043, date: "2026-08-19T12:00:23Z"),
            release("0.3.0a1", "- a prerelease nobody on a plain `bub` gets", prerelease: true, date: "2026-03-06T09:05:09Z"),
            release("0.2.1", "**Full Changelog**: https://github.com/PsiACE/bub/compare/0.2.0...0.2.1", date: "2026-02-14T09:11:31Z"),
            release("0.2.0", "## What’s new\n\n- `bub chat` for interactive sessions\n- `bub run` for one-shot execution", date: "2026-02-14T08:03:17Z"),
        ]
        let data = try! JSONSerialization.data(withJSONObject: releases)
        return String(decoding: data, as: UTF8.self)
    }

    func entry(_ changelog: Changelog, _ version: String) throws -> Changelog.Entry {
        try #require(changelog.entries.first { $0.version == version })
    }

    /// One entry per stable release, newest first; the prerelease and the body
    /// that is only a compare link have none.
    @Test func everyStableReleaseWithNotesIsAnEntry() throws {
        let changelog = try #require(BubChangelog.parse(Self.releasesJSON))
        #expect(changelog.entries.map(\.version) == ["0.5.0", "0.4.4", "0.4.3", "0.2.0"])
        #expect(changelog.entries.map(\.date) == ["2026-09-30", "2026-09-14", "2026-08-19", "2026-02-14"])
        #expect(changelog.itemSyntax == .markdown)
    }

    /// Headings keep their emoji and lose changelogithub's `&nbsp;` indent; every
    /// attribution tail, whatever its shape, is cut at its separator.
    @Test func changelogithubBodiesReadAsTitlesUnderHeadings() throws {
        let changelog = try #require(BubChangelog.parse(Self.releasesJSON))
        let notes = try entry(changelog, "0.5.0")
        #expect(notes.content == [
            .heading("🚀 Features"),
            .note("Document and bundle Agent Plugins"),
            .note("Support embedding Agent with instance tools, skills, and storage"),
            .note("Check provider connections and discover models during onboarding"),
            .note("Enhance code mode functionality and tool handling"),
            .heading("🐞 Bug Fixes"),
            .note("Spill oversized tool errors"),
            .note("**auth**: Handle Codex OAuth expiry and refresh errors"),
        ])
        #expect(!notes.items.contains { $0.contains("&nbsp;") || $0.contains("<samp>") || $0.contains("https://") })
    }

    /// A scope with several changes is a label with the changes nested under it;
    /// each change keeps the label, as the one-change form writes it.
    @Test func nestedScopeChangesAreItemsAndTheBareLabelIsNot() throws {
        let changelog = try #require(BubChangelog.parse(Self.releasesJSON))
        #expect(try entry(changelog, "0.4.3").items == [
            "Add continue prompt hook",
            "Add missing license information in pyproject.toml",
            "**agent**: Recover unknown tool calls before they abort the turn",
            "**agent**: Remove default step limit",
            "**codex**: Forward output token limit",
        ])
    }

    @Test func olderHandWrittenBodiesAreUnchanged() throws {
        let changelog = try #require(BubChangelog.parse(Self.releasesJSON))
        #expect(try entry(changelog, "0.2.0").items == ["`bub chat` for interactive sessions", "`bub run` for one-shot execution"])
    }

    /// What the app shows someone on 0.4.4 with 0.5.0 out: the new release, then
    /// what they already have.
    @Test func theRelevantSliceForAnInstallBehind() throws {
        let changelog = try #require(BubChangelog.parse(Self.releasesJSON))
        let relevant = try #require(CLIToolChangelog.relevant(changelog, installed: "0.4.4", latest: "0.5.0", minimum: 3))
        #expect(relevant.entries.map(\.version) == ["0.5.0", "0.4.4", "0.4.3"])
    }

    @Test func anErrorBodyIsNoSections() {
        #expect(BubChangelog.parse(#"{"message":"API rate limit exceeded"}"#) == nil)
        #expect(BubChangelog.parse("[]") == nil)
    }

    // MARK: - Parser rules, one at a time

    func items(_ body: String) -> [String] {
        GitHubMarkdownParser.parse(body: body, version: "1.0.0", date: nil)?.entries.first?.items ?? []
    }

    @Test func headingIndentEntitiesAreDropped() {
        #expect(GitHubMarkdownParser.headingRawText(of: "### &nbsp;&nbsp;&nbsp;🚀 Features") == "🚀 Features")
        #expect(GitHubMarkdownParser.headingRawText(of: "##   Fixed") == "Fixed")
        // Only a leading run: an entity inside the title is the vendor's text.
        #expect(GitHubMarkdownParser.headingRawText(of: "## A&nbsp;B") == "A&nbsp;B")
    }

    @Test(arguments: [
        "Add a feature &nbsp;-&nbsp; by @a in https://x.invalid/issues/1 [<samp>(abc12)</samp>](https://x.invalid/c/abc12)",
        "Add a feature &nbsp;-&nbsp; by @a, **B** and **c** in https://x.invalid/issues/1 [<samp>(abc12)</samp>](https://x.invalid/c)",
        "Add a feature &nbsp;-&nbsp; in https://x.invalid/issues/1 [<samp>(abc12)</samp>](https://x.invalid/c)",
        "Add a feature &nbsp;-&nbsp; by @a [<samp>(abc12)</samp>](https://x.invalid/c)",
        "Add a feature &nbsp;-&nbsp;",
    ])
    func everyChangelogithubTailIsCut(bullet: String) {
        #expect(items("- \(bullet)") == ["Add a feature"])
    }

    /// GitHub's own "What's Changed" tail is still read by the rule it always was.
    @Test func gitHubsGeneratedTailIsStillCut() {
        #expect(items("- Fix the thing by @someone in https://github.com/o/r/pull/12") == ["Fix the thing"])
    }

    /// Outside a scope label, an indented bullet is an item of its own, unprefixed.
    @Test func indentedBulletsUnderAnOrdinaryItemAreItemsOfTheirOwn() {
        #expect(items("- A real change here\n  - a detail of it\n- **ui**:\n  - Nested change") ==
                ["A real change here", "a detail of it", "**ui**: Nested change"])
    }

    /// A scope is closed by the next top-level line or heading: what is nested
    /// after it is no longer prefixed with the label.
    @Test func aScopeEndsAtTheNextTopLevelLine() {
        #expect(items("- **ui**:\n  - First change\n- Unscoped change\n  - detail") ==
                ["**ui**: First change", "Unscoped change", "detail"])
        #expect(items("- Top change\n- **ui**:\n## Fixed\n  - Indented after a heading") == ["Top change"])
    }
}
