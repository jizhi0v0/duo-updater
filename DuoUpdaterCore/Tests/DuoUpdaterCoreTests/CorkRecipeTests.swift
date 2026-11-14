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

/// The release header and original-post structure of the official NodeBB topic,
/// fetched 2026-11-14. Other paragraphs, author chrome and the reply are trimmed.
private let corkForumFixture = #"""
<span class="topic-title" component="topic/title">Cork 2.1.2 is Out: Just Some Legalities</span>
<li component="post" class="topic-owner-post" data-index="0" data-pid="21" data-uid="3">
<meta itemprop="datePublished" content="2026-11-02T19:50:03.626Z">
<div class="content text-break" component="post/content" itemprop="text">
<p dir="auto">Cork 2.1.2 is out, and it only includes some legalities.</p>
</div>
<div component="post/footer" class="post-footer"></div></li>
<li component="post" data-index="1"><div component="post/content"><p>Unrelated reply</p></div><div component="post/footer"></div></li>
"""#

private let corkForumIndexFixture = #"""
<h3 component="topic/header"><a href="/topic/20/download-endpoints-fixed">Download endpoints fixed</a></h3>
<h3 component="topic/header"><a href="/topic/21/cork-2.2.0-public-beta-is-out">Cork 2.2.0 Public Beta is out</a></h3>
<h3 component="topic/header"><a href="/topic/19/cork-2.1.2-is-out-just-some-legalities">Cork 2.1.2 is Out: Just Some Legalities</a></h3>
<h3 component="topic/header"><a href="/topic/18/cork-2.1.1-is-out-fixed-permissions">Cork 2.1.1 is Out</a></h3>
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

@Test func corkChangelogFollowsTheNewestCreatedReleaseTopic() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "eu.davidbures.cork"))
    #expect(URLComponents(url: recipe.source, resolvingAgainstBaseURL: false)?.queryItems
        == [URLQueryItem(name: "sort", value: "recently_created")])
    let pattern = try #require(recipe.indexLinkPattern)
    #expect(ChangelogService.firstLink(in: corkForumIndexFixture, pattern: pattern, base: recipe.source)?
        .absoluteString == "https://forum.rikidar.eu/topic/19/cork-2.1.2-is-out-just-some-legalities")
}

@Test func corkChangelogReadsOnlyTheReleaseAuthorsOriginalPost() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "eu.davidbures.cork"))
    let log = try #require(ChangelogExtractor.extract(from: corkForumFixture, using: recipe))
    #expect(log.entries.count == 1)
    #expect(log.entries[0].version == "2.1.2")
    #expect(log.entries[0].date == "2026-11-02")
    #expect(log.entries[0].items == ["Cork 2.1.2 is out, and it only includes some legalities."])

    // A missing original-post footer must fail closed, rather than use a reply's.
    let missingFooter = corkForumFixture.replacingOccurrences(
        of: "<div component=\"post/footer\" class=\"post-footer\"></div>", with: "")
    #expect(ChangelogExtractor.extract(from: missingFooter, using: recipe) == nil)
    let replyOnly = corkForumFixture.replacingOccurrences(of: "data-index=\"0\"", with: "data-index=\"2\"")
    #expect(ChangelogExtractor.extract(from: replyOnly, using: recipe) == nil)
}

@Test func corkChangelogKeepsParagraphsListsAndHeadingsTogether() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "eu.davidbures.cork"))
    let fixture = corkForumFixture.replacingOccurrences(
        of: "<p dir=\"auto\">Cork 2.1.2 is out, and it only includes some legalities.</p>",
        with: "<p>Overview &amp; details</p><h2>Fixes</h2><ul><li>First fix<ul><li>Nested fix</li></ul></li><li><p>Second fix</p></li></ul>")
    let entry = try #require(ChangelogExtractor.extract(from: fixture, using: recipe)?.entries.first)
    #expect(entry.items == ["Overview & details", "First fix", "Nested fix", "Second fix"])
    #expect(entry.content.contains(.heading("Fixes")))
}
