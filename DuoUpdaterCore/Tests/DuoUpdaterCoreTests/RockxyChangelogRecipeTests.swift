import Foundation
import Testing

@testable import DuoUpdaterCore

/// Two releases from `api.github.com/repos/RockxyApp/Rockxy/releases` (fetched
/// 2026-09-09), bodies verbatim, trimmed to the fields the decoder reads. Both
/// carry the `> **Distribution notice:**` blockquote every Rockxy release opens
/// with — that is the shape this fixture exists for.
private let rockxyReleasesFixture = #"""
[{"tag_name":"v0.38.2","prerelease":false,"draft":false,"published_at":"2026-09-08T02:21:24Z",
  "body":"> **Distribution notice:** The attached DMG is the official Rockxy binary distribution under the Rockxy Binary EULA. It runs in Community mode without a purchase and can unlock Pro. The public tag identifies the separate AGPL Community source edition for this product version; it is not represented as the complete build source for the DMG.\n\n# Rockxy 0.38.2 (build 57)\n\n## Added\n\n- Added **Choose & Open Developer App** to Automatic Setup, so Rockxy can launch a fully quit macOS developer tool with scoped proxy and certificate settings without changing shell profiles.\n\n## Changed\n\n- Compatible helpers now refresh safely after app updates while preserving macOS approval; explicit action is required only for genuinely incompatible helpers.\n\n## Fixed\n\n- Restored recognized application proxy settings after prepared apps exit or Rockxy relaunches, while preserving newer user choices and unrelated settings.\n- Prevented interrupted recovery from overwriting newer capture sessions or manually changed system proxy settings.\n- Preserved each macOS network service's own proxy configuration during stop and recovery.\n- Improved helper, certificate, and TLS fallback behavior to reduce stuck capture states and restore application traffic more reliably.\n\n"},
 {"tag_name":"v0.38.1","prerelease":false,"draft":false,"published_at":"2026-09-05T09:39:28Z",
  "body":"> **Distribution notice:** The attached DMG is the official Rockxy binary distribution under the Rockxy Binary EULA. It runs in Community mode without a purchase and can unlock Pro. The public tag identifies the separate AGPL Community source edition for this product version; it is not represented as the complete build source for the DMG.\n\n# Rockxy 0.38.1 (build 56)\n\n## Fixed\n\n- Preserved the same Rockxy root certificate across app relaunches, preventing unexpected certificate replacement and repeated HTTPS inspection setup.\n- Made certificate installation, trust checks, and removal safer by targeting exact certificates, preserving unrelated roots, and preventing overlapping privileged changes.\n- Improved recovery for outdated helpers and unreadable certificate states with clearer recheck, reinstall, and trust guidance.\n- Clarified JetBrains IDE proxy setup and surfaced failed HTTPS CONNECT tunnels for easier diagnosis.\n\n"}]
"""#

@Suite struct RockxyChangelogRecipeTests {

    /// Rockxy's update source is the Sparkle appcast its own `SUFeedURL` names, so
    /// detection needs no recipe. Its NOTES come from GitHub because that appcast
    /// is rewritten in place and holds exactly one `<item>` — inline notes for the
    /// newest build and no history at all.
    @Test func readsGitHubReleases() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.amunx.rockxy.community"))
        #expect(recipe.structuredFormat == .gitHubReleases)
        #expect(recipe.mode == .json)
        #expect(recipe.source.host == "api.github.com")
        #expect(recipe.source.path == "/repos/RockxyApp/Rockxy/releases")
        // Without `skipSections` the recipe leans entirely on the strict bullet
        // pass to drop the distribution notice. Stating it here means adding one
        // later is a deliberate edit rather than a silent behaviour change.
        #expect(recipe.skipSections.isEmpty)
    }

    /// Newest first, `v` stripped so the rail version matches
    /// `CFBundleShortVersionString` (`v0.38.2` → `0.38.2`, which is what the real
    /// bundle reports), dates as ISO days.
    @Test func versionsAndDatesMatchTheInstalledVersionScheme() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(rockxyReleasesFixture, maxEntries: 20))
        #expect(log.entries.map(\.version) == ["0.38.2", "0.38.1"])
        #expect(log.entries.map(\.date) == ["2026-09-08", "2026-09-05"])
    }

    /// Every Rockxy release body opens with a `> **Distribution notice:**`
    /// blockquote about the binary EULA. It is not a change, and it is identical
    /// in all 40 releases on the live page — surfaced as an item it would be the
    /// first and longest line of every entry in the rail. The strict bullet pass
    /// drops it because it is not a top-level `-`/`*`/`+` bullet, which is why the
    /// recipe carries no `skipSections`; this is the assertion that keeps that
    /// argument honest.
    @Test func dropsTheDistributionNoticeBlockquote() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(rockxyReleasesFixture, maxEntries: 20))
        #expect(!log.entries.contains { $0.items.contains { $0.contains("Distribution notice") } })
        #expect(!log.entries.contains { $0.items.contains { $0.contains("Binary EULA") } })
    }

    /// The bullets under `## Added` / `## Changed` / `## Fixed` are the changes,
    /// flattened in document order — the headings themselves are not items, and
    /// none of the three is a section this app skips.
    @Test func keepsEveryBulletAcrossTheThreeSections() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(rockxyReleasesFixture, maxEntries: 20))
        let latest = try #require(log.entries.first)
        #expect(latest.items.count == 6)
        #expect(latest.items.first == "Added **Choose & Open Developer App** to Automatic Setup, so Rockxy can launch a fully quit macOS developer tool with scoped proxy and certificate settings without changing shell profiles.")
        #expect(latest.items.last == "Improved helper, certificate, and TLS fallback behavior to reduce stuck capture states and restore application traffic more reliably.")
        #expect(!latest.items.contains { $0 == "Added" || $0 == "Changed" || $0 == "Fixed" })
        #expect(log.entries.last?.items.count == 4)
    }

    /// The bullets keep their Markdown inline syntax (`**Choose & Open Developer
    /// App**`), so the changelog has to declare it or the renderer prints the
    /// asterisks verbatim.
    @Test func itemsAreMarkedAsMarkdown() throws {
        let log = try #require(
            StructuredChangelogDecoder.decodeGitHubReleases(rockxyReleasesFixture, maxEntries: 20))
        #expect(log.itemSyntax == .markdown)
    }
}
