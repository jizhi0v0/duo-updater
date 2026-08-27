import Foundation
import Testing

@testable import DuoUpdaterCore

/// Three releases from `api.github.com/repos/notnotDudu/shotbase-releases/releases`
/// (fetched 2026-08-27), verbatim bodies, trimmed to the fields the decoder reads.
/// One bulleted release, one prose-only release, and the prerelease baseline —
/// the three shapes this feed actually contains.
private let shotbaseReleasesFixture = #"""
[{"tag_name":"v1.3.0","prerelease":false,"draft":false,"published_at":"2026-08-25T19:35:24Z",
  "body":"## What’s new\n\n- Use Shotbase across up to three connected devices.\n- Improved reliability when triggering direct captures with keyboard shortcuts.\n- Standardized canvas size limits across capture workflows.\n- Improved selection cursor consistency.\n- Simplified account reconnection confirmation.\n\nSource build: [`cdbf36665fa8171efc75ff0ef05bef1cce2c0092`](https://github.com/notnotDudu/shotbase/commit/cdbf36665fa8171efc75ff0ef05bef1cce2c0092)"},
 {"tag_name":"v1.0.0","prerelease":false,"draft":false,"published_at":"2026-08-05T18:08:34Z",
  "body":"The first stable Shotbase release for macOS. Includes secure automatic updates through Sparkle."},
 {"tag_name":"v0.9.0","prerelease":true,"draft":false,"published_at":"2026-08-05T16:36:50Z",
  "body":"Public upgrade-rehearsal baseline for Shotbase. This prerelease is retained to verify the Sparkle update path to the stable 1.0.0 release."}]
"""#

@Suite struct ShotbaseChangelogRecipeTests {

    /// Shotbase's update source is its Sparkle appcast; its NOTES are on GitHub,
    /// because the appcast ships neither a `<description>` nor a
    /// `<sparkle:releaseNotesLink>` on any item. Same split as Waku.
    @Test func readsGitHubReleases() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.shotbase.app"))
        #expect(recipe.structuredFormat == .gitHubReleases)
        #expect(recipe.mode == .json)
        #expect(recipe.source.host == "api.github.com")
        #expect(recipe.source.path == "/repos/notnotDudu/shotbase-releases/releases")
    }

    /// Newest first, `v` stripped, dates as ISO days. The prerelease baseline is a
    /// track nobody opted into and must not appear in the rail.
    @Test func skipsThePrereleaseBaseline() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(shotbaseReleasesFixture, maxEntries: 20))
        #expect(log.entries.map(\.version) == ["1.3.0", "1.0.0"])
        #expect(log.entries.first?.date == "2026-08-25")
    }

    /// The bullets are the changes; the `Source build: [`<sha>`](…)` footer that
    /// closes every bulleted release is not one, and the strict bullet pass leaves
    /// it behind. If that ever changes, every Shotbase entry grows a commit hash.
    @Test func keepsTheBulletsAndDropsTheSourceBuildFooter() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(shotbaseReleasesFixture, maxEntries: 20))
        let latest = try #require(log.entries.first)
        #expect(latest.items.count == 5)
        #expect(latest.items.first == "Use Shotbase across up to three connected devices.")
        #expect(!latest.items.contains { $0.contains("Source build") })
    }

    /// v1.0.0's body is one sentence with no list at all. Dropping it would leave a
    /// hole in the rail for anyone still on 1.0.0, so the prose pass carries it.
    @Test func proseOnlyReleaseStillGetsAnEntry() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(shotbaseReleasesFixture, maxEntries: 20))
        #expect(log.entries.last?.items == [
            "The first stable Shotbase release for macOS. Includes secure automatic updates through Sparkle."
        ])
    }
}
