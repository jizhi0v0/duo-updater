import Foundation
import Testing

@testable import DuoUpdaterCore

/// CleanMyMac 5: the vendor appcast at `updates.cleanmymac.com` and the
/// `macpaw.com/cleanmymac/whats-new` changelog.
///
/// The feed fixture is the 2026-11-01 response, cut to its first two items (the
/// 5.7.3 release and the `.delta` block under it). The page fixture is the same
/// day's `/cleanmymac/whats-new`, cut to the 5.7.2 and 5.7.1 blocks: a feature
/// release with bullets and a bug-fix release with none, which is why the recipe
/// carries a paragraph fallback.
private let cleanMyMacFeedFixture = #"""
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>CleanMyMac_5</title>
        <item>
            <title>5.7.3</title>
            <pubDate>Thu, 29 Oct 2026 15:45:26 +0000</pubDate>
            <sparkle:version>50703.0.2610281229</sparkle:version>
            <sparkle:shortVersionString>5.7.3</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
            <enclosure url="https://updates.cleanmymac.com/com.macpaw.cleanmymac5/releases/CleanMyMac5_50703.0.2610281229.zip" length="222341604" type="application/octet-stream" sparkle:edSignature="6tkbr6Jw8fBg6FxYo4WjSw7gLiv/HNKSiQHeyHqt3rZHadOTi36VsJZnErr5m9Iu5M+M8L7QuP76KOo7BeLvAQ=="/>
            <sparkle:deltas>
                <enclosure url="https://updates.cleanmymac.com/com.macpaw.cleanmymac5/deltas/50703.0.2610281229/CleanMyMac_550703.0.2610281229-50702.0.2610141002.delta" sparkle:deltaFrom="50702.0.2610141002" length="5515510" type="application/octet-stream" sparkle:edSignature="8IHkuJjJydYdAoKPif2GCPUqtjKAiDFzBxQ6RxfMnI9nCvlYFLe+s7miOt/CY5GyLcm1kMuaG+YNsLY6w+2pBQ=="/>
            </sparkle:deltas>
        </item>
        <item>
            <title>5.7.2</title>
            <pubDate>Thu, 15 Oct 2026 09:00:00 +0000</pubDate>
            <sparkle:version>50702.0.2610141002</sparkle:version>
            <sparkle:shortVersionString>5.7.2</sparkle:shortVersionString>
            <enclosure url="https://updates.cleanmymac.com/com.macpaw.cleanmymac5/releases/CleanMyMac5_50702.0.2610141002.zip" length="222000000" type="application/octet-stream"/>
        </item>
    </channel>
</rss>
"""#

/// `macpaw.com/cleanmymac/whats-new`, 2026-11-01, two blocks verbatim except for
/// elided `<img>` attributes and the second release's second summary.
private let cleanMyMacChangelogFixture = #"""
<section class="versions -active" data-section="releases">
<div class="versions-list" data-accordion="whats-new">
<div class="versions-item   -active " data-versions-item data-accordion-block>
<div class="versions-item__wrap">
<div class="versions-item__info">
<h2 class="version">Update 5.7.2</h2>
<span class="date"><span class="pre-date">&#8197;&#8197;/ </span>October 15, 2026</span>
</div>
<div class="versions-item__description">
<p>Your browser just got a new companion. Browser Care is a Chrome extension that helps you manage tabs and keep Chrome running smoothly.</p>
</div>
<button class="versions-item__button" data-accordion-trigger type="button">View details</button>
</div>
<div class="versions-item__wrap" data-accordion-content>
<div class="versions-item__content">
<div class="versions-item__summary">
<div class="versions-item__list">
<h3 class="label">New</h3>
<p>Browser Care keeps your browser under control, right from the toolbar:</p>
<ul><li>See which tabs use the most memory and CPU and take action on the ones slowing you down.</li><li>Find and close duplicate tabs across all your windows.</li><li>Clean up tabs you've had open for too long and no longer need.</li></ul>
</div>
</div>
</div>
</div>
</div>
<div class="versions-item  " data-versions-item data-accordion-block>
<div class="versions-item__wrap">
<div class="versions-item__info">
<h2 class="version">Update 5.7.1</h2>
<span class="date"><span class="pre-date">&#8197;&#8197;/ </span>October 01, 2026</span>
</div>
<div class="versions-item__description">
<p>CleanMyMac now helps you care for the outside of your Mac, too, with the new Screen Cleaning Mode.</p>
</div>
<button class="versions-item__button" data-accordion-trigger type="button">View details</button>
</div>
<div class="versions-item__wrap" data-accordion-content>
<div class="versions-item__content">
<div class="versions-item__summary">
<div class="versions-item__list">
<h3 class="label">New</h3>
<p>Screen Cleaning Mode</p>
<p>Temporarily locks your keyboard and trackpad while you wipe the screen.</p>
</div>
</div>
</div>
</div>
</div>
</div>
</section>
"""#

@Test func theProbeReadsTheMarketingVersionAndTheReleaseZip() throws {
    let probes = VendorProbeRegistry.recipes.filter { $0.bundleID == "com.macpaw.CleanMyMac5" }
    let probe = try #require(probes.count == 1 ? probes[0] : nil)
    #expect(probe.url.absoluteString
        == "https://updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml")
    #expect(!probe.versionIsBuild)
    #expect(VendorProbeRecipe.extractVersion(
        from: cleanMyMacFeedFixture, pattern: probe.versionPattern) == "5.7.3")

    guard case .bodyPattern(let pattern)? = probe.install?.urlSource else {
        Issue.record("expected a .bodyPattern install")
        return
    }
    // The first enclosure is the release zip; the `.delta` under `<sparkle:deltas>`
    // must not be reachable through the `/releases/…zip` anchor.
    #expect(VendorProbeRecipe.extractVersion(from: cleanMyMacFeedFixture, pattern: pattern)
        == "https://updates.cleanmymac.com/com.macpaw.cleanmymac5/releases/CleanMyMac5_50703.0.2610281229.zip")
}

@Test func theChangelogReadsVersionsDatesAndBullets() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.macpaw.CleanMyMac5"))
    let log = try #require(ChangelogExtractor.extract(from: cleanMyMacChangelogFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["5.7.2", "5.7.1"])
    #expect(log.entries.map(\.date) == ["October 15, 2026", "October 01, 2026"])
    #expect(log.entries[0].items == [
        "See which tabs use the most memory and CPU and take action on the ones slowing you down.",
        "Find and close duplicate tabs across all your windows.",
        "Clean up tabs you've had open for too long and no longer need.",
    ])
    // No `<li>` in this release: the paragraph fallback still gives it notes
    // instead of leaving it out of the list entirely.
    #expect(log.entries[1].items.first
        == "CleanMyMac now helps you care for the outside of your Mac, too, with the new Screen Cleaning Mode.")
    #expect(log.entries[1].items.contains("Screen Cleaning Mode"))
}
