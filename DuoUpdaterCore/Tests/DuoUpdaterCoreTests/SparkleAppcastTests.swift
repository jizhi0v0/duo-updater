import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func deltaEnclosuresDontHijackTheItemsDownload() {
    // Sparkle nests incremental patches in <sparkle:deltas>, using the SAME
    // <enclosure> tag as the real download. Treating them alike left each item
    // holding the last delta it saw — so `deltaFrom` was set on every item, the
    // delta filter dropped them all, and the source returned nil. Rectangle and
    // Keka were both invisible this way, reported as "no source applied" with no
    // error to explain it.
    let xml = """
    <?xml version="1.0" standalone="yes"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
      <item>
        <title>0.98</title>
        <pubDate>Wed, 15 Jul 2026 09:17:03 -0400</pubDate>
        <sparkle:version>104</sparkle:version>
        <sparkle:shortVersionString>0.98</sparkle:shortVersionString>
        <enclosure url="https://example.com/Rectangle0.98.dmg" length="4262228"
                   type="application/octet-stream" sparkle:edSignature="sig"/>
        <sparkle:deltas>
          <enclosure url="https://example.com/Rectangle104-103.delta" length="111"
                     sparkle:deltaFrom="103" type="application/octet-stream"/>
          <enclosure url="https://example.com/Rectangle104-99.delta" length="222"
                     sparkle:deltaFrom="99" type="application/octet-stream"/>
        </sparkle:deltas>
      </item>
    </channel>
    </rss>
    """
    let items = SparkleAppcastParser.parse(Data(xml.utf8))
    #expect(items.count == 1)
    let item = try! #require(items.first)
    #expect(item.deltaFrom == nil)
    #expect(item.enclosureURL?.lastPathComponent == "Rectangle0.98.dmg")
    #expect(item.enclosureLength == 4262228)  // not a delta's size
    #expect(item.edSignature == "sig")

    // And the item survives the filter that the deltas used to trip.
    let app = InstalledApp(
        name: "Rectangle", bundleID: "com.knollsoft.Rectangle", shortVersion: "0.96",
        buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Rectangle.app"),
        isMASApp: false, sparkleFeedURL: URL(string: "https://example.com/updates.xml"))
    let usable = SparkleAppcastSource.usableItems(for: app, from: items, osVersion: "26.6.0")
    #expect(usable.count == 1)
}

/// The other half of the rule above: the patches are skipped as the item's
/// download AND kept as patches. Verbatim from Keka's real appcast, fetched
/// 2026-08-23 — eight deltas against a 32.9 MB archive, the smallest of them
/// 519 KB for the immediately-preceding build.
@Test func deltaEnclosuresAreCollectedAsPatches() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
      <item>
        <title>Keka</title>
        <sparkle:version>5729</sparkle:version>
        <sparkle:shortVersionString>1.6.7</sparkle:shortVersionString>
        <enclosure url="https://github.com/aonez/Keka/releases/download/v1.6.7/Keka-1.6.7.zip"
                   length="32861805" type="application/octet-stream" sparkle:edSignature="full-sig"/>
        <sparkle:deltas>
          <enclosure url="https://github.com/aonez/Keka/releases/download/v1.6.7/1.6.4r5707-1.6.7r5729.delta"
                     sparkle:version="5729" sparkle:deltaFrom="5707" length="1345567"
                     type="application/octet-stream" sparkle:edSignature="sig-5707"/>
          <enclosure url="https://github.com/aonez/Keka/releases/download/v1.6.7/1.6.5r5715-1.6.7r5729.delta"
                     sparkle:version="5729" sparkle:deltaFrom="5715" length="519746"
                     type="application/octet-stream" sparkle:edSignature="sig-5715"/>
        </sparkle:deltas>
      </item>
    </channel>
    </rss>
    """
    let items = SparkleAppcastParser.parse(Data(xml.utf8))
    let item = try #require(items.first)

    // The real download is still the archive, with the archive's own signature.
    #expect(item.enclosureURL?.lastPathComponent == "Keka-1.6.7.zip")
    #expect(item.enclosureLength == 32_861_805)
    #expect(item.edSignature == "full-sig")

    // And each patch is carried with the build it upgrades FROM.
    #expect(item.deltas.count == 2)
    let from5715 = try #require(item.deltas.first { $0.fromBuild == "5715" })
    #expect(from5715.size == 519_746)
    #expect(from5715.edSignature == "sig-5715")
    #expect(from5715.url.lastPathComponent == "1.6.5r5715-1.6.7r5729.delta")

    // A patch signature must never be mistaken for the archive's: they sign
    // different bytes, and verifying one against the other fails closed.
    #expect(from5715.edSignature != item.edSignature)
}
