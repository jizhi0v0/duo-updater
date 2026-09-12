import Testing
import Foundation
@testable import DuoUpdaterCore

/// `cline/cline` is a monorepo: one Releases list, four products. These tests
/// pin the `tagPattern` that separates Cline Desktop's releases from the VS Code
/// extension's, the CLI's and the SDK's — and that turns `desktop-v0.0.26` into
/// the `0.0.26` the row actually shows.
///
/// The fixture is seven real releases from the live `per_page=40` page fetched
/// 2026-09-12, with each `body` cut to its first bullet. Tags, `prerelease`,
/// `draft` and `published_at` are verbatim. The three foreign trains and the
/// rolling `desktop-beta` feed tag are in here precisely because they are what
/// the pattern has to reject.
private let clineReleasesFixture = """
[
  {
    "tag_name": "desktop-v0.0.26",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-11T07:46:42Z",
    "body": "- The composer now shows the current branch's GitHub pull request"
  },
  {
    "tag_name": "desktop-v0.0.25",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-10T04:57:15Z",
    "body": "- ChatGPT Subscription (Codex) now lists only the models your plan can use"
  },
  {
    "tag_name": "desktop-v0.0.23-beta.1",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-09-03T01:46:33Z",
    "body": "- Beta: configure and opt in to image generation under Customize"
  },
  {
    "tag_name": "v4.1.17",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-02T05:40:05Z",
    "body": "Everything here lands through the SDK bundle, so it applies to windows running that bundle."
  },
  {
    "tag_name": "cli-v3.0.61",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-02T04:49:47Z",
    "body": "- Cline now handles a running Hub that is older than your CLI."
  },
  {
    "tag_name": "sdk/sdk/v0.0.82",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-02T04:40:16Z",
    "body": "- Fixed tool calling being silently disabled for gateway models"
  },
  {
    "tag_name": "desktop-beta",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-08-18T01:42:25Z",
    "body": "Rolling release backing the beta desktop app auto-updater."
  }
]
"""

private func clineChangelogRecipe(_ channel: ReleaseChannel) throws -> ChangelogRecipe {
    let id = channel == .beta ? "bot.cline.app.beta" : "bot.cline.app"
    return try #require(
        ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == id && $0.channel == channel
        }, "no Cline changelog recipe for \(id) [\(channel.rawValue)]")
}

private func decoded(_ recipe: ChangelogRecipe) -> Changelog? {
    ChangelogService.parse(recipe, body: clineReleasesFixture)
}

/// The stable rail takes only `desktop-v<semver>`, and reports the semver — not
/// the tag. Both halves fail differently if dropped, so both are asserted:
/// without the filter the panel gains three other products' releases; without the
/// capture group every entry is titled `desktop-v0.0.26`.
@Test func clineStableChangelogTakesOnlyTheDesktopTrain() throws {
    let changelog = try #require(decoded(try clineChangelogRecipe(.stable)))
    #expect(changelog.entries.map(\.version) == ["0.0.26", "0.0.25"])
}

/// The beta rail takes only `-beta.N` desktop tags. The rolling `desktop-beta`
/// feed tag is `prerelease: true` and carries a real body, so the `prerelease`
/// filter alone lets it through — it is the entry that would otherwise sit in the
/// panel forever under a version string that never changes.
@Test func clineBetaChangelogTakesOnlyNumberedBetasNotTheRollingFeedTag() throws {
    let changelog = try #require(decoded(try clineChangelogRecipe(.beta)))
    #expect(changelog.entries.map(\.version) == ["0.0.23-beta.1"])
    #expect(!changelog.entries.contains { $0.version.contains("desktop") })
}

/// The counterfactual, measured rather than argued: this is what the panel would
/// hold if `tagPattern` were dropped from the stable recipe. Four of the six
/// entries belong to other products, and every version string is a raw tag.
///
/// Kept as a test rather than a comment because it is the only thing that fails
/// if someone "simplifies" the recipe back to the plain `.gitHubReleases` shape
/// every other GitHub-backed app here uses.
@Test func clineWithoutATagPatternWouldRenderThreeOtherProductsChangelogs() {
    let unfiltered = StructuredChangelogDecoder.decodeGitHubReleases(
        clineReleasesFixture, channel: .stable, maxEntries: 20)
    let versions = try! #require(unfiltered).entries.map(\.version)
    #expect(versions == [
        "desktop-v0.0.26", "desktop-v0.0.25", "4.1.17", "cli-v3.0.61", "sdk/sdk/v0.0.82",
    ])
    // Not one of them is the string the row shows for an installed 0.0.26.
    #expect(!versions.contains("0.0.26"))
}

/// A group-less `tagPattern` is a pure filter — the tag is then read the
/// unfiltered way (`stripLeadingV`). Pinned because the fallback is easy to
/// mistake for "returns nil", which would render an empty panel instead.
@Test func aGroupLessTagPatternFiltersWithoutRenamingTheEntry() throws {
    let recipe = ChangelogRecipe(
        bundleID: "bot.cline.app",
        source: URL(string: "https://api.github.com/repos/cline/cline/releases?per_page=40")!,
        mode: .json,
        maxEntries: 20,
        channel: .stable,
        structuredFormat: .gitHubReleases,
        tagPattern: #"^desktop-v[0-9.]+$"#)
    let changelog = try #require(ChangelogService.parse(recipe, body: clineReleasesFixture))
    #expect(changelog.entries.map(\.version) == ["desktop-v0.0.26", "desktop-v0.0.25"])
}

/// Cline's release bodies are bare `- ` bullet lists with no `##` headings.
/// `GitHubMarkdownParser` has a bullet pass, a lenient pass and a prose fallback;
/// this pins that the bullets are read as bullets, so a body that is ONLY bullets
/// never silently degrades into one prose blob.
@Test func clineBulletBodiesParseAsItemsNotProse() throws {
    let changelog = try #require(decoded(try clineChangelogRecipe(.stable)))
    let first = try #require(changelog.entries.first)
    #expect(first.items.count == 1)
    #expect(first.items[0].hasPrefix("The composer now shows"))
    #expect(first.date == "2026-09-11")
}
