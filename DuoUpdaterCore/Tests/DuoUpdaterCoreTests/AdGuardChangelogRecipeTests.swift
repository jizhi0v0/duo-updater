import Testing
import Foundation
@testable import DuoUpdaterCore

/// `adguard.com/en/adguard-for-mac/versions.html?channel=release`, captured
/// 2026-10-16: the 2.17.3 entry verbatim, then 2.17 cut to its intro, one
/// section with both screenshots, and two lines of its changelog. Ends with the
/// page's trailing `<style>`, where the last body stops.
private let releasePageFixture = #"""
<!doctype html><html>
<head>
    <meta charset="UTF-8">
    <title>macOS versions</title>
</head>
    <body class="light">
            <div class="version">
            <div class="feed" v-pre>
                    <div class="feed__item" id="version-21732020">
                <div class="feed__header">


                                            <div class="feed__title">
                                                            AdGuard for Mac 2.17.3
                                                    </div>

                    <div class="feed__release">
                        <div class="md__paragraph">Release date: August 6, 2025</div>
                    </div>
                </div>
                <div class="feed__version">
                    <div class="feed__version-desc">
                                                    <div class="md__paragraph">Have you ever noticed how the app crashes even when you have a freshly updated version? Well, notice no more! This hotfix solves that problem. From now on, just pure ad blocking all the way.</div>
                                            </div>
                </div>
            </div>
                    <div class="feed__item" id="version-21701981">
                <div class="feed__header">


                                            <div class="feed__title">
                                                            AdGuard for Mac 2.17
                                                    </div>

                    <div class="feed__release">
                        <div class="md__paragraph">Release date: June 16, 2025</div>
                    </div>
                </div>
                <div class="feed__version">
                    <div class="feed__version-desc">
                                                    <div class="md__paragraph">In this release, we&rsquo;ve made AdGuard more helpful by updating interactive blocking pages and stronger by adding post-quantum encryption &mdash; it&rsquo;s a win-win.</div>
<h2 class="md__title md__title_second">New blocking pages</h2>
<div class="md__paragraph">&ldquo;Access blocked&rdquo;: You may have already seen one of these screens if you&rsquo;ve visited a phishing website or if a rule restricted access to a website. If you haven&rsquo;t seen it yet, now is the time to get familiar with it and see what you can do on these screens. </div>
<div class="md__paragraph"><img class="md__img" src="https://cdn.adtidy.org/content/release_notes/ad_blocker/windows/v7.20/malicious_website_en.jpg" alt="Dangerous website *border" rel="nofollow"></div>
<div class="md__paragraph">A website blocked by a filtering rule? Just click <span class="md__em">Add this website to the allowlist</span> and an unblocking rule will be generated automatically and added to <span class="md__em">User rules</span>.</div>
<div class="md__paragraph"><img class="md__img" src="https://cdn.adtidy.org/content/release_notes/ad_blocker/windows/v7.20/blocked_by_userrule.jpg" alt="Website blocked by a rule *border" rel="nofollow"></div>
<h3 class="md__title md__title_third">Fixes</h3>
<div class="md__list">
<div class="md__list-elem">Browser assistant state isn&rsquo;t updated after AdGuard uninstallation <a class="link md__link" rel="nofollow" href="https://github.com/AdguardTeam/AdguardForMac/issues/1659">#1659</a></div>
<div class="md__list-elem">The <span class="md__em">Block Java</span> message is triggering Cloudflare DDoS protection <a class="link md__link" rel="nofollow" href="https://github.com/AdguardTeam/AdguardForMac/issues/1694">#1694</a></div>
</div>
                                            </div>
                </div>
            </div>
                </div>
        </div>
        <style>
        .feed__item:last-child {
            border-bottom: 0;
        }
    </style>
    </body>
</html>
"""#

/// The beta page's 2.16 RC entry, captured 2026-10-16 and cut to its first
/// lines: a suffix with no number after it, and an `<h1>` section title.
private let betaPageFixture = #"""
<div class="feed__item" id="version-21601856">
                <div class="feed__header">


                                            <div class="feed__title">
                                                            AdGuard for Mac 2.16 RC
                                                    </div>

                    <div class="feed__release">
                        <div class="md__paragraph">Release date: December 9, 2024</div>
                    </div>
                </div>
                <div class="feed__version">
                    <div class="feed__version-desc">
                                                    <div class="md__paragraph">The differential filters update is now available in AdGuard for Mac.</div>
<h1 class="md__title md__title_first">Changelog</h1>
<h3 class="md__title md__title_third">Improvements</h3>
<div class="md__list">
<div class="md__list-elem">Added differential filters update</div>
</div>
                                            </div>
                </div>
            </div>
</body>
"""#

/// The nightly page's newest entry, captured 2026-10-16: the title is the
/// four-part build, and the notes are one line.
private let nightlyPageFixture = #"""
<div class="feed__item" id="version-22002625">
                <div class="feed__header">


                                            <div class="feed__title">
                                                            AdGuard for Mac 2.20.0.2625
                                                    </div>

                    <div class="feed__release">
                        <div class="md__paragraph">Release date: October 8, 2026</div>
                    </div>
                </div>
                <div class="feed__version">
                    <div class="feed__version-desc">
                                                    <div class="md__list">
<div class="md__list-elem">[Fixed] Pull updated `ssl_exclusions.json` into the app #1795</div>
</div>
                                            </div>
                </div>
            </div>
