import Foundation
import Testing

@testable import DuoUpdaterCore

/// The macOS block of `krita.org/en/download/`, fetched 2026-10-16. Verbatim
/// except that the surrounding page is cut; the Windows portable link beside it
/// stays, because it shares the host and directory and must never be read.
private let kritaDownloadPageFixture = #"""
<div class=col-md-6><a href=https://download.kde.org/stable/krita/5.3.4.1/krita-x64-5.3.4.1.zip class=downloadable>Windows Portable</a></div><div class=col-md-6><a href=https://download.kde.org/stable/krita/5.3.4.1/krita-5.3.4.1-signed.dmg class=downloadable>macOS Installer</a>
"""#

/// Three items of `krita.org/en/index.xml`, fetched 2026-10-16: the 5.3.4/6.0.4
/// post (cut to two changes and the two macOS download sections), the
/// 5.3.2.1/6.0.2.1 hotfix post (no change list, only downloads) and a monthly
/// report that carries no release. Entity-escaped as the feed serves it,
/// including the double-escaped `&amp;quot;`.
private let kritaFeedFixture = #"""
<item><title>Monthly Report - October 2026</title><link>https://krita.org/en/posts/2026/monthly-update-34/</link><pubDate>Sat, 10 Oct 2026 00:00:00 +0000</pubDate><guid>https://krita.org/en/posts/2026/monthly-update-34/</guid><description>&lt;p&gt;Krita 5.3.4 and 6.0.4 are out.&lt;/p&gt;
&lt;ul&gt;
&lt;li&gt;Not a change of any release&lt;/li&gt;
&lt;/ul&gt;</description></item>
<item><title>Krita 5.3.4 Released!</title><link>https://krita.org/en/posts/2026/krita-5.3.4-released/</link><pubDate>Tue, 15 Sep 2026 00:00:00 +0000</pubDate><guid>https://krita.org/en/posts/2026/krita-5.3.4-released/</guid><description>
&lt;p&gt;Today we're releasing Krita 5.3.4 and 6.0.4, containing many bugfixes and improvements across the board.&lt;/p&gt;
&lt;h2 id="changelog"&gt;Changelog&lt;/h2&gt;
&lt;ul&gt;
&lt;li&gt;Fix writable resource path validator (&lt;a href="https://bugs.kde.org/show_bug.cgi?id=521186"&gt;Bug 521186&lt;/a&gt;)&lt;/li&gt;
&lt;li&gt;Fix a crash when &amp;quot;First Frame&amp;quot; shortcut is used when a file is closed&lt;/li&gt;
&lt;/ul&gt;
&lt;h2 id="download-534"&gt;Download 5.3.4&lt;/h2&gt;
&lt;h3 id="macos"&gt;MacOS&lt;/h3&gt;
&lt;ul&gt;
&lt;li&gt;MacOS disk image: &lt;a href="https://download.kde.org/stable/krita/5.3.4/krita-5.3.4-signed.dmg"&gt;krita-5.3.4-signed.dmg&lt;/a&gt;&lt;/li&gt;
&lt;/ul&gt;
&lt;h2 id="download-604"&gt;Download 6.0.4&lt;/h2&gt;
&lt;h3 id="macos-1"&gt;MacOS&lt;/h3&gt;
&lt;ul&gt;
&lt;li&gt;MacOS disk image: &lt;a href="https://download.kde.org/stable/krita/6.0.4/krita-6.0.4-signed.dmg"&gt;krita-6.0.4-signed.dmg&lt;/a&gt;&lt;/li&gt;
&lt;/ul&gt;</description></item>
<item><title>Krita 5.3.2.1 Released!</title><link>https://krita.org/en/posts/2026/krita-5.3.2.1-released/</link><pubDate>Tue, 02 Jun 2026 00:00:00 +0000</pubDate><guid>https://krita.org/en/posts/2026/krita-5.3.2.1-released/</guid><description>
&lt;p&gt;Hot on the heels of Krita 5.3.2, we're releasing Krita 5.3.2.1.&lt;/p&gt;
&lt;h2 id="download-5321"&gt;Download 5.3.2.1&lt;/h2&gt;
&lt;ul&gt;
&lt;li&gt;MacOS disk image: &lt;a href="https://download.kde.org/stable/krita/5.3.2.1/krita-5.3.2.1-signed.dmg"&gt;krita-5.3.2.1-signed.dmg&lt;/a&gt;&lt;/li&gt;
&lt;/ul&gt;
&lt;h2 id="download-6021"&gt;Download 6.0.2.1&lt;/h2&gt;
&lt;ul&gt;
&lt;li&gt;MacOS disk image: &lt;a href="https://download.kde.org/stable/krita/6.0.2.1/krita-6.0.2.1-signed.dmg"&gt;krita-6.0.2.1-signed.dmg&lt;/a&gt;&lt;/li&gt;
&lt;/ul&gt;</description></item>
"""#

private func kritaProbe(_ variant: String) throws -> VendorProbeRecipe {
    try #require(VendorProbeRegistry.recipes.first {
        $0.bundleID == "org.krita" && $0.variant == variant
    })
}

@Test func kritaRegistersOneStableProbePerLine() throws {
    let all = VendorProbeRegistry.recipes.filter { $0.bundleID == "org.krita" }
    #expect(all.count == 2)
    #expect(all.allSatisfy { $0.channel == .stable })
    let page = try kritaProbe("download-page")
    let six = try kritaProbe("krita6")
    // Each installed copy is served by exactly one of the two.
    for installed in ["4.4.8", "5.3.3", "5.3.4", "7.0.0"] {
        #expect(page.matchesInstalled(version: installed), "\(installed)")
        #expect(!six.matchesInstalled(version: installed), "\(installed)")
    }
    for installed in ["6.0.3", "6.0.4"] {
        #expect(!page.matchesInstalled(version: installed), "\(installed)")
        #expect(six.matchesInstalled(version: installed), "\(installed)")
    }
}

@Test func kritaDownloadPageReadsThreeComponentsAndInstallsTheHotfix() throws {
    let recipe = try kritaProbe("download-page")
    // The 5.3.4.1 bundle reports 5.3.4; reading four components would offer it forever.
    #expect(VendorProbeRecipe.extractVersion(
        from: kritaDownloadPageFixture, pattern: recipe.versionPattern) == "5.3.4")
    let spec = try #require(recipe.install)
    #expect(spec.kind == .dmg)
    guard case .bodyPattern(let pattern) = spec.urlSource else {
        Issue.record("Krita's install is no longer a body pattern")
        return
    }
    #expect(VendorProbeRecipe.extractVersion(from: kritaDownloadPageFixture, pattern: pattern)
        == "https://download.kde.org/stable/krita/5.3.4.1/krita-5.3.4.1-signed.dmg")
    // A three-component release reads as itself.
    #expect(VendorProbeRecipe.extractVersion(
        from: "https://download.kde.org/stable/krita/5.3.5/krita-5.3.5-signed.dmg",
        pattern: recipe.versionPattern) == "5.3.5")
    // A beta lives under unstable/ and is not a release.
    #expect(VendorProbeRecipe.extractVersion(
        from: "https://download.kde.org/unstable/krita/6.1.0-beta1/krita-6.1.0-beta1-signed.dmg",
        pattern: recipe.versionPattern) == nil)
}

@Test func kritaSixLineReadsTheHighestSixDmgInTheFeed() throws {
    let recipe = try kritaProbe("krita6")
    #expect(recipe.selectHighest)
    // 6.0.4 sorts above 6.0.2.1 and the 5.x links are the other line.
    #expect(VendorProbeRecipe.highestVersion(
        from: kritaFeedFixture, pattern: recipe.versionPattern) == "6.0.4")
    let spec = try #require(recipe.install)
    guard case .bodyPatternHighestVersioned(let pattern) = spec.urlSource else {
        Issue.record("Krita 6's install is no longer highest-versioned")
        return
    }
    #expect(VendorProbeRecipe.highestVersionedURL(from: kritaFeedFixture, pattern: pattern)
        == "https://download.kde.org/stable/krita/6.0.4/krita-6.0.4-signed.dmg")
    // Feed order does not decide it: the same links with the older post first.
    let reordered = kritaFeedFixture.components(separatedBy: "<item>").reversed()
        .joined(separator: "<item>")
    #expect(VendorProbeRecipe.highestVersionedURL(from: reordered, pattern: pattern)
        == "https://download.kde.org/stable/krita/6.0.4/krita-6.0.4-signed.dmg")
}

@Test func kritaChangelogGivesEachLineItsOwnNumbers() throws {
    let five = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.krita", version: "5.3.3"))
    let fiveLog = try #require(ChangelogExtractor.extract(from: kritaFeedFixture, using: five))
    // The monthly report and the hotfix post (no change list) give no entry.
    #expect(fiveLog.entries.map(\.version) == ["5.3.4"])
    let entry = try #require(fiveLog.entries.first)
    #expect(entry.date == "Tue, 15 Sep 2026 00:00:00 +0000")
    #expect(entry.items == [
        "Fix writable resource path validator (Bug 521186)",
        "Fix a crash when \"First Frame\" shortcut is used when a file is closed",
    ])

    let six = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.krita", version: "6.0.3"))
    #expect(six.minimumAppVersion == "6")
    let sixLog = try #require(ChangelogExtractor.extract(from: kritaFeedFixture, using: six))
    #expect(sixLog.entries.map(\.version) == ["6.0.4"])
    // Same post, same changes; the download links never become items.
    #expect(sixLog.entries.first?.items == entry.items)
}
