import Foundation
import Testing

@testable import DuoUpdaterCore

/// Requestly publishes with conventional commits through GitHub's release
/// generator, so every body is the auto-generated "## What's Changed" list —
/// `GitHubMarkdownParser`'s own format. This is the real body of `v26.6.29`.
@Suite struct RequestlyChangelogTests {

    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == "io.requestly.beta"
        })
    }

    /// The recipe reads GitHub's release bodies, not a page.
    @Test func readsTheReleaseBodiesAsStructuredMarkdown() throws {
        let r = try recipe()
        #expect(r.structuredFormat == .gitHubReleases)
        #expect(r.source.absoluteString.contains("requestly/http-interceptor-desktop-app"))
    }

    /// One bullet, with the "by @author in <PR url>" suffix and the trailing
    /// "**Full Changelog**" compare line stripped — both are noise, neither is a
    /// change. Mutation: parse with a hand-rolled pattern that keeps the suffix
    /// → the equality fails.
    @Test func theGeneratedBodyBecomesItsChanges() throws {
        let body = """
        ## What's Changed
        * chore(release): proxy 1.5.2 + app version 26.6.29 by @dinex-dev in https://github.com/requestly/http-interceptor-desktop-app/pull/362


        **Full Changelog**: https://github.com/requestly/http-interceptor-desktop-app/compare/v26.6.26...v26.6.29
        """
        let entry = try #require(GitHubMarkdownParser.parse(
            body: body, version: "26.6.29", date: nil)?.entries.first)
        #expect(entry.items == ["chore(release): proxy 1.5.2 + app version 26.6.29"])
    }
}
