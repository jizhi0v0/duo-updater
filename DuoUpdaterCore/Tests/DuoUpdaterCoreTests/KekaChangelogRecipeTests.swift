import Testing
import Foundation
@testable import DuoUpdaterCore

/// Keka's changelog comes from its GitHub release bodies, which carry the
/// vendor's `## Fixes` / `## Formats` / `## Translations` sections; the Sparkle
/// feed inlines nothing and the vendor's changelog pages are flat.
///
/// The fixture is five real releases from `api.github.com/repos/aonez/Keka/releases`
/// fetched 2026-10-08, emitted with `json.dumps` so the `\r\n` line endings stay
/// as the API serves them. Tags, `prerelease`, `draft`, `published_at` are
/// verbatim. The first three bodies are whole; the last two are cut to their
/// first lines. `v1.2.0-dev.3742` is the one dev build published with
/// `prerelease: false`, and `dev-test-builds` is the vendor's rolling test-build
/// release.
private let kekaReleasesFixture = #"""
[
  {
    "tag_name": "v1.6.8",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-24T06:39:57Z",
    "body": "👉 Do not miss [Keka for iOS](https://ios.keka.io) 🤩🤩🤩\r\n👉 Follow us on [Mastodon](https://techhub.social/@keka) and [X](https://x.com/kekaosx) to get all the Keka news\r\n\r\nThis is a maintenance release.\r\n\r\n## Fixes\r\n- Fixed custom task counter in the Dock not differentiating active/total tasks in some cases\r\n- Fixed password encoding detection in plain text (Thanks to @vollkommenIrrelevant) [#1774](https://github.com/aonez/Keka/issues/1774)\r\n- Fixed non tarball ZSTD extraction with very small sizes (Thanks to @ahaley2013) [#1777](https://github.com/aonez/Keka/issues/1777)\r\n\r\n## Formats\r\n- Updated 7ZZ from 26.02 to 26.03 (Thanks to Igor Pavlov)\r\n- Updated XZ from 5.8.3 to 5.8.4 (Thanks to Lasse Collin)\r\n- Updated UNRAR from 7.13 to 7.23 (Thanks to rarlab)\r\n- Updated BSDTAR from 3.8.7 to 3.8.9 (Thanks to Tim Kientzle and authors)\r\n\r\n## Translations\r\n- Simplified Chinese translation updated (Thanks to @maxsky from https://maxsky.cc) [#1764](https://github.com/aonez/Keka/issues/1764)\r\n- Korean translation updated (Thanks to @hooray804) [#1767](https://github.com/aonez/Keka/issues/1767)\r\n- Czech translation updated (Thanks to @ferben) [#1773](https://github.com/aonez/Keka/issues/1773)\r\n"
  },
  {
    "tag_name": "v1.6.7",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-06-30T12:42:14Z",
    "body": "👉 Do not miss [Keka for iOS](https://ios.keka.io) 🤩🤩🤩\r\n👉 Follow us on [Mastodon](https://techhub.social/@keka) and [X](https://x.com/kekaosx) to get all the Keka news\r\n\r\nThis is a hot-fix release.\r\n\r\n## Fixes\r\n- Reverted BSDTAR from 3.8.8 to 3.8.7 due to issues on macOS 26.5.2 (Thanks to @suishouen) #1762\r\n\r\n# Changes in version 1.6.6\r\n\r\n## Fixes\r\n- Enhanced ISO detection and extraction (Thanks to @frvctal) [#1756](https://github.com/aonez/Keka/issues/1756)\r\n\r\n## Formats\r\n- Updated 7ZZ from 26.01 to 26.02 (Thanks to Igor Pavlov)\r\n- Updated BSDTAR from 3.8.7 to 3.8.8 (Thanks to Tim Kientzle and authors)\r\n- Updated LZIP from 1.25 to 1.26 (Thanks to Antonio Diaz Diaz)\r\n- Updated PLZIP from 1.12 to 1.13 (Thanks to Antonio Diaz Diaz)\r\n- Updated XZ from 5.8.1 to 5.8.3 (Thanks to Lasse Collin)\r\n- Stripped P7ZIP ARM support, only used as fallback on 10.13 or older (Intel)\r\n\r\n## Translations\r\n- Japanese translation updated (Thanks to @SakiPapa) [#1753](https://github.com/aonez/Keka/issues/1753) [#1761](https://github.com/aonez/Keka/issues/1761)"
  },
  {
    "tag_name": "v1.5.2-dev.r5614",
    "prerelease": true,
    "draft": false,
    "published_at": "2025-06-22T09:20:15Z",
    "body": "👉 Do not miss the newly introduced [Keka for iOS](https://ios.keka.io) 🤩🤩🤩\r\n👉 Follow us on [Mastodon](https://techhub.social/@keka) and [X](https://x.com/kekaosx) to get all the Keka news\r\n\r\nThis is a fix release for **macOS 26 Tahoe**. Check out all the [1.5 release changes](https://github.com/aonez/Keka/releases/tag/v1.5.0).\r\n\r\n## Changes since build 5608\r\n- Using Liquid icon on macOS 11 and later\r\n- Squish face limited to macOS 15 or older\r\n\r\n### All 1.5.2 changes:\r\n- https://github.com/aonez/Keka/releases/tag/v1.5.2-dev.r5608\r\n"
  },
  {
    "tag_name": "v1.2.0-dev.3742",
    "prerelease": false,
    "draft": false,
    "published_at": "2019-12-20T12:35:55Z",
    "body": "This is an early stage version that, although very stable, may contain some bugs. Use at your own risk.\r\n\r\nPlease focus on the new queue system and report anything you find 🐞 in the issue #21.\r\nAnything else report it in the Issues section.\r\n\r\nChanges in this revision:\r\n- Merged all fixes and features from 1.1 branch up to 1.1.24\r\n- Enhanced custom name configuration #236 #237 #501\r\n- Using parent folder name instead of default name (option) #188"
  },
  {
    "tag_name": "dev-test-builds",
    "prerelease": true,
    "draft": false,
    "published_at": "2019-12-10T12:40:12Z",
    "body": "<!---\r\nNo current test versions, check the beta versions instead 👉 https://beta.keka.io\r\n--->\r\n\r\nHere are most recent Keka tests builds:\r\n\r\n- Keka-v1.6.8.r5734:\r\n  - Fixed custom task counter in the Dock not differentiating active/total tasks in some cases"
  }
]
"""#

private func kekaRecipe() throws -> ChangelogRecipe {
    try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.aone.keka"),
                 "no Keka changelog recipe")
}

private func headings(_ entry: Changelog.Entry) -> [String] {
    entry.content.compactMap { block in
        if case .heading(let text) = block { return text }
        return nil
    }
}

@Test func kekaRecipeReadsStableReleasesWithTheirSections() throws {
    let recipe = try kekaRecipe()
    let changelog = try #require(ChangelogService.parse(recipe, body: kekaReleasesFixture))

    #expect(changelog.entries.map(\.version) == ["1.6.8", "1.6.7"])

    let newest = try #require(changelog.entries.first)
    #expect(newest.date == "2026-09-24")
    #expect(newest.items.count == 10)
    #expect(headings(newest) == ["Fixes", "Formats", "Translations"])
    #expect(newest.items.first
            == "Fixed custom task counter in the Dock not differentiating active/total tasks in some cases")
    #expect(newest.items.last
            == "Czech translation updated (Thanks to @ferben) [#1773](https://github.com/aonez/Keka/issues/1773)")
    // The promo lines and the one-line summary above the first heading are
    // prose, not bullets, so they are never items.
    #expect(!newest.items.contains { $0.contains("👉") || $0.contains("maintenance release") })
}

/// 1.6.7's body restates 1.6.6 under `# Changes in version 1.6.6`. 1.6.6 is
/// older than 1.6.7, so `GitHubMarkdownParser` drops that heading and
/// everything under it: the entry is the hot fix alone. Its one `Fixes`
/// heading has no sibling left, so it is not styled.
@Test func kekaHotFixEntryDropsTheRestatedPreviousRelease() throws {
    let recipe = try kekaRecipe()
    let changelog = try #require(ChangelogService.parse(recipe, body: kekaReleasesFixture))
    let hotFix = try #require(changelog.entries.first { $0.version == "1.6.7" })
    #expect(hotFix.date == "2026-06-30")
    #expect(hotFix.items == [
        "Reverted BSDTAR from 3.8.8 to 3.8.7 due to issues on macOS 26.5.2 (Thanks to @suishouen) #1762",
    ])
    #expect(headings(hotFix).isEmpty)
}

/// Dev builds never render as releases on a stable copy. The prerelease flag
/// covers `v1.5.2-dev.r5614` and `dev-test-builds`; `v1.2.0-dev.3742` is
/// flagged stable, and only `tagPattern` keeps it out.
@Test func kekaRecipeExcludesDevBuildsEvenWhenFlaggedStable() throws {
    let recipe = try kekaRecipe()
    let changelog = try #require(ChangelogService.parse(recipe, body: kekaReleasesFixture))
    #expect(!changelog.entries.contains { $0.version.contains("dev") })

    let flagOnly = try #require(StructuredChangelogDecoder.decode(
        kekaReleasesFixture, format: .gitHubReleases, channel: recipe.channel,
        maxEntries: recipe.maxEntries, tagPattern: nil))
    #expect(flagOnly.entries.map(\.version) == ["1.6.8", "1.6.7", "1.2.0-dev.3742"])
}
