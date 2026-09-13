import Foundation
import Testing

@testable import DuoUpdaterCore

/// Three releases from `api.github.com/repos/Homebrew/BrewUI/releases`
/// (fetched 2026-09-13), trimmed to the fields the decoder reads and to the
/// first few bullets of each body; the lines kept are verbatim. The newest
/// release, one carrying `@dependabot[bot]` entries, and a prerelease — whose
/// body uses CRLF, as the two earliest releases' do.
private let brewUIReleasesFixture = #"""
[{"tag_name": "v0.4.0", "prerelease": false, "draft": false, "published_at": "2026-09-10T13:39:07Z", "body": "## What's Changed\n* Remove title and icon from sidebar by @graeme in https://github.com/Homebrew/BrewUI/pull/158\n* README: replace BrewUI image with updated version by @MikeMcQuaid in https://github.com/Homebrew/BrewUI/pull/159\n\n\n**Full Changelog**: https://github.com/Homebrew/BrewUI/compare/v0.3.1...v0.4.0"},
 {"tag_name": "v0.2.2", "prerelease": false, "draft": false, "published_at": "2026-09-05T13:35:20Z", "body": "## What's Changed\n* Search bar escape crash by @graeme in https://github.com/Homebrew/BrewUI/pull/133\n* Bump the github-actions group across 1 directory with 5 updates by @dependabot[bot] in https://github.com/Homebrew/BrewUI/pull/135\n* Bump the bundler group across 2 directories with 4 updates by @dependabot[bot] in https://github.com/Homebrew/BrewUI/pull/136\n\n\n**Full Changelog**: https://github.com/Homebrew/BrewUI/compare/v0.2.1...v0.2.2"},
 {"tag_name": "v0.1.1", "prerelease": true, "draft": false, "published_at": "2026-07-19T03:41:57Z", "body": "## What's Changed\r\n* Upgrades tab by @graeme in https://github.com/Homebrew/BrewUI/pull/65\r\n* Synchronize shared configuration by @BrewTestBot in https://github.com/Homebrew/BrewUI/pull/66\r\n\r\n\r\n**Full Changelog**: https://github.com/Homebrew/BrewUI/compare/v0.1.0...v0.1.1"}]
"""#

@Suite struct BrewUIChangelogRecipeTests {

    /// BrewUI's update source is the Homebrew cask, which carries no notes; the
    /// notes are the GitHub releases the cask downloads from.
    @Test func readsGitHubReleases() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "sh.brew.app"))
        #expect(recipe.structuredFormat == .gitHubReleases)
        #expect(recipe.mode == .json)
        #expect(recipe.source.host == "api.github.com")
        #expect(recipe.source.path == "/repos/Homebrew/BrewUI/releases")
    }

    /// Newest first, `v` stripped so the heading is the version the row shows,
    /// dates as ISO days, and the prerelease left out.
    @Test func stableReleasesOnlyVersionedLikeTheCask() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(brewUIReleasesFixture, maxEntries: 20))
        #expect(log.entries.map(\.version) == ["0.4.0", "0.2.2"])
        #expect(log.entries.first?.date == "2026-09-10")
    }

    /// The generated lists end every item with `by @user in <PR URL>`, and the
    /// bot accounts spell the user `@dependabot[bot]`. Both must come off, and
    /// the Full Changelog footer must not become an item.
    @Test func itemsAreThePullRequestTitles() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(brewUIReleasesFixture, maxEntries: 20))
        #expect(log.entries.first?.items == [
            "Remove title and icon from sidebar",
            "README: replace BrewUI image with updated version",
        ])
        #expect(log.entries.last?.items == [
            "Search bar escape crash",
            "Bump the github-actions group across 1 directory with 5 updates",
            "Bump the bundler group across 2 directories with 4 updates",
        ])
    }
}
