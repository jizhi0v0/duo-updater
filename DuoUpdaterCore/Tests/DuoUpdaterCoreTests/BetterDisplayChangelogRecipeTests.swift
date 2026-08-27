import Foundation
import Testing

@testable import DuoUpdaterCore

/// Two releases from `api.github.com/repos/waydabber/BetterDisplay/releases`
/// (fetched 2026-08-27): the newest stable and the newest plain pre-release, which
/// is also the shape that has no bullets at all. v4.3.6's body is trimmed to one
/// item per region — the two headings, the localization pair, the trailing links
/// line and the download button are what the parser has to make decisions about;
/// the other five change bullets add nothing to the test. Everything kept is
/// verbatim. v5.0.2's body is whole.
private let betterDisplayReleasesFixture = #"""
[
 {
  "tag_name": "v5.0.2",
  "prerelease": true,
  "draft": false,
  "published_at": "2026-08-11T17:40:35Z",
  "body": "This updated BetterDisplay 5 pre-release adds improved soft-disconnected display handling, direct display connection controls in Settings, new display-group actions, and better touch compatibility on macOS 27 Golden Gate. Additionally, this version reintroduces Intel support for macOS 26 Tahoe. Other highlights in BetterDisplay 5 include advanced compositor filters, expanded display reporting and integration capabilities, HDMI-CEC control, improved per-display automation, app menu and OSD refinements, performance improvements, custom 3D LUT filters, a built-in app console, and compatibility updates for the latest macOS versions.\r\n\r\n_Please note that this pre-release was tested with macOS 27 Golden Gate public beta 3 (developer beta 5) and may not be fully compatible with earlier or later macOS 27 versions - an [updated release](https://github.com/waydabber/BetterDisplay/releases) is available._\r\n\r\n<a href=\"https://github.com/waydabber/BetterDisplay/releases/download/v5.0.2/BetterDisplay-v5.0.2-pre-release.dmg\"><img src=\"https://user-images.githubusercontent.com/37590873/219133640-8b7a0179-20a7-4e02-8887-fbbd2eaad64b.png\" width=\"175\" alt=\"Download for macOS\"/></a>"
 },
 {
  "tag_name": "v4.3.6",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-08-11T17:40:14Z",
  "body": "This version is a service release focused on bug fixes and compatibility improvements with macOS 27.\r\n\n_**macOS 27 Golden Gate beta users:** try the latest v5.x pre-release for even better macOS 27 support and additional features. BetterDisplay 5 supports macOS 26 or later (Apple Silicon & Intel). Go to `Settings` > `Application` > `Updates`, enable `Receive pre-release updates`, then use `Check for Updates`._\r\n\n### Changes\n\n- Fixed DDC capability retrieval through the console potentially hanging indefinitely - #5674\r\n- Improved default nits values for built-in displays on Intel Macs - #5684\r\n\n### Included Localizations\n\n- British English, Chinese Simplified, Chinese Traditional, Dutch, French, German, Hungarian, Italian, Japanese, Korean, Norwegian Bokmål, Polish, Portuguese Brazil, Romanian, Russian, Slovenian, Spanish, Swedish, Turkish, Ukrainian, and Vietnamese.\r\n- Contributors: @afkeceli, @AndryTi, @andrwmai, @BingoKingo, @brzenio, @cfuentea, @chihuahua-experience, @cristianritco, @dimaitre, @dotWee, @DrRoglaa, @dvanzoerlandt, @elislays08, @enormous-rat, @giulianopires, @gpnunes75, @HaiBliss, @hshsilver, @hw0603, @ibrayd, @jacktechstudio, @JulyIghor, @Kcraft059, @MapleLeaf14, @marcinkardas, @maximsenterprise, @MazlumSerbest, @mickimnet, @mikevic18, @MonolitheMedia, @moriLiu, @MStankiewiczOfficial, @niklasbogensperger, @old-cookie, @PatrykM13, @pavlik000-collab, @PuzzledUser, @SakiPapa, @shindgewongxj, @skantek, @sm-moshi, @stonkol, @sup3rb3ar, @yeager, @waydabber. AI was used for updating some of the localizations.\r\n\nFor previous release notes, visit the [GitHub Releases page](https://github.com/waydabber/BetterDisplay/releases). [Outdated license FAQ](https://github.com/waydabber/BetterDisplay/discussions/4620).\r\n\n<a href=\"https://github.com/waydabber/BetterDisplay/releases/download/v4.3.6/BetterDisplay-v4.3.6.dmg\"><img src=\"https://user-images.githubusercontent.com/37590873/219133640-8b7a0179-20a7-4e02-8887-fbbd2eaad64b.png\" width=\"175\" alt=\"Download for macOS\"/></a>"
 }
]
"""#

@Suite struct BetterDisplayChangelogRecipeTests {

    private func recipe(_ channel: ReleaseChannel) throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: BetterDisplayChannel.bundleID, channel: channel))
    }

    /// All three tracks read the same GitHub releases endpoint; only `channel`
    /// differs, and that is what splits the feed inside the decoder.
    @Test func everyTrackIsRegisteredAgainstTheReleasesAPI() throws {
        let all = ChangelogRecipeRegistry.recipes(forBundleID: BetterDisplayChannel.bundleID)
        #expect(all.count == 3)
        #expect(Set(all.map(\.channel)) == [.stable, .beta, .unstable])
        for r in all {
            #expect(r.structuredFormat == .gitHubReleases)
            #expect(r.mode == .json)
            #expect(r.source.host == "api.github.com")
            #expect(r.source.path == "/repos/waydabber/BetterDisplay/releases")
        }
    }

    /// The internal track has no per-version notes of its own — its appcast items
    /// link `changelog.html?tag=pre`, a rolling release whose body is boilerplate
    /// (see `BetterDisplayChannel`). It is registered explicitly against the
    /// pre-release feed BECAUSE the lookup's last resort is the `.stable` recipe:
    /// without this registration someone on an internal 5.x build would be shown
    /// the 4.x stable notes.
    @Test func theInternalTrackReadsPreReleasesNotStable() throws {
        #expect(try recipe(.unstable).channel == .unstable)
        #expect(try recipe(.stable).channel == .stable)
        #expect(try recipe(.beta).channel == .beta)
    }

    /// `prerelease` is the track split. A stable install must never be shown a
    /// pre-release's notes, and vice versa.
    @Test func theChannelDecidesWhichSideOfTheFeedIsRead() throws {
        let stable = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            betterDisplayReleasesFixture, channel: .stable, maxEntries: 15))
        #expect(stable.entries.map(\.version) == ["4.3.6"])

        for prereleaseTrack: ReleaseChannel in [.beta, .unstable] {
            let pre = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
                betterDisplayReleasesFixture, channel: prereleaseTrack, maxEntries: 15))
            #expect(pre.entries.map(\.version) == ["5.0.2"], "\(prereleaseTrack)")
        }
    }

    /// No channel means stable only — the behavior every other `.gitHubReleases`
    /// recipe (Waku, Shotbase) relies on, none of which registers a channel.
    @Test func noChannelStillMeansStableOnly() throws {
        let log = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            betterDisplayReleasesFixture, channel: nil, maxEntries: 15))
        #expect(log.entries.map(\.version) == ["4.3.6"])
    }

    /// Every BetterDisplay release closes with an HTML download button. It is not a
    /// change, and it is worse than useless as an item: `<a href=…><img …/></a>`
    /// reaches the pane as literal angle brackets. On a bulleted release the strict
    /// pass never sees it; on a bullet-less one like v5.0.2 the prose pass does, and
    /// `isImageOnly` is what drops it. Measured before the fix: 14 items across the
    /// two tracks of the live 40-release feed were that markup.
    @Test func theDownloadButtonIsNeverAChangeItem() throws {
        for channel: ReleaseChannel in [.stable, .beta] {
            let log = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
                betterDisplayReleasesFixture, channel: channel, maxEntries: 15))
            let items = log.entries.flatMap(\.items)
            #expect(!items.contains { $0.contains("<img") || $0.contains("<a href") })
            #expect(!items.contains { $0.contains("Download for macOS") })
        }
    }

    /// v5.0.2 has no list at all, so the prose pass carries it: two paragraphs of
    /// real notes, and nothing else from a body whose third line is the button.
    @Test func theBulletlessPreReleaseKeepsItsProse() throws {
        let log = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            betterDisplayReleasesFixture, channel: .beta, maxEntries: 15))
        let entry = try #require(log.entries.first)
        #expect(entry.date == "2026-08-11")
        #expect(entry.items.count == 2)
        #expect(entry.items[0].hasPrefix("This updated BetterDisplay 5 pre-release adds"))
        #expect(entry.items[1].hasPrefix("_Please note that this pre-release was tested"))
    }

    /// The stable body's own decisions: the seven-region trim keeps the `### Changes`
    /// bullets and the two under `### Included Localizations` (a real section of the
    /// vendor's notes, not contributor noise GitHub generates), and drops the intro
    /// prose, the pre-release promo and the "For previous release notes" line —
    /// none of which is a bullet.
    @Test func theStableBodyKeepsOnlyItsBullets() throws {
        let log = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            betterDisplayReleasesFixture, channel: .stable, maxEntries: 15))
        let entry = try #require(log.entries.first)
        #expect(entry.items.count == 4)
        #expect(entry.items[0].hasPrefix("Fixed DDC capability retrieval"))
        #expect(entry.items[3].hasPrefix("Contributors: @afkeceli"))
        #expect(!entry.items.contains { $0.contains("For previous release notes") })
        #expect(!entry.items.contains { $0.contains("service release focused on bug fixes") })
    }
}
