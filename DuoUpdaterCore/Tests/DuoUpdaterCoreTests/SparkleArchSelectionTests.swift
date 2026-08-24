import Testing
import Foundation
@testable import DuoUpdaterCore

/// Architecture-aware Sparkle appcast item selection. Mirrors
/// `ArchSelectionTests` (GitHub releases), but Sparkle vendors that publish
/// separate per-architecture builds do it as two `<item>`s carrying the SAME
/// version — a shape GitHub releases never has — so before this, `usableItems`
/// had no arch signal at all and tie-broke on the enclosure URL string, which
/// has nothing to do with which one this Mac can run.
struct SparkleArchSelectionTests {

    private func app() -> InstalledApp {
        InstalledApp(
            name: "TablePro", bundleID: "app.tablepro.TablePro",
            shortVersion: "0.66.0", buildVersion: "110",
            path: URL(fileURLWithPath: "/Applications/TablePro.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))
    }

    /// TablePro's real 0.67.1 item pair, fetched 2026-08-24 from
    /// raw.githubusercontent.com/TableProApp/TablePro/main/appcast.xml
    /// (description bodies trimmed; everything else verbatim, including the
    /// arm64 item appearing first in document order and carrying the only
    /// `sparkle:hardwareRequirements` tag of the pair). `reversed` swaps the
    /// item order in the feed, so a test can prove selection depends on
    /// architecture, not on which item the vendor happened to list first.
    private func tableProPair(reversed: Bool = false) -> [SparkleAppcastItem] {
        let arm64Item = """
        <item>
          <title>0.67.1</title>
          <pubDate>Sat, 22 Aug 2026 10:44:28 +0000</pubDate>
          <sparkle:version>122</sparkle:version>
          <sparkle:shortVersionString>0.67.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
          <enclosure url="https://github.com/TableProApp/TablePro/releases/download/v0.67.1/TablePro-0.67.1-arm64.zip"
                     length="24418655" type="application/octet-stream" sparkle:edSignature="arm-sig"/>
        </item>
        """
        let x86Item = """
        <item>
          <title>0.67.1</title>
          <pubDate>Sat, 22 Aug 2026 10:44:29 +0000</pubDate>
          <sparkle:version>122</sparkle:version>
          <sparkle:shortVersionString>0.67.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/TableProApp/TablePro/releases/download/v0.67.1/TablePro-0.67.1-x86_64.zip"
                     length="25966268" type="application/octet-stream" sparkle:edSignature="x86-sig"/>
        </item>
        """
        let body = reversed ? [x86Item, arm64Item] : [arm64Item, x86Item]
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel>\(body.joined())</channel>
        </rss>
        """
        return SparkleAppcastParser.parse(Data(xml.utf8))
    }

    // MARK: - Real TablePro feed shape

    @Test func parserReadsHardwareRequirements() {
        let items = tableProPair()
        let arm = items.first { $0.enclosureURL?.lastPathComponent.contains("arm64") == true }
        let x86 = items.first { $0.enclosureURL?.lastPathComponent.contains("x86_64") == true }
        #expect(arm?.hardwareRequirements == ["arm64"])
        #expect(x86?.hardwareRequirements == [])
    }

    @Test func arm64HostGetsTheArm64BuildRegardlessOfFeedOrder() {
        for reversed in [false, true] {
            let best = SparkleAppcastSource.bestItem(
                for: app(), from: tableProPair(reversed: reversed), osVersion: "26.6.0",
                hostArch: .arm64, allowingIntelTranslation: true)
            #expect(best?.enclosureURL?.lastPathComponent == "TablePro-0.67.1-arm64.zip")
        }
    }

    @Test func intelHostGetsTheX86BuildAndNeverTheArm64OneEvenListedFirst() {
        let best = SparkleAppcastSource.bestItem(
            for: app(), from: tableProPair(), osVersion: "14.6.0",
            hostArch: .x86_64, allowingIntelTranslation: false)
        #expect(best?.enclosureURL?.lastPathComponent == "TablePro-0.67.1-x86_64.zip")
    }

    @Test func intelHostNeverOffersTheArm64TaggedItemEvenIfItWereTheOnlyOne() {
        // Isolate the arm64 item only — an Intel Mac can never run it (no
        // reverse Rosetta), so this must resolve to "nothing usable", not a
        // fallback pick of an item this host can't run.
        let armOnly = tableProPair().filter { $0.hardwareRequirements.contains("arm64") }
        let usable = SparkleAppcastSource.usableItems(
            for: app(), from: armOnly, osVersion: "14.6.0",
            hostArch: .x86_64, allowingIntelTranslation: false)
        #expect(usable.isEmpty)
    }

    @Test func structuredArmRequirementWinsOverProductNameTokens() {
        var item = tableProPair().first {
            $0.hardwareRequirements.contains("arm64")
        }!
        // `intel` is a supported Intel marker, but here it is embedded inside
        // the product name rather than standing alone as an architecture marker.
        item.enclosureURL = URL(string: "https://example.com/IntelliJ-0.67.1-arm64.zip")
        let usable = SparkleAppcastSource.usableItems(
            for: app(), from: [item], osVersion: "28.0.0",
            hostArch: .arm64, allowingIntelTranslation: false)
        #expect(usable.count == 1)
    }

    // MARK: - Filename-token fallback (no hardwareRequirements tag at all)
    //
    // Most Sparkle vendors don't use the tag; some still ship a genuine
    // per-arch pair named only by filename (the same shape GitHubReleaseRule
    // already handles for GitHub releases).

    private func untaggedPair(hostToken: String, otherToken: String) -> [SparkleAppcastItem] {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel>
          <item><sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
            <enclosure url="https://example.com/app-2.0-\(otherToken).dmg" sparkle:edSignature="s" length="1" type="application/octet-stream"/></item>
          <item><sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
            <enclosure url="https://example.com/app-2.0-\(hostToken).dmg" sparkle:edSignature="s" length="1" type="application/octet-stream"/></item>
        </channel>
        </rss>
        """
        return SparkleAppcastParser.parse(Data(xml.utf8))
    }

    @Test func untaggedNativeFilenameWinsOverForeignOnArm64() {
        let items = untaggedPair(hostToken: "arm64", otherToken: "x86_64")
        let best = SparkleAppcastSource.bestItem(
            for: app(), from: items, osVersion: "26.6.0", hostArch: .arm64, allowingIntelTranslation: true)
        #expect(best?.enclosureURL?.lastPathComponent == "app-2.0-arm64.dmg")
    }

    @Test func untaggedNativeFilenameWinsOverForeignOnIntel() {
        let items = untaggedPair(hostToken: "x86_64", otherToken: "arm64")
        let best = SparkleAppcastSource.bestItem(
            for: app(), from: items, osVersion: "14.6.0", hostArch: .x86_64, allowingIntelTranslation: false)
        #expect(best?.enclosureURL?.lastPathComponent == "app-2.0-x86_64.dmg")
    }

    @Test func untaggedForeignOnlyIsOfferedOnArm64WhileRosettaStillCoversIt() {
        // No arm64 item exists at all this version — only x86_64, no tag. Still
        // installable via Rosetta translation, so it must not be dropped.
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel><item><sparkle:version>3</sparkle:version><sparkle:shortVersionString>3.0</sparkle:shortVersionString>
          <enclosure url="https://example.com/app-3.0-x86_64.dmg" sparkle:edSignature="s" length="1" type="application/octet-stream"/></item></channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(xml.utf8))
        let best = SparkleAppcastSource.bestItem(
            for: app(), from: items, osVersion: "26.6.0", hostArch: .arm64, allowingIntelTranslation: true)
        #expect(best != nil)
    }

    @Test func untaggedForeignOnlyIsDroppedOnArm64OnceRosettaIsGone() {
        // Same feed as above, but macOS 28+ / no Rosetta: nothing this Mac can
        // run, so it must resolve to "no update", not a doomed download.
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel><item><sparkle:version>3</sparkle:version><sparkle:shortVersionString>3.0</sparkle:shortVersionString>
          <enclosure url="https://example.com/app-3.0-x86_64.dmg" sparkle:edSignature="s" length="1" type="application/octet-stream"/></item></channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(xml.utf8))
        let usable = SparkleAppcastSource.usableItems(
            for: app(), from: items, osVersion: "28.0.0", hostArch: .arm64, allowingIntelTranslation: false)
        #expect(usable.isEmpty)
    }

