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

/// A `feedPagePattern` recipe: the page is the one the Sparkle check resolved.
@Suite struct BartenderChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes
            .first { $0.bundleID == "com.surteesstudios.Bartender" })
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

    /// The probe's `changelogURL` is the human release-notes page, not the
    /// appcast, and not a page this recipe would try to parse. It is used only
    /// if the probe itself answers; in production Sparkle answers first, and the
    /// pane falls back to that answer's per-version `rnotes.html` instead.
    @Test func theFallbackPageIsTheHumanReleaseNotes() throws {
        let probe = try #require(VendorProbeRegistry.recipes
            .first { $0.bundleID == "com.surteesstudios.Bartender" })
        let page = try #require(probe.changelogURL)
        #expect(page.absoluteString == "https://www.macbartender.com/Bartender6/release_notes/")
        #expect(try recipe().acceptedFeedPage(page) == nil)
    }
}
