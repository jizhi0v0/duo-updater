import XCTest
@testable import DuoUpdaterCore

final class AppcastMarkdownParserTests: XCTestCase {

    func testKeepsHeadingsProseBulletsAndCode() {
        let md = """
        ### Logbook

        The Logbook feature has now been added to Surge.

        - Surge Dashboard supports reading Logbook content.

        ### Proxy Protocol

        - Added HTTP/2 CONNECT proxy support.

        ```
        Proxy = http, example.com, 8080
        ```
        """
        let items = AppcastMarkdownParser.items(from: md)
        // Heading kept, prose kept, bullets unwrapped, fenced code kept (no ```).
        XCTAssertEqual(items.first, "Logbook")
        XCTAssertTrue(items.contains("The Logbook feature has now been added to Surge."))
        XCTAssertTrue(items.contains("Surge Dashboard supports reading Logbook content."))
        XCTAssertTrue(items.contains("Added HTTP/2 CONNECT proxy support."))
        XCTAssertTrue(items.contains("Proxy = http, example.com, 8080"))
        XCTAssertFalse(items.contains(where: { $0.contains("```") }))
    }

    func testStripsInlineEmphasis() {
        let items = AppcastMarkdownParser.items(from: "- Fixed **SNI** and `headers=` handling")
        XCTAssertEqual(items, ["Fixed SNI and headers= handling"])
    }

    func testEpochPubDateBecomesYMD() {
        // 1780324303 → 2026-06-01 (UTC).
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "1780324303"), "2026-06-01")
        XCTAssertNil(AppcastMarkdownParser.displayDate(from: nil))
        XCTAssertNil(AppcastMarkdownParser.displayDate(from: "  "))
        // Non-epoch strings pass through verbatim.
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "March 2026"), "March 2026")
    }

    /// End-to-end against a real Surge appcast: markdownDescription items become a
    /// multi-version structured changelog instead of a web-view fallback.
    func testSurgeAppcastProducesStructuredChangelog() throws {
        let xml = Self.surgeAppcast.data(using: .utf8)!
        let parsed = SparkleAppcastParser.parse(xml)
        XCTAssertEqual(parsed.count, 2)

        let app = InstalledApp(
            name: "Surge", bundleID: "com.nssurge.surge-mac",
            shortVersion: "6.5.0", buildVersion: "10960",
            path: URL(fileURLWithPath: "/Applications/Surge.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let usable = SparkleAppcastSource.usableItems(for: app, from: parsed, osVersion: "26.0.0")
        XCTAssertEqual(usable.first?.shortVersionString, "6.6.0", "highest version first")

        let changelog = SparkleAppcastSource.structuredChangelog(from: usable)
        XCTAssertEqual(changelog?.entries.count, 2)
        let top = try XCTUnwrap(changelog?.entries.first)
        XCTAssertEqual(top.version, "6.6.0")
        XCTAssertEqual(top.date, "2026-06-01")
        XCTAssertTrue(top.items.contains("Logbook"))
        XCTAssertTrue(top.items.contains("Added HTTP/2 CONNECT proxy support."))
    }

    private static let surgeAppcast = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
      <item>
        <title>Version 6.6.0</title>
        <markdownDescription><![CDATA[
    ### Logbook

    - Added HTTP/2 CONNECT proxy support.
    ]]></markdownDescription>
        <pubDate>1780324303</pubDate>
        <enclosure url="https://dl.nssurge.com/mac/Surge-6.6.0.zip" sparkle:version="11270" sparkle:shortVersionString="6.6.0"/>
        <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
      </item>
      <item>
        <title>Version 6.5.0</title>
        <markdownDescription><![CDATA[
    ### Fixes

    - Fixed a crash.
    ]]></markdownDescription>
        <pubDate>1770000000</pubDate>
        <enclosure url="https://dl.nssurge.com/mac/Surge-6.5.0.zip" sparkle:version="10960" sparkle:shortVersionString="6.5.0"/>
        <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
      </item>
    </channel>
    </rss>
    """
}
