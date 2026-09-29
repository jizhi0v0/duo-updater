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

    /// `displayDate` shared `TimeInterval(String)`'s over-acceptance with
    /// `ReleaseDate.parse`: a `yyyyMMdd` pubDate displayed as 1970-08-23, a
    /// millisecond epoch as the year 57450, and "nan" as whatever the formatter
    /// makes of a non-finite Date. It now reads digit runs through the same
    /// helper `ReleaseDate` uses, and passes anything that is not a date through.
    func testDigitRunsAreReadAsDatesOnlyWhenPlausible() {
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "20260614"), "2026-06-14")
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "1750785600000"), "2025-06-24")
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "1780324303"), "2026-06-01")
        // Not dates: shown as written, never as an epoch reading.
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "2026"), "2026")
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "nan"), "nan")
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "infinity"), "infinity")
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "1e9"), "1e9")
        XCTAssertEqual(AppcastMarkdownParser.displayDate(from: "99999999"), "99999999")
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
        // One heading per release is below the styling threshold: flat, as before.
        XCTAssertTrue(top.content.isEmpty)
    }

    /// Osaurus's appcast is its GitHub release bodies, shipped as
    /// `<description sparkle:format="markdown">`. Its headings used to come out as
    /// bullets ("• What's Changed"); they are now `.heading` blocks, decided by the
    /// same rule as the GitHub path, and `items` carries only the notes.
    ///
    /// Mutation: in `AppcastMarkdownParser.entry`, append the heading to `notes`
    /// as well (headings fall back into `items`), or return the flat entry
    /// unconditionally (no `content`) — either way this fails.
    func testOsaurusHeadingsBecomeHeadingBlocks() throws {
        let parsed = SparkleAppcastParser.parse(Data(Self.osaurusAppcast.utf8))
        let changelog = SparkleAppcastSource.structuredChangelog(from: parsed)
        let entry = try XCTUnwrap(changelog?.entries.first)
        XCTAssertEqual(entry.version, "0.25.14")

        let notes = [
            "Clarify background model admission for description backfill (#2901) by @jjang-ai",
            "added iOS app integrations (#2875) by @RaajeevChandran",
            "Fix covariant Self default argument in ProductHuntLaunchCampaign init (#2906) by @tpae",
            "Fix timing export choices for restored chats (#2902) by @jjang-ai",
            "Postpone the Raptor Product Hunt dialogs (#2905) by @tpae",
            "Full Changelog: https://github.com/osaurus-ai/osaurus/compare/0.25.13...0.25.14",
        ]
        XCTAssertEqual(entry.items, notes)
        XCTAssertEqual(entry.content, [
            .heading("What's Changed"), .note(notes[0]), .note(notes[1]),
            .heading("🐛 Bug Fixes"), .note(notes[2]), .note(notes[3]),
            .heading("🧰 Maintenance"), .note(notes[4]), .note(notes[5]),
        ])
    }

    /// A heading with nothing under it before the next one is not emitted, and a
    /// version-like heading does not qualify and is dropped — both as in
    /// `GitHubMarkdownParser`.
    func testDanglingAndVersionLikeHeadingsAreDropped() throws {
        let md = """
        ## Release 2.0
        ## Added
        ## Fixed
        - Fixed a crash on launch.
        ## Changed
        - Faster sync.
        """
        let entry = try XCTUnwrap(AppcastMarkdownParser.entry(from: md, version: "2.0", date: nil))
        XCTAssertEqual(entry.items, ["Fixed a crash on launch.", "Faster sync."])
        XCTAssertEqual(entry.content, [
            .heading("Fixed"), .note("Fixed a crash on launch."),
            .heading("Changed"), .note("Faster sync."),
        ])
    }

    /// Trimmed from the live feed (fetched 2026-09-29): 0.25.14 with its three
    /// headings, two bullets of seven under Bug Fixes, and the trailing link line.
    private static let osaurusAppcast = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
      <item>
        <title>0.25.14</title>
        <pubDate>Sun, 27 Sep 2026 07:10:28 +0000</pubDate>
        <sparkle:channel>release</sparkle:channel>
        <sparkle:version>0.25.14</sparkle:version>
        <sparkle:shortVersionString>0.25.14</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
        <enclosure url="https://github.com/osaurus-ai/osaurus/releases/download/0.25.14/Osaurus-0.25.14.dmg" length="79256834" type="application/octet-stream"/>
        <description sparkle:format="markdown"><![CDATA[
    ## What's Changed

    - Clarify background model admission for description backfill (#2901) by @jjang-ai
    - added iOS app integrations (#2875) by @RaajeevChandran

    ## 🐛 Bug Fixes

    - Fix covariant Self default argument in ProductHuntLaunchCampaign init (#2906) by @tpae
    - Fix timing export choices for restored chats (#2902) by @jjang-ai

    ## 🧰 Maintenance

    - Postpone the Raptor Product Hunt dialogs (#2905) by @tpae

    **Full Changelog**: https://github.com/osaurus-ai/osaurus/compare/0.25.13...0.25.14
    ]]></description>
      </item>
    </channel>
    </rss>
    """

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
