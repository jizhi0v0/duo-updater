import Testing
import Foundation
@testable import DuoUpdaterCore

/// Element Stable's notes come from `element-hq/element-web`'s Releases, which
/// also publish the module packages (`module/banner/v2.1.1`) as NON-prerelease
/// releases. These tests pin the `tagPattern` that keeps those out.
///
/// The fixture is five real releases from the live `per_page=40` page fetched
/// 2026-10-10, each `body` cut to its first lines. Tags, `prerelease`, `draft`
/// and `published_at` are verbatim.
private let elementReleasesFixture = #"""
[
  {
    "tag_name": "v1.12.31-rc.1",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-10-08T12:50:54Z",
    "body": "## ✨ Features\n\n* Do not allow skip device verification by default ([#35259](https://github.com/element-hq/element-web/pull/35259)). Contributed by @mxandreas.\n* Collection of EN string changes, Pt. 2 ([#35289](https://github.com/element-hq/element-web/pull/35289)). Contributed by @dbkr."
  },
  {
    "tag_name": "v1.12.30",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-29T13:14:47Z",
    "body": "## 🦖 Deprecations\n\n* Remove legacy Module \\& Customisation API ([#33941](https://github.com/element-hq/element-web/pull/33941)). Contributed by @t3chguy."
  },
  {
    "tag_name": "module/banner/v2.1.1",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-29T10:10:38Z",
    "body": "## What's Changed\r\n* Fix banner module's logo_href not working in Univention mode by @t3chguy in https://github.com/element-hq/element-web/pull/35236\r"
  },
  {
    "tag_name": "v1.12.29",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-22T12:51:06Z",
    "body": "Update modules in element-web modules Docker image"
  },
  {
    "tag_name": "v1.12.28",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-16T12:13:56Z",
    "body": "## ⚠️ Important\r\n\r\nDesktop releases now require glibc 2.34, ie. Debian bookworm or Ubuntu 22.04. Support for Debian bullseye and Ubuntu earlier than 22.04 has been dropped since Debian bullseye's LTS support period has now ended. If you are running a version of these OSes for which support has been dropped (or another distribution using glibc earlier than 2.34) you will need to upgrade your OS to continue using Element Desktop.\r"
  }
]
"""#

private func elementRecipe() throws -> ChangelogRecipe {
    try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == "im.riot.app" })
}

@Test func elementChangelogReadsOnlyDesktopVersionTags() throws {
    let changelog = try #require(ChangelogService.parse(try elementRecipe(), body: elementReleasesFixture))
    // Release candidate (prerelease) and module package (stable!) both dropped.
    #expect(changelog.entries.map(\.version) == ["1.12.30", "1.12.29", "1.12.28"])
    let newest = try #require(changelog.entries.first)
    #expect(newest.date == "2026-09-29")
    #expect(newest.items.first?.hasPrefix(#"Remove legacy Module \& Customisation API"#) == true)
    #expect(changelog.entries[1].items == ["Update modules in element-web modules Docker image"])
}

/// The counterfactual: without `tagPattern` the module package renders as an
/// Element entry under its raw tag.
@Test func elementWithoutATagPatternWouldRenderTheModulePackage() throws {
    let unfiltered = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
        elementReleasesFixture, channel: .stable, maxEntries: 20))
    #expect(unfiltered.entries.map(\.version).contains("module/banner/v2.1.1"))
}

/// Nightly's `YYYYMMDDNN` stamps have no release of their own, so no recipe.
@Test func elementNightlyHasNoChangelogRecipe() {
    #expect(!ChangelogRecipeRegistry.recipes.contains { $0.bundleID == "im.riot.nightly" })
}
