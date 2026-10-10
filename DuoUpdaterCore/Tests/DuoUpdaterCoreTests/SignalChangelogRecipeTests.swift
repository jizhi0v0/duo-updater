import Testing
import Foundation
@testable import DuoUpdaterCore

/// Signal Stable and Signal Beta read one Releases list
/// (`signalapp/Signal-Desktop`); GitHub's `prerelease` bit is set on exactly the
/// `-beta.N` tags, so each channel's recipe takes its own side of it.
///
/// The fixture is five real releases from the live `per_page=40` page fetched
/// 2026-10-10, verbatim (Signal's bodies are this short). `v8.28.0` is the
/// one stable body with no list marker, so it exercises the prose path.
private let signalReleasesFixture = #"""
[
  {
    "tag_name": "v8.31.0-beta.1",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-10-07T19:48:49Z",
    "body": "- Handful of bug fixes to keep your app running smoothly. More exciting changes on the horizon!"
  },
  {
    "tag_name": "v8.30.0",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-10-07T19:27:43Z",
    "body": "- Thanks to a few performance improvements, your CPU will be slightly happier during video calls (even if you're not smiling).\r\n- We also added a convenient shortcut to open your system settings on Windows if you try to join a video call and Signal doesn't have permission to access the camera. Now it's easier to see what you need to do so that people can see you.\r\n"
  },
  {
    "tag_name": "v8.30.0-beta.1",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-10-01T21:47:21Z",
    "body": "- Thanks to a few performance improvements, your CPU will be slightly happier during video calls (even if you're not smiling).\r\n- We also added a convenient shortcut to open your system settings on Windows if you try to join a video call and Signal doesn't have permission to access the camera. Now it's easier to see what you need to do so that people can see you.\r\n"
  },
  {
    "tag_name": "v8.29.0",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-10-01T21:20:34Z",
    "body": "- Additional small tweaks, bug fixes, and performance enhancements. Thanks for using Signal!"
  },
  {
    "tag_name": "v8.28.0",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-23T21:28:17Z",
    "body": "Small tweaks, bug fixes, and performance enhancements. Thanks for using Signal!"
  }
]
"""#

private func signalRecipe(_ id: String) throws -> ChangelogRecipe {
    try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == id })
}

@Test func signalStableChangelogReadsOnlyStableReleases() throws {
    let recipe = try signalRecipe("org.whispersystems.signal-desktop")
    let changelog = try #require(ChangelogService.parse(recipe, body: signalReleasesFixture))
    #expect(changelog.entries.map(\.version) == ["8.30.0", "8.29.0", "8.28.0"])
    #expect(changelog.entries.first?.date == "2026-10-07")
    #expect(changelog.entries.first?.items.count == 2)
    #expect(changelog.entries.last?.items
        == ["Small tweaks, bug fixes, and performance enhancements. Thanks for using Signal!"])
}

/// The beta rail is a separate app whose feed only ever offers `-beta.N`
/// builds, so it takes prereleases only and the version keeps its suffix, the
/// same string `beta-mac.yml` offers.
@Test func signalBetaChangelogReadsOnlyBetaReleases() throws {
    let recipe = try signalRecipe("org.whispersystems.signal-desktop-beta")
    #expect(recipe.channel == .beta)
    #expect(recipe.includesPromotedStable == false)
    let changelog = try #require(ChangelogService.parse(recipe, body: signalReleasesFixture))
    #expect(changelog.entries.map(\.version) == ["8.31.0-beta.1", "8.30.0-beta.1"])
    #expect(changelog.entries.first?.items
        == ["Handful of bug fixes to keep your app running smoothly. More exciting changes on the horizon!"])
}
