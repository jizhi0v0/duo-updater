import Foundation
import Testing

@testable import DuoUpdaterCore

/// `corkmac.app/releases.json`, fetched 2026-10-18. The rows that matter are
/// verbatim (the endpoint answers one line; line breaks added here); the other
/// 70-odd version rows are cut. Kept: two-part, three-part and four-part
/// versions, the string-sorted-last release before the newest, and the three
/// non-version names (`latest`, `macos-13`, `1.6.1+Sonoma`).
private let corkReleasesFixture = #"""
[{"name":"0.1.1","url":"https://corkmac.app/RLS/0.1.1/Cork.zip"},
{"name":"0.1.10","url":"https://corkmac.app/RLS/0.1.10/Cork.zip"},
{"name":"0.12","url":"https://corkmac.app/RLS/0.12/Cork.zip"},
{"name":"0.9","url":"https://corkmac.app/RLS/0.9/Cork.zip"},
{"name":"1.4","url":"https://corkmac.app/RLS/1.4/Cork.zip"},
{"name":"1.6.1+Sonoma","url":"https://corkmac.app/RLS/1.6.1+Sonoma/Cork.zip"},
{"name":"1.7.3.1","url":"https://corkmac.app/RLS/1.7.3.1/Cork.zip"},
{"name":"2.0.2","url":"https://corkmac.app/RLS/2.0.2/Cork.zip"},
{"name":"2.0.3","url":"https://corkmac.app/RLS/2.0.3/Cork.zip"},
{"name":"latest","url":"https://corkmac.app/RLS/latest/Cork.zip"},
{"name":"macos-13","url":"https://corkmac.app/RLS/macos-13/Cork.zip"}]
"""#

/// Three items of `blog.corkmac.app/feed`, fetched 2026-10-16: the 1.7.4 post
/// verbatim (the subscribe box included), a beta post cut after its title, and
/// the tail of the 2.0.1 post with the vendor's closing boilerplate.
private let corkFeedFixture = #"""
<rss><channel><item><title><![CDATA[Cork 2.0.0 Public Beta 3 is out!]]></title><description><![CDATA[Entering the home stretch.]]></description><pubDate>Tue, 14 Jul 2026 19:03:25 GMT</pubDate><content:encoded><![CDATA[<p>Beta notes</p>]]></content:encoded></item><item><title><![CDATA[Cork 2.0.1 is out: Processes don’t error out anymore]]></title><description><![CDATA[Cursed `depends_on` and `tap trust`]]></description><pubDate>Fri, 11 Sep 2026 18:29:24 GMT</pubDate><content:encoded><![CDATA[<h2>Fixes</h2><ul><li><p><code>tap trust</code> warnings incorrectly showing in the UI</p></li></ul><div><hr></div><h2>NO AI USED, EVER</h2><p>As always, no AI is used at any point in the development of Cork.</p><h2>Cork Community</h2><ul><li><p><a href="https://mstdn.social/@CorkApp">Cork on Mastodon</a></p></li></ul>]]></content:encoded></item><item><title><![CDATA[Cork 1.7.4 Out: Small fixes before the storm]]></title><description><![CDATA[The next update is really big.]]></description><link>https://blog.corkmac.app/p/cork-174-out-small-fixed-before-the</link><guid isPermaLink="false">https://blog.corkmac.app/p/cork-174-out-small-fixed-before-the</guid><dc:creator><![CDATA[David Bureš]]></dc:creator><pubDate>Tue, 31 Mar 2026 20:33:45 GMT</pubDate><enclosure url="https://substackcdn.com/image/fetch/$s_!Y8Zb!,w_256,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F8fa79553-ae95-43f2-ae3b-64169ed5afe3_1024x1024.png" length="0" type="image/jpeg"/><content:encoded><![CDATA[<p>The next update is <em>really </em>big. This one implements a few small fixes to get us there.</p><h2>Fixes:</h2><ul><li><p>Few incorrect associations for adoptable packages</p></li><li><p>Wrong packages listed in the &#8220;New updates available&#8220; notification</p></li><li><p>Some ignorable errors not getting ignored during package updating</p></li></ul><div class="subscription-widget-wrap-editor" data-attrs="{&quot;url&quot;:&quot;https://blog.corkmac.app/subscribe?&quot;,&quot;text&quot;:&quot;Subscribe&quot;,&quot;language&quot;:&quot;en&quot;}" data-component-name="SubscribeWidgetToDOM"><div class="subscription-widget show-subscribe"><div class="preamble"><p class="cta-caption">Thanks for reading Cork: The Ultimate Homebrew Companion! Subscribe for free to receive new posts and support my work.</p></div><form class="subscription-widget-subscribe"><input type="email" class="email-input" name="email" placeholder="Type your email&#8230;" tabindex="-1"><input type="submit" class="button primary" value="Subscribe"><div class="fake-input-wrapper"><div class="fake-input"></div><div class="fake-button"></div></div></form></div></div>]]></content:encoded></item></channel></rss>
"""#

private func corkProbe() throws -> VendorProbeRecipe {
    try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "eu.davidbures.cork" })
}

@Test func corkReadsTheHighestReleaseOnly() throws {
    let recipe = try corkProbe()
    #expect(recipe.url.absoluteString == "https://corkmac.app/releases.json")
    #expect(recipe.selectHighest)
    #expect(VendorProbeRecipe.highestVersion(
        from: corkReleasesFixture, pattern: recipe.versionPattern) == "2.0.3")
    // `latest`, `macos-13` and `1.6.1+Sonoma` never match.
    let regex = try NSRegularExpression(pattern: recipe.versionPattern)
    let range = NSRange(corkReleasesFixture.startIndex..., in: corkReleasesFixture)
    #expect(regex.numberOfMatches(in: corkReleasesFixture, range: range) == 8)
    // Sorted as strings: the first match is not the newest.
    #expect(VendorProbeRecipe.extractVersion(
        from: corkReleasesFixture, pattern: recipe.versionPattern) == "0.1.1")
}

@Test func corkInstallsTheResolvedVersionsZip() throws {
    let spec = try #require(try corkProbe().install)
    #expect(spec.kind == .zip)
    guard case .versionTemplate(let template) = spec.urlSource else {
        Issue.record("expected a version template"); return
    }
    #expect(template.replacingOccurrences(of: "{version}", with: "2.0.3")
        == "https://corkmac.app/RLS/2.0.3/Cork.zip")
}

@Test func corkOldIdsAreFiledUnderTheCurrentId() {
    #expect(BundleIDMigration.recipeBundleID(
        for: "com.davidbures.Cork", installedVersion: "1.4.4") == "eu.davidbures.cork")
    #expect(BundleIDMigration.recipeBundleID(
        for: "com.davidbures.cork", installedVersion: "1.5.7") == "eu.davidbures.cork")
    #expect(BundleIDMigration.migration(
        installed: "com.davidbures.cork", downloaded: "eu.davidbures.cork",
        installedVersion: "1.5.6", installedTeam: "ZSVA6DVZHM", downloadedTeam: "ZSVA6DVZHM") != nil)
    #expect(BundleIDMigration.migration(
        installed: "com.davidbures.cork", downloaded: "eu.davidbures.cork",
        installedVersion: "1.5.6", installedTeam: "ZSVA6DVZHM", downloadedTeam: "OTHERTEAM1") == nil)
}

@Test func corkChangelogReadsReleasePostsOnly() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "eu.davidbures.cork"))
    let log = try #require(ChangelogExtractor.extract(from: corkFeedFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["2.0.1", "1.7.4"])
    #expect(log.entries.map(\.date) == ["11 Sep 2026", "31 Mar 2026"])
    // The closing boilerplate is cut off.
    #expect(log.entries[0].items == ["tap trust warnings incorrectly showing in the UI"])
    // The subscribe box's caption is not an item; entities are decoded.
    #expect(log.entries[1].items == [
        "The next update is really big. This one implements a few small fixes to get us there.",
        "Few incorrect associations for adoptable packages",
        "Wrong packages listed in the \u{201C}New updates available\u{201C} notification",
        "Some ignorable errors not getting ignored during package updating",
    ])
}