</body>
"""#

/// The zh_cn release page's header, captured 2026-10-16: the redirect follows
/// Accept-Language, so the product words and the date label are translated
/// (full-width colon).
private let chinesePageFixture = #"""
<div class="feed__item" id="version-22002626">
                <div class="feed__header">


                                            <div class="feed__title">
                                                            AdGuard Mac版 2.20
                                                    </div>

                    <div class="feed__release">
                        <div class="md__paragraph">更新日期：2026年10月14日</div>
                    </div>
                </div>
                <div class="feed__version">
                    <div class="feed__version-desc">
                                                    <div class="md__paragraph">在 AdGuard Mac 版 v2.20 中，我们焕新了应用的视觉风格。</div>
                                            </div>
                </div>
            </div>
</body>
"""#

/// The release appcast, captured 2026-10-16 (one item; the signature cut).
private let appcastFixture = #"""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>AdGuard for Mac Updates</title>
    <item>
      <title>Version 2.20</title>
      <pubDate>Fri, 09 Oct 2026 08:52:18 +0000</pubDate>
      <sparkle:version>2626</sparkle:version>
      <sparkle:shortVersionString>2.20</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>12.7.6</sparkle:minimumSystemVersion>
      <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>
      <sparkle:releaseNotesLink><![CDATA[https://link.adtidy.org/forward.html?app=mac&action=update_release_notes&from=updater&channel=release]]></sparkle:releaseNotesLink>
      <enclosure url="https://static.adtidy.org/mac/release/AdGuard-2.20.0.2626.dmg" type="application/octet-stream" sparkle:edSignature="sig" length="112485149" sparkle:installationType="package"></enclosure>
    </item>
  </channel>
</rss>
"""#

private let linkBase =
    "https://link.adtidy.org/forward.html?app=mac&action=update_release_notes&from=updater&channel="

@Suite struct AdGuardChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes
            .first { $0.bundleID == "com.adguard.mac.adguard" })
    }

    // MARK: - The page

    @Test func readsEveryEntryWithItsDate() throws {
        let log = try #require(ChangelogExtractor.extract(from: releasePageFixture, using: try recipe()))
        #expect(log.entries.map(\.version) == ["2.17.3", "2.17"])
        #expect(log.entries.map(\.date) == ["August 6, 2025", "June 16, 2025"])
        #expect(log.entries.first?.items.count == 1)
    }

    /// Mutation: drop `imagePattern` — `content` loses both images; drop
    /// `headingPattern` — it loses both headings. An image paragraph is no line.
    @Test func keepsScreenshotsAndHeadingsInPlace() throws {
        let log = try #require(ChangelogExtractor.extract(from: releasePageFixture, using: try recipe()))
        let entry = try #require(log.entries.last)
        #expect(entry.items.count == 5)
        #expect(entry.items.first == "In this release, we’ve made AdGuard more helpful by updating interactive blocking pages and stronger by adding post-quantum encryption — it’s a win-win.")
        #expect(entry.items.contains("The Block Java message is triggering Cloudflare DDoS protection #1694"))
        let shape: [String] = entry.content.map {
            switch $0 {
            case .note: "note"
            case .image: "image"
            case .heading(let text): "heading:\(text)"
            }
        }
        #expect(shape == [
            "note", "heading:New blocking pages", "note", "image", "note", "image",
            "heading:Fixes", "note", "note",
        ])
        #expect(entry.content.contains(.image(URL(string:
            "https://cdn.adtidy.org/content/release_notes/ad_blocker/windows/v7.20/blocked_by_userrule.jpg")!)))
    }

    /// Mutation: require a number after the suffix word — "2.16 RC" is dropped.
    @Test func aBetaSuffixNeedNotCarryANumber() throws {
        let log = try #require(ChangelogExtractor.extract(from: betaPageFixture, using: try recipe()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "2.16 RC")
        #expect(entry.content.filter { if case .heading = $0 { true } else { false } }.count == 2)
    }

    @Test func aNightlyEntryIsItsBuild() throws {
        let log = try #require(ChangelogExtractor.extract(from: nightlyPageFixture, using: try recipe()))
        #expect(log.entries.first?.version == "2.20.0.2625")
        #expect(log.entries.first?.items == ["[Fixed] Pull updated `ssl_exclusions.json` into the app #1795"])
    }

    /// Mutation: anchor the title on "AdGuard for Mac", or the date label on an
    /// ASCII colon — the translated page loses its entry or its date.
    @Test func aTranslatedPageKeepsVersionAndDate() throws {
        let log = try #require(ChangelogExtractor.extract(from: chinesePageFixture, using: try recipe()))
        #expect(log.entries.first?.version == "2.20")
        #expect(log.entries.first?.date == "2026年10月14日")
    }

    // MARK: - Which page

    @Test func acceptsEachTracksLink() throws {
        let recipe = try recipe()
        for track in ["release", "beta", "nightly"] {
            let url = URL(string: linkBase + track)!
            #expect(recipe.acceptedFeedPage(url) == url, "\(url)")
        }
    }

    @Test func refusesOtherLinks() throws {
        let recipe = try recipe()
        for string in [
            linkBase + "alpha",
            linkBase + "release&extra=1",
            "https://link.adtidy.org/forward.html?app=windows&action=update_release_notes&from=updater&channel=release",
            "http://link.adtidy.org/forward.html?app=mac&action=update_release_notes&from=updater&channel=release",
            "https://adguard.com/en/adguard-for-mac/versions.html?channel=release",
        ] {
            #expect(recipe.acceptedFeedPage(URL(string: string)!) == nil, "\(string)")
        }
    }

    /// What `duo verify` fetches with no update result in hand.
    @Test func verifyResolvesTheReleaseLinkFromTheAppcast() throws {
        let recipe = try recipe()
        let link = try #require(SparkleAppcastSource.probeReleaseNotesLink(
            in: Data(appcastFixture.utf8), feedURL: recipe.source, bundleID: recipe.bundleID))
        #expect(link == URL(string: linkBase + "release")!)
        #expect(recipe.acceptedFeedPage(link) == link)
    }
}
