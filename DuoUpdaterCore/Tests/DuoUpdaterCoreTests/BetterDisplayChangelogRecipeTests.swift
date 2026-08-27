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

/// v3.3.4 and v3.3.3 (fetched 2026-08-27), trimmed to the sections that matter and
/// two roster rows each; every line kept is verbatim. Together they hold all three
/// heading shapes this app has used: the roster spelled two ways, and — in v3.3.4,
/// one section above its own roster — `### Localization Improvements`, which is
/// real changes and must survive.
private let betterDisplayOlderReleasesFixture = #"""
[
 {
  "tag_name": "v3.3.4",
  "prerelease": false,
  "draft": false,
  "published_at": "2025-01-31T21:04:07Z",
  "body": "## About this version\n\nThis release focuses on enhanced localization support, improved macOS 15.3 compatibility, and various bug fixes.\r\n\n### Localization Improvements\n\n- A new language selection feature has been added to the Settings window (bottom-left corner) for easy language switching. - #3972\r\n- Incomplete localizations (below 90% completion) have been removed to ensure a consistent user experience. - #3977\r\n\n### Bug Fixes\n\n- Resolved an issue where some text appeared unlocalized regardless of settings - #3980\r\n- Corrected various typos in the base language text - #3975\r\n\n### Included Localizations\n\nThis release includes the following localizations, with thanks to our contributors:\r\n\n- British English (@PuzzledUser)\r\n- Chinese, Simplified (@BingoKingo, @shindgewongxj, @hshsilver, @jacktechstudio)\r"
 },
 {
  "tag_name": "v3.3.3",
  "prerelease": false,
  "draft": false,
  "published_at": "2025-01-25T09:14:58Z",
  "body": "### Enhancements\n\n- Improved mouse cursor responsiveness with mirrored virtual screens (thanks to @dave-fl) - #807\r\n\n### Localizations included in this release\n\n- **British English** (100%) -  @PuzzledUser\r\n- **French** (100%) - @Kcraft059\r"
 }
]
"""#

@Suite struct BetterDisplayChangelogRecipeTests {

    private func recipe(_ channel: ReleaseChannel) throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: BetterDisplayChannel.bundleID, channel: channel))
    }

    /// Decode the way `ChangelogService.parse` does — through the registered recipe,
    /// carrying its `skipSections`. A test that calls the decoder bare tests a
    /// configuration that never ships.
    private func decode(_ feed: String, _ channel: ReleaseChannel) throws -> Changelog {
        let r = try recipe(channel)
        let format = try #require(r.structuredFormat)
        return try #require(StructuredChangelogDecoder.decode(
            feed, format: format, channel: r.channel,
            maxEntries: r.maxEntries, skipSections: r.skipSections))
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

    /// The stable body as it actually ships: only the `### Changes` bullets survive.
    /// The intro prose, the pre-release promo and the "For previous release notes"
    /// line are dropped for being non-bullets; the two rows under
    /// `### Included Localizations` are dropped by `skipSections`.
    @Test func theStableBodyKeepsOnlyItsChangeBullets() throws {
        let entry = try #require(decode(betterDisplayReleasesFixture, .stable).entries.first)
        #expect(entry.items.count == 2)
        #expect(entry.items[0].hasPrefix("Fixed DDC capability retrieval"))
        #expect(entry.items[1].hasPrefix("Improved default nits values"))
        #expect(!entry.items.contains { $0.contains("For previous release notes") })
        #expect(!entry.items.contains { $0.contains("service release focused on bug fixes") })
    }

    // MARK: - The contributor roster

    /// All three tracks carry the same roster headings, from one shared constant —
    /// a fourth spelling must not have to be added in three places.
    @Test func everyTrackSkipsTheSameRosterHeadings() throws {
        for r in ChangelogRecipeRegistry.recipes(forBundleID: BetterDisplayChannel.bundleID) {
            #expect(r.skipSections == [
                "Included Localizations", "Localizations included in this release",
            ])
        }
    }

    /// Both spellings of the roster go, in the modern one-bullet-per-release form
    /// and the old one-bullet-per-language form.
    @Test func bothSpellingsOfTheRosterAreDropped() throws {
        let items = try decode(betterDisplayOlderReleasesFixture, .stable)
            .entries.flatMap(\.items)
        #expect(!items.contains { $0.contains("@PuzzledUser") })
        #expect(!items.contains { $0.contains("British English") })
        #expect(!items.contains { $0.contains("with thanks to our contributors") })

        let latest = try #require(decode(betterDisplayReleasesFixture, .stable).entries.first)
        #expect(!latest.items.contains { $0.hasPrefix("Contributors: @") })
    }

    /// The whole point of matching a WHOLE heading rather than a substring.
    /// `### Localization Improvements` sits one section above the roster in the very
    /// same v3.3.4 body and holds real changes — a language switcher, and the removal
    /// of under-90% translations. A `localization` keyword would take both.
    @Test func aRealLocalizationSectionIsNotMistakenForTheRoster() throws {
        let entry = try #require(decode(betterDisplayOlderReleasesFixture, .stable).entries.first)
        #expect(entry.version == "3.3.4")
        #expect(entry.items.count == 4)
        #expect(entry.items[0].hasPrefix("A new language selection feature"))
        #expect(entry.items[1].hasPrefix("Incomplete localizations (below 90% completion)"))
        #expect(entry.items[2].hasPrefix("Resolved an issue where some text appeared unlocalized"))
    }

    /// A recipe with no `skipSections` is untouched — the default every other
    /// `.gitHubReleases` recipe runs on. Same fixture, same channel, roster intact.
    @Test func anEmptySkipListChangesNothing() throws {
        let log = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            betterDisplayReleasesFixture, channel: .stable, maxEntries: 15))
        let entry = try #require(log.entries.first)
        #expect(entry.items.count == 4)
        #expect(entry.items[3].hasPrefix("Contributors: @afkeceli"))
    }
}