    @Test func neutralFilenameIsUnaffectedByArchSelection() {
        // The overwhelming majority of feeds: a single universal build, no arch
        // marker in the name at all. Must keep working exactly as before.
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel><item><sparkle:version>1</sparkle:version><sparkle:shortVersionString>1.0</sparkle:shortVersionString>
          <enclosure url="https://example.com/App.zip" sparkle:edSignature="s" length="1" type="application/octet-stream"/></item></channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(xml.utf8))
        for arch: HostArch in [.arm64, .x86_64] {
            let best = SparkleAppcastSource.bestItem(
                for: app(), from: items, osVersion: "14.0.0", hostArch: arch, allowingIntelTranslation: false)
            #expect(best?.enclosureURL?.lastPathComponent == "App.zip")
        }
    }

    @Test func explicitDualArchitectureFilenameIsUniversal() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel><item><sparkle:version>4</sparkle:version><sparkle:shortVersionString>4.0</sparkle:shortVersionString>
          <enclosure url="https://example.com/App-4.0-arm64-x86_64.zip" sparkle:edSignature="s" length="1" type="application/octet-stream"/></item></channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(xml.utf8))
        for arch: HostArch in [.arm64, .x86_64] {
            let best = SparkleAppcastSource.bestItem(
                for: app(), from: items, osVersion: "14.0.0",
                hostArch: arch, allowingIntelTranslation: false)
            #expect(best?.enclosureURL?.lastPathComponent == "App-4.0-arm64-x86_64.zip")
        }
    }
}
