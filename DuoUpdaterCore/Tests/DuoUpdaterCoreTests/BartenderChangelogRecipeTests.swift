import Testing
import Foundation
@testable import DuoUpdaterCore

/// `https://downloads.macbartender.com/B2/updates/6-5-2/rnotes.html` as served
/// (fetched 2026-10-10), the Cloudflare email-decode `<script>` dropped. Product
/// headings ("Bartender 6", "Top Shelf") and category headings ("Fixes", "New")
/// are all `<h3>`; the intro and the closing note are `<p>`.
private let bartenderPageFixture = #"""
<html>

<head>
  <meta http-equiv="content-type" content="text/html;charset=utf-8">
  <title>Release Notes</title>
  <meta name="robots" content="anchors">
  <link href="rnotes.css" type="text/css" rel="stylesheet" media="all">
</head>

<body>

  <table class="dots" width="100%" border="0" cellspacing="0" cellpadding="0" summary="Two column table with heading">
    <tr>
      <td class="blue" colspan="2">
        <h2>Bartender 6.5.2</h2>
      </td>
    </tr>
    <tr>
      <p>
        This update for Bartender brings some improvements to pro onboarding, a new airpods activity, and some small fixes for users on large monitors.
      </p>
      <td valign="top" class="gap">
        <h3 class="section_heading">Bartender 6</h3>
        <h3>Fixes</h3>
        <ul>
          <li>Users on extremeley wide displays will no longer see artifacts in the menu bar</li>
          <li>If you've purchased Bartender previously and choose to upgrade to Mega, you can now update your license from the license page, to another key.</li>
        </ul>
        <h3 class="section_heading">Top Shelf</h3>
        <h3>New</h3>
        <ul>
          <li>You can now enable Connection Alerts &amp; Low Battery Alerts for your AIrpods in the Status Section of Top Shelf</li>
        </ul>
        <h3>Fixes</h3>
        <ul>
          <li>The "Hover here" option now correctly aligns with the indicators in onboarding</li>
          <li>You can also now skip the demo entirely</li>
        </ul>
        <p>
          If you face any issues with this update, or want to share a feature request, please reach out to us.
          <br>
          <a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="d6a5a3a6a6b9a4a296bbb7b5b4b7a4a2b3b8b2b3a4f8b5b9bb">[email&#160;protected]</a>
        </p>
      </td>
    </tr>
  </table>


</body>

</html>
"""#

/// `…/6-0-3/rnotes.html` (fetched 2026-10-10), cut to its body: a page with no
/// list at all.
private let bartenderProsePageFixture = #"""
<body>

  <table class="dots" width="100%" border="0" cellspacing="0" cellpadding="0" summary="Two column table with heading">
    <tr>
      <td class="blue" colspan="2">
        <h2>Bartender 6.0.3</h2>
      </td>
    </tr>
    <tr>
      <td valign="top" class="gap">
        <p>
          We've resolved issues with the cursor feeling a little sluggish, or jumping whilst you move items.
        </p>

      </td>
    </tr>
  </table>

</body>
"""#

/// The appcast (fetched 2026-10-10), cut to three of its sixteen items: the
/// oldest, which links the bare host, and the two newest, which link
/// `downloads.`. Ascending, like the real feed, so a reader that takes the first
/// item resolves 6.0.0's page and fails.
private let bartenderAppcastFixture = #"""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
	xmlns:dc="http://purl.org/dc/elements/1.1/">
	<channel>
		<title>Bartender 6 Changelog</title>
		<link>http://macbartender.com/B2/updates/AppcastB6.xml</link>
		<description>Most recent changes with links to updates.</description>
		<language>en</language>
		<item>
			<title>Version 6.0.0</title>
			<sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
			<sparkle:version>600000</sparkle:version>
			<sparkle:shortVersionString>6.0.0</sparkle:shortVersionString>
			<sparkle:releaseNotesLink>https://macbartender.com/B2/updates/6-0-0/rnotes.html</sparkle:releaseNotesLink>
			<pubDate>September 13, 2025 09:45:00 +0000</pubDate>
			<enclosure url="https://macbartender.com/B2/updates/6-0-0/Bartender%206.zip" type="application/octet-stream" sparkle:dsaSignature="MCwCFH2p482/EsOcyPFvZnRnJDwMGdJdAhRrcn8AOE0fbu4XFDIu+DmK3dnvpw==" sparkle:edSignature="I/Pj6gMbzc1Joj5i26Xas6OcuAt+aAnZdzxTrBQMAbC/ASbkDfKNFlQSupnILaARCV9wT/vSfpU8h8dA+Y6fCg==" length="29924006" />
		</item>
	<item>
    <title>Version 6.6.1</title>
    <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
    <sparkle:version>661000</sparkle:version>
    <sparkle:shortVersionString>6.6.1</sparkle:shortVersionString>
    <sparkle:releaseNotesLink>https://downloads.macbartender.com/B2/updates/6-6-1/rnotes.html</sparkle:releaseNotesLink>
    <pubDate>July 28, 2026 09:45:00 +0000</pubDate>
    <enclosure url="https://downloads.macbartender.com/B2/updates/6-6-1/Bartender%206.zip" type="application/octet-stream" sparkle:dsaSignature="MC0CFQCWObS0lX3ONTb9ZkfaiVG+uz0uAQIUME3CHU55jOV41mcZU4h3z+Xpgks=" sparkle:edSignature="8VQJNEkUouzDgN6SyfdUQFfUtcBU0KzQSjCDpMCBt3bRE2xQG1dkjoPeXlm+Lbl16Bg78LV6hcQqIFSRCPyKBw==" length="53799969" />
  </item>
<item>
    <title>Version 6.6.2</title>
    <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
    <sparkle:version>662000</sparkle:version>
    <sparkle:shortVersionString>6.6.2</sparkle:shortVersionString>
    <sparkle:releaseNotesLink>https://downloads.macbartender.com/B2/updates/6-6-2/rnotes.html</sparkle:releaseNotesLink>
    <pubDate>July 30, 2026 09:45:00 +0000</pubDate>
    <enclosure url="https://downloads.macbartender.com/B2/updates/6-6-2/Bartender%206.zip" type="application/octet-stream" sparkle:dsaSignature="MC0CFEfhnpYcpLoLhJO56xPyTPo25GQ/AhUAhcXE2u040kVd6/WQlpS1epw68D8=" sparkle:edSignature="s/mRrpiVL9iddOemfstjeHRBtCNFX+EcS5AQktA1jCJosbs9zcT1635bctnnmIzK556FK/n1Jt+9aEo6fGaKAQ==" length="53798566" />
  </item>
</channel>
</rss>
"""#

/// `https://downloads.macbartender.com/Bartender7/updates/7-0-5/rnotes.html`
/// as served (fetched 2026-10-10), the Cloudflare email-decode `<script>`
/// dropped: the 6.x template with one category heading.
private let bartender7PageFixture = #"""
<html>

<head>
  <meta http-equiv="content-type" content="text/html;charset=utf-8">
  <title>Release Notes</title>
  <meta name="robots" content="anchors">
  <link href="rnotes.css" type="text/css" rel="stylesheet" media="all">
</head>

<body>

  <table class="dots" width="100%" border="0" cellspacing="0" cellpadding="0" summary="Two column table with heading">
    <tr>
      <td class="blue" colspan="2">
        <h2>Bartender 7.0.5</h2>
      </td>
    </tr>
    <tr>
      <td valign="top" class="gap">
      <p>
        This update improves opening Notification Center while Bartender is hiding items, and makes refreshing menu bar item images less disruptive while you&#x27;re working.
      </p>
        <h3>Fixes</h3>
        <ul>
          <li>Fixed Fn+N not opening or closing Notification Center when menu bar items are hidden. This also supports custom Notification Center shortcuts configured in System Settings.</li>
          <li>Improved clicking the clock to open Notification Center, including shortly after launch or while Bartender is arranging your items.</li>
          <li>Reduced menu bar flickering when opening Notification Center.</li>
          <li>Prevent repeated attempts to refresh hidden-item images when they&#x27;re failing to capture. You can retry using “Recapture Items” on the Layout page.</li>
          <li>Improved menu bar image capture after moving or revealing items, and prevented stalled captures from holding up the refresh.</li>
          <li>Corrected the message shown when launching this build on an unsupported version of macOS to say it requires macOS 27 or later.</li>
        </ul>
        <p>
          If you face any issues with this update, or want to share a feature request, please reach out to us.
          <br>
          <a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="a1d2d4d1d1ced3d5e1ccc0c2c3c0d3d5c4cfc5c4d38fc2cecc">[email&#160;protected]</a>
        </p>
      </td>
    </tr>
  </table>


</body>

</html>
"""#

/// `…/Bartender7/updates/7-0-4/rnotes-stable.html` (fetched 2026-10-10), cut to
/// its body and to two of its thirteen "Fixes" items: the page the feed links
/// for 7.0.4, with a second section under a `section_heading`.
private let bartender7StablePageFixture = #"""
<body>

  <table class="dots" width="100%" border="0" cellspacing="0" cellpadding="0" summary="Two column table with heading">
    <tr>
      <td class="blue" colspan="2">
        <h2>Bartender 7.0.4</h2>
      </td>
    </tr>
    <tr>
      <td valign="top" class="gap">
      <p>
        This update fixes issues with items failing to appear, getting stuck while moving, or shifting around after a restart—especially spacers.
      </p>
        <h3>Fixes</h3>
        <ul>
          <li>Prevented delayed moves when an item is hidden by Control Center.</li>
          <li>Fixed the item mover getting stuck and never restarting.</li>
        </ul>
        <h3 class="section_heading">Clipboard improvements</h3>
        <ul>
          <li>Support keyboard selection with Up/Down and Enter.</li>
          <li>Added paste, copy, pin, unpin, and delete actions.</li>
        </ul>
        <p>
          If you face any issues with this update, or want to share a feature request, please reach out to us.
        </p>
      </td>
    </tr>
  </table>

</body>
"""#

/// The Bartender 7 appcast (fetched 2026-10-10), all four items, signatures
/// dropped. Ascending; 7.0.0's enclosure carries a `?revision=` query and
/// 7.0.4 links `rnotes-stable.html`.
private let bartender7AppcastFixture = #"""
<?xml version='1.0' encoding='utf-8'?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Bartender 7 Updates</title>
    <link>https://www.macbartender.com/Bartender7/</link>
    <description>Bartender 7 software updates</description>
    <language>en</language>
    <item>
      <title>Version 7.0.0</title>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:version>700007</sparkle:version>
      <sparkle:shortVersionString>7.0.0</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://downloads.macbartender.com/Bartender7/updates/7-0-0/rnotes.html</sparkle:releaseNotesLink>
      <pubDate>Mon, 14 Sep 2026 16:24:56 GMT</pubDate>
      <enclosure url="https://downloads.macbartender.com/Bartender7/updates/7-0-0/Bartender%207.zip?revision=86418c9bc7c93aac" type="application/octet-stream" length="59941985" />
    </item>
    <item>
      <title>Version 7.0.1</title>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:version>700008</sparkle:version>
      <sparkle:shortVersionString>7.0.1</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://downloads.macbartender.com/Bartender7/updates/7-0-1/rnotes.html</sparkle:releaseNotesLink>
      <pubDate>Mon, 14 Sep 2026 21:49:12 GMT</pubDate>
      <enclosure url="https://downloads.macbartender.com/Bartender7/updates/7-0-1/Bartender%207.zip" type="application/octet-stream" length="59941363" />
    </item>
    <item>
      <title>Version 7.0.4</title>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:version>700011</sparkle:version>
      <sparkle:shortVersionString>7.0.4</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://downloads.macbartender.com/Bartender7/updates/7-0-4/rnotes-stable.html</sparkle:releaseNotesLink>
      <pubDate>Mon, 21 Sep 2026 08:58:40 GMT</pubDate>
      <enclosure url="https://downloads.macbartender.com/Bartender7/updates/7-0-4/Bartender%207.zip" type="application/octet-stream" length="60515644" />
    </item>
    <item>
      <title>Version 7.0.5</title>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:version>700012</sparkle:version>
      <sparkle:shortVersionString>7.0.5</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://downloads.macbartender.com/Bartender7/updates/7-0-5/rnotes.html</sparkle:releaseNotesLink>
      <pubDate>Tue, 06 Oct 2026 11:26:05 GMT</pubDate>
      <enclosure url="https://downloads.macbartender.com/Bartender7/updates/7-0-5/Bartender%207.zip" type="application/octet-stream" length="60564183" />
    </item>
  </channel>
</rss>
"""#

/// A `feedPagePattern` recipe: the page is the one the Sparkle check resolved.
@Suite struct BartenderChangelogRecipeTests {
    /// The recipe the lookup picks for a version, the way the pane asks:
    /// Bartender 6 and 7 share the bundle id, and the version window decides.
    private func recipe(forVersion version: String = "6.6.2") throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.surteesstudios.Bartender", version: version))
    }

    private func recipe7() throws -> ChangelogRecipe { try recipe(forVersion: "7.0.5") }

    private func result(installed: String, latest: String, changelogURL: URL?) -> UpdateResult {
        let app = InstalledApp(
            name: "Bartender", bundleID: "com.surteesstudios.Bartender",
            shortVersion: installed, buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Bartender.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: latest, version: "2", downloadURL: nil,
            sourceName: "Sparkle", changelogURL: changelogURL)
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: latest))
    }

    /// Mutation: remove `headingPattern` — the five headings disappear.
    @Test func readsThePageWithItsHeadings() throws {
        let log = try #require(ChangelogExtractor.extract(from: bartenderPageFixture, using: try recipe()))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "6.5.2")
        #expect(entry.date == nil)
        #expect(entry.items.count == 5)
        #expect(entry.items[2]
            == "You can now enable Connection Alerts & Low Battery Alerts for your AIrpods in the Status Section of Top Shelf")
        #expect(Array(entry.content.prefix(3)) == [
            .heading("Bartender 6"), .heading("Fixes"),
            .note("Users on extremeley wide displays will no longer see artifacts in the menu bar"),
        ])
        #expect(!entry.items.contains { $0.contains("reach out to us") })
    }

    /// Mutation: remove the `<p>` item pattern — this page extracts nothing.
    @Test func aPageWithNoListFallsThroughToParagraphs() throws {
        let log = try #require(ChangelogExtractor.extract(from: bartenderProsePageFixture, using: try recipe()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "6.0.3")
        #expect(entry.items == ["We've resolved issues with the cursor feeling a little sluggish, or jumping whilst you move items."])
    }

    /// The newest item's link, as the production Sparkle parser picks it from
    /// the ascending feed.
    @Test func resolvesTheNewestItemsPage() throws {
        let link = SparkleAppcastSource.probeReleaseNotesLink(
            in: Data(bartenderAppcastFixture.utf8),
            feedURL: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            bundleID: "com.surteesstudios.Bartender")
        let expected = URL(string: "https://downloads.macbartender.com/B2/updates/6-6-2/rnotes.html")!
        #expect(link == expected)
        #expect(try recipe().acceptedFeedPage(link) == expected)
    }

    /// Both hosts the feed has linked are accepted. Mutation: drop the optional
    /// host prefix — the `downloads.` pages are refused.
    @Test func acceptsBothHostsTheFeedLinks() throws {
        let recipe = try recipe()
        for string in [
            "https://macbartender.com/B2/updates/6-0-0/rnotes.html",
            "https://downloads.macbartender.com/B2/updates/6-6-2/rnotes.html",
        ] {
            let url = URL(string: string)!
            #expect(recipe.acceptedFeedPage(url) == url, "\(string)")
        }
    }

    @Test func refusesEverythingElse() throws {
        let recipe = try recipe()
        for string in [
            "http://downloads.macbartender.com/B2/updates/6-6-2/rnotes.html",
            "https://downloads.macbartender.com/B2/updates/6-6-2/rnotes.html?x=1",
            "https://downloads.macbartender.com/B2/updates/AppcastB6.xml",
            "https://evil.example/macbartender.com/B2/updates/6-6-2/rnotes.html",
            "https://www.macbartender.com/Bartender6/release_notes/",
        ] {
            #expect(recipe.acceptedFeedPage(URL(string: string)!) == nil, "\(string)")
        }
        #expect(recipe.acceptedFeedPage(nil) == nil)
    }

    /// The probe's `changelogURL` is what the pane embeds when no recipe
    /// produces notes: the human release-notes page, never the appcast, and not
    /// a page this recipe would try to parse.
    @Test func theFallbackPageIsTheHumanReleaseNotes() throws {
        let probe = try #require(VendorProbeRegistry.recipes
            .first { $0.bundleID == "com.surteesstudios.Bartender" })
        let page = try #require(probe.changelogURL)
        #expect(page.absoluteString == "https://www.macbartender.com/Bartender6/release_notes/")
        #expect(try recipe().acceptedFeedPage(page) == nil)
    }

    // MARK: - Bartender 7

    /// Mutation: drop `minimumAppVersion`/`belowAppVersion` from both recipes —
    /// a 7.x lookup gets the 6.x recipe, the first in the group.
    @Test func theVersionWindowPicksTheTrain() throws {
        #expect(try recipe(forVersion: "6.6.2").source.absoluteString
            == "https://www.macbartender.com/B2/updates/AppcastB6.xml")
        #expect(try recipe(forVersion: "7.0.5").source.absoluteString
            == "https://downloads.macbartender.com/Bartender7/updates/AppcastB7.xml")
        #expect(try recipe(forVersion: "7.0.0").minimumAppVersion == "7")
    }

    /// The selection the pane makes, from the update result: each train's own
    /// feed page selects that train's recipe, and a page from the other train
    /// selects nothing, so the pane embeds that page instead of mis-parsing it.
    @Test func eachTrainsPageSelectsItsOwnRecipe() throws {
        let page6 = URL(string: "https://downloads.macbartender.com/B2/updates/6-6-2/rnotes.html")!
        let page7 = URL(string: "https://downloads.macbartender.com/Bartender7/updates/7-0-5/rnotes.html")!

        let six = result(installed: "6.6.1", latest: "6.6.2", changelogURL: page6)
        let sixRecipe = try #require(ChangelogRecipeSelection.recipe(for: six))
        #expect(sixRecipe.belowAppVersion == "7")
        #expect(ChangelogRecipeSelection.feedPage(for: six, recipe: sixRecipe) == page6)

        let seven = result(installed: "7.0.4", latest: "7.0.5", changelogURL: page7)
        let sevenRecipe = try #require(ChangelogRecipeSelection.recipe(for: seven))
        #expect(sevenRecipe.minimumAppVersion == "7")
        #expect(ChangelogRecipeSelection.feedPage(for: seven, recipe: sevenRecipe) == page7)

        #expect(ChangelogRecipeSelection.recipe(
            for: result(installed: "7.0.4", latest: "7.0.5", changelogURL: page6)) == nil)
        #expect(ChangelogRecipeSelection.recipe(
            for: result(installed: "6.6.1", latest: "6.6.2", changelogURL: page7)) == nil)
    }

    @Test func readsABartender7Page() throws {
        let log = try #require(ChangelogExtractor.extract(from: bartender7PageFixture, using: try recipe7()))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "7.0.5")
        #expect(entry.items.count == 6)
        #expect(entry.items[3]
            == "Prevent repeated attempts to refresh hidden-item images when they're failing to capture. You can retry using “Recapture Items” on the Layout page.")
        #expect(entry.content.first == .heading("Fixes"))
        #expect(!entry.items.contains { $0.contains("reach out to us") })
    }

    /// Mutation: remove `headingPattern` from the 7.x recipe — the second
    /// section's heading disappears.
    @Test func readsTheStableNotesPageWithBothSections() throws {
        let log = try #require(ChangelogExtractor.extract(from: bartender7StablePageFixture, using: try recipe7()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "7.0.4")
        #expect(entry.items.count == 4)
        #expect(entry.content == [
            .heading("Fixes"),
            .note("Prevented delayed moves when an item is hidden by Control Center."),
            .note("Fixed the item mover getting stuck and never restarting."),
            .heading("Clipboard improvements"),
            .note("Support keyboard selection with Up/Down and Enter."),
            .note("Added paste, copy, pin, unpin, and delete actions."),
        ])
    }

    /// Every link the 7.x feed carries is accepted, and the production Sparkle
    /// parser resolves the newest one from the ascending feed. Mutation: drop
    /// `(?:-stable)?` — 7.0.4's link is refused.
    @Test func acceptsEveryLinkTheBartender7FeedCarries() throws {
        let recipe = try recipe7()
        let links = [
            "https://downloads.macbartender.com/Bartender7/updates/7-0-0/rnotes.html",
            "https://downloads.macbartender.com/Bartender7/updates/7-0-1/rnotes.html",
            "https://downloads.macbartender.com/Bartender7/updates/7-0-4/rnotes-stable.html",
            "https://downloads.macbartender.com/Bartender7/updates/7-0-5/rnotes.html",
        ]
        for string in links {
            let url = URL(string: string)!
            #expect(recipe.acceptedFeedPage(url) == url, "\(string)")
        }
        let newest = SparkleAppcastSource.probeReleaseNotesLink(
            in: Data(bartender7AppcastFixture.utf8),
            feedURL: URL(string: "https://downloads.macbartender.com/Bartender7/updates/AppcastB7.xml")!,
            bundleID: "com.surteesstudios.Bartender")
        #expect(newest?.absoluteString == links.last)
    }

    @Test func theBartender7RecipeRefusesEverythingElse() throws {
        let recipe = try recipe7()
        for string in [
            "https://downloads.macbartender.com/B2/updates/6-6-2/rnotes.html",
            "https://downloads.macbartender.com/Bartender7/updates/6-6-2/rnotes.html",
            "https://downloads.macbartender.com/Bartender7/updates/7-0-5/rnotes-beta.html",
            "http://downloads.macbartender.com/Bartender7/updates/7-0-5/rnotes.html",
            "https://downloads.macbartender.com/Bartender7/updates/AppcastB7.xml",
            "https://www.macbartender.com/Bartender7/release_notes/",
        ] {
            #expect(recipe.acceptedFeedPage(URL(string: string)!) == nil, "\(string)")
        }
    }

    // MARK: - The Bartender 6 probe

    /// Bartender 7 is a paid upgrade under the same bundle id; the 6.x probe
    /// must not answer a 7.x install (nor a future 8.x). Checked through
    /// `VendorProbeSource`, which skips a recipe whose pattern refuses the
    /// installed version before fetching, so this needs no network. Mutation:
    /// drop `installedVersionPattern` — the 7.x install becomes a candidate
    /// and the source goes to the network.
    @Test func theBartender6ProbeIsPinnedToBartender6() async throws {
        let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == "com.surteesstudios.Bartender" }
        #expect(recipes.count == 1)
        let probe = try #require(recipes.first)
        #expect(probe.matchesInstalled(version: "6.6.2"))
        #expect(probe.matchesInstalled(version: "6.0.0"))
        #expect(!probe.matchesInstalled(version: "7.0.5"))
        #expect(!probe.matchesInstalled(version: "5.3.4"))

        let seven = InstalledApp(
            name: "Bartender 7", bundleID: "com.surteesstudios.Bartender",
            shortVersion: "7.0.5", buildVersion: "700012",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Bartender 7.app"),
            isMASApp: false, sparkleFeedURL: nil)
        #expect(try await VendorProbeSource(recipes: recipes).latestVersion(for: seven) == nil)
    }
}
