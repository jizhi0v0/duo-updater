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

// MARK: - relative URLs in the appcast

/// Helium's real feed shape (`updates.helium.computer/mac/appcast-arm64.xml`,
/// 2026-08-31): every URL in it is written relative to the feed. That is a
/// supported Sparkle appcast — `SUAppcastItem` resolves each URL with
/// `[NSURL URLWithString:… relativeToURL:appcastURL]` — even though RSS 2.0 says
/// an enclosure url "must be an http url". Before this, `URL(string:)` with no
/// base produced a schemeless URL: the item parsed, the row would have looked
/// fine, and the download was unfetchable.
private let relativeFeedFixture = """
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel>
  <title>Helium (arm64)</title>
  <item>
    <title>0.16.2.1</title>
    <pubDate>Sat, 29 Aug 2026 11:21:24 GMT</pubDate>
    <sparkle:version>0.16.2.1</sparkle:version>
    <sparkle:shortVersionString>0.16.2.1</sparkle:shortVersionString>
    <sparkle:releaseNotesLink>notes/0.16.2.1.html</sparkle:releaseNotesLink>
    <enclosure url="assets/helium_0.16.2.1_arm64-macos.dmg" length="124017808"
               sparkle:edSignature="sig" type="application/octet-stream"/>
    <sparkle:deltas>
      <enclosure url="assets/0.16.2.1-0.16.1.1-arm64.delta" length="40212558"
                 sparkle:deltaFrom="0.16.1.1" sparkle:edSignature="sig"
                 type="application/octet-stream"/>
    </sparkle:deltas>
  </item>
</channel>
</rss>
"""

@Test func relativeURLsResolveAgainstTheFeedTheyCameFrom() throws {
    let feed = URL(string: "https://updates.helium.computer/mac/appcast-arm64.xml")!
    let items = SparkleAppcastParser.parse(Data(relativeFeedFixture.utf8), relativeTo: feed)
    let item = try #require(items.first)

    #expect(item.enclosureURL?.absoluteString
        == "https://updates.helium.computer/mac/assets/helium_0.16.2.1_arm64-macos.dmg")
    #expect(item.releaseNotesLink?.absoluteString
        == "https://updates.helium.computer/mac/notes/0.16.2.1.html")
    // Patches too — Sparkle resolves the delta enclosures against the same base,
    // and a delta we cannot fetch is worse than one we never offered.
    #expect(item.deltas.count == 1)
    #expect(item.deltas.first?.url.absoluteString
        == "https://updates.helium.computer/mac/assets/0.16.2.1-0.16.1.1-arm64.delta")

    // `.absoluteURL`, so nothing downstream carries a base around: a relative
    // URL prints as "assets/…" in a log, a verify report, or an issue body.
    #expect(item.enclosureURL?.baseURL == nil)
}

/// Every feed we read today publishes absolute URLs, and a base must not touch
/// them — `URL(string:relativeTo:)` ignores the base when the string has its own
/// scheme, and this pins that so the change stays a no-op for all of them.
@Test func absoluteURLsAreUnaffectedByTheBase() throws {
    let xml = relativeFeedFixture
        .replacingOccurrences(of: "\"assets/", with: "\"https://cdn.example.com/x/")
        .replacingOccurrences(of: ">notes/", with: ">https://example.com/notes/")
    let items = SparkleAppcastParser.parse(
        Data(xml.utf8), relativeTo: URL(string: "https://updates.helium.computer/mac/appcast-arm64.xml")!)
    let item = try #require(items.first)
    #expect(item.enclosureURL?.absoluteString
        == "https://cdn.example.com/x/helium_0.16.2.1_arm64-macos.dmg")
    #expect(item.releaseNotesLink?.absoluteString == "https://example.com/notes/0.16.2.1.html")
    #expect(item.deltas.first?.url.absoluteString
        == "https://cdn.example.com/x/0.16.2.1-0.16.1.1-arm64.delta")
}
