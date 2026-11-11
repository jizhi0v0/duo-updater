import XCTest
@testable import DuoUpdaterCore

/// Several appcast items with one marketing version: when they are one release
/// (list it once) and when they are several (list each, titled with its build).
/// Issue #1921.
final class SparkleSameVersionBuildsTests: XCTestCase {

    private struct Item {
        var short: String?
        var build: String?
        var notes: [String]
        var file: String = "App.zip"
        var arm64Tag = false
        var second = "00"
    }

    private func changelog(_ items: [Item]) throws -> Changelog {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel>
        \(items.map(render).joined(separator: "\n"))
        </channel>
        </rss>
        """
        let parsed = SparkleAppcastParser.parse(Data(xml.utf8))
        XCTAssertEqual(parsed.count, items.count)
        let app = InstalledApp(
            name: "Probe", bundleID: "com.example.probe",
            shortVersion: "0.9", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/Probe.app"),
            isMASApp: false, sparkleFeedURL: nil)
        // Pinned to Apple silicon with Rosetta, so an x86_64 twin stays usable
        // and reaches the changelog, the way it does on a real Mac.
        let usable = SparkleAppcastSource.usableItems(
            for: app, from: parsed, osVersion: "26.0.0",
            hostArch: .arm64, allowingIntelTranslation: true)
        return try XCTUnwrap(SparkleAppcastSource.structuredChangelog(from: usable))
    }

    private func render(_ item: Item) -> String {
        let list = "<ul>" + item.notes.map { "<li>\($0)</li>" }.joined() + "</ul>"
        return """
          <item>
            <pubDate>Mon, 09 Nov 2026 14:52:\(item.second) +0800</pubDate>
            \(item.build.map { "<sparkle:version>\($0)</sparkle:version>" } ?? "")
            \(item.short.map { "<sparkle:shortVersionString>\($0)</sparkle:shortVersionString>" } ?? "")
            \(item.arm64Tag ? "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>" : "")
            <description><![CDATA[\(list)]]></description>
            <enclosure url="https://example.invalid/\(item.file)" length="1" type="application/octet-stream"/>
          </item>
        """
    }

    /// Rex's shape: builds 24…26 are all 1.1, each with its own notes. Every
    /// build gets an entry, titled with its build; `version` stays "1.1".
    func testBuildsOfOneVersionWithTheirOwnNotesEachGetAnEntry() throws {
        let log = try changelog([
            Item(short: "1.1", build: "26", notes: ["Aggregation management."], arm64Tag: true),
            Item(short: "1.1", build: "25", notes: ["Fixed stacked titles."], arm64Tag: true),
            Item(short: "1.1", build: "24", notes: ["Environment switcher."], arm64Tag: true),
            Item(short: "1.0.2", build: "19", notes: ["Import conflicts."], arm64Tag: true),
        ])
        XCTAssertEqual(log.entries.map(\.version), ["1.1", "1.1", "1.1", "1.0.2"])
        XCTAssertEqual(log.entries.map(\.title), ["1.1 (26)", "1.1 (25)", "1.1 (24)", nil])
        XCTAssertEqual(log.entries.map(\.items), [
            ["Aggregation management."], ["Fixed stacked titles."],
            ["Environment switcher."], ["Import conflicts."],
        ])
    }

    /// A respin whose notes are copied from the build before it: one entry,
    /// untitled, which is what this feed showed before #1921.
    func testRespinWithCopiedNotesStaysOneEntry() throws {
        let log = try changelog([
            Item(short: "2.0", build: "201", notes: ["New editor."]),
            Item(short: "2.0", build: "200", notes: ["New editor."]),
        ])
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertNil(log.entries.first?.title)
        XCTAssertEqual(log.entries.first?.version, "2.0")
    }

    /// Backdrop 2.7.0's shape: build 129's notes are build 128's plus one line.
    /// The older build has nothing the newer one lacks, so one entry.
    func testOlderBuildWhoseNotesTheNewerOneRepeatsStaysOneEntry() throws {
        let log = try changelog([
            Item(short: "2.7.0", build: "129", notes: ["New: Discover.", "Fixed: Menus.", "Fixed: Search."]),
            Item(short: "2.7.0", build: "128", notes: ["New: Discover.", "Fixed: Menus."], second: "01"),
        ])
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertNil(log.entries.first?.title)
        XCTAssertEqual(log.entries.first?.items.count, 3)
    }

    /// Astropad 5.3.3's shape: identical notes under a line naming the build.
    /// That line is not a note of its own, so one entry.
    func testLineNamingTheBuildDoesNotSplitAnOtherwiseCopiedRelease() throws {
        let log = try changelog([
            Item(short: "5.3.3", build: "4771", notes: ["What's new in 5.3.3.4771", "Fixed pairing."]),
            Item(short: "5.3.3", build: "4740", notes: ["What's new in 5.3.3.4740", "Fixed pairing."],
                 second: "01"),
        ])
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries.first?.items.first, "What's new in 5.3.3.4771")
    }

    /// One build per architecture, numbered separately, with a line that names
    /// the architecture. Still one release, so one entry.
    func testSeparatelyNumberedArchitectureTwinsStayOneEntry() throws {
        let log = try changelog([
            Item(short: "3.4", build: "341", notes: ["Faster sync.", "Apple silicon build."],
                 file: "App-3.4-arm64.zip"),
            Item(short: "3.4", build: "340", notes: ["Faster sync.", "Intel build."],
                 file: "App-3.4-x86_64.zip", second: "01"),
        ])
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertNil(log.entries.first?.title)
        XCTAssertEqual(log.entries.first?.items, ["Faster sync.", "Apple silicon build."])
    }

    /// Two items with a marketing version but no build: there is no build to
    /// tell them apart by, so they merge as before.
    func testItemsWithoutABuildStayOneEntry() throws {
        let log = try changelog([
            Item(short: "5.0", build: nil, notes: ["Second notes."]),
            Item(short: "5.0", build: nil, notes: ["First notes."], second: "01"),
        ])
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertNil(log.entries.first?.title)
    }

    /// Switchy's shape: many builds of the newest versions. The 40-entry cap
    /// keeps one entry for every version first, so the oldest versions are
    /// not pushed out by extra builds of the newer ones.
    func testExtraBuildsNeverPushAVersionPastTheCap() throws {
        var items: [Item] = []
        var build = 200
        for minor in stride(from: 9, through: 0, by: -1) {
            for n in 0..<8 {
                items.append(Item(short: "1.\(minor)", build: String(build), notes: ["1.\(minor) change \(n)."]))
                build -= 1
            }
        }
        let log = try changelog(items)
        XCTAssertEqual(log.entries.count, 40)
        XCTAssertEqual(Set(log.entries.map(\.version)).count, 10, "every version keeps an entry")
        XCTAssertEqual(log.entries.last?.version, "1.0")
        XCTAssertEqual(log.entries.filter { $0.version == "1.9" }.count, 8, "newest builds fill the rest")
    }

    /// A feed whose versions all differ is untouched: no titles appear.
    func testDistinctVersionsGetNoTitles() throws {
        let log = try changelog([
            Item(short: "1.2", build: "12", notes: ["Two."]),
            Item(short: "1.1", build: "11", notes: ["One."]),
        ])
        XCTAssertEqual(log.entries.map(\.version), ["1.2", "1.1"])
        XCTAssertEqual(log.entries.map(\.title), [nil, nil])
    }

    /// A build-only feed (no shortVersionString) shows the build as the version,
    /// so no title is added to repeat it.
    func testBuildOnlyFeedGetsNoTitle() throws {
        let log = try changelog([
            Item(short: nil, build: "1853", notes: ["Two."]),
            Item(short: nil, build: "1852", notes: ["One."]),
        ])
        XCTAssertEqual(log.entries.map(\.version), ["1853", "1852"])
        XCTAssertEqual(log.entries.map(\.title), [nil, nil])
    }
}
