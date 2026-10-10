import Testing
import Foundation
@testable import DuoUpdaterCore

/// Telegram Desktop's notes come from `telegramdesktop/tdesktop`'s Releases.
/// Betas are tagged with plain numbers (`v7.2.10`) and marked only by GitHub's
/// `prerelease` bit, which the stable-only default must honour.
///
/// The fixture is four real releases from the live `per_page=40` page fetched
/// 2026-10-10, each `body` cut to its first three lines.
private let telegramReleasesFixture = #"""
[
  {
    "tag_name": "v7.3.1",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-10-10T13:03:14Z",
    "body": "- Fix wallet encryption with Windows Hello sometimes failing.\n- Fix same passcode saving in wallet encryption.\n- Fix copy-restricted media reaching Downloads."
  },
  {
    "tag_name": "v7.3.0",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-10-09T08:26:21Z",
    "body": "- Money."
  },
  {
    "tag_name": "v7.2.10",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-09-27T19:42:12Z",
    "body": "- Update emoji to Unicode 17.\n- Submit the rich messages editor with Ctrl+Enter.\n- Play audio tracks in a rich message as a playlist."
  },
  {
    "tag_name": "v7.2.9",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-17T09:31:34Z",
    "body": "- Fix some tlottie incorrect renderings."
  }
]
"""#

@Test func telegramChangelogReadsStableReleasesAndSkipsPlainNumberedBetas() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipes.first { $0.bundleID == "com.tdesktop.Telegram" })
    let changelog = try #require(ChangelogService.parse(recipe, body: telegramReleasesFixture))
    #expect(changelog.entries.map(\.version) == ["7.3.1", "7.3.0", "7.2.9"])
    let newest = try #require(changelog.entries.first)
    #expect(newest.date == "2026-10-10")
    #expect(newest.items.count == 3)
    #expect(newest.items.first == "Fix wallet encryption with Windows Hello sometimes failing.")
}
