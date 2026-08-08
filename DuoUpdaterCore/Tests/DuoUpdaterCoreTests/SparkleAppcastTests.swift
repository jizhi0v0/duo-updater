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
