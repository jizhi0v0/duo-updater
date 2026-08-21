import XCTest
@testable import DuoUpdaterCore

/// Fixtures below are byte-for-byte slices of real, currently-live appcasts
/// (fetched 2026-08-22), not hand-written approximations — the whole point of
/// `AppcastHTMLChangelogParser` is to survive vendors' actual markup, not a tidy
/// version of it.
///
///   - TablePro (`raw.githubusercontent.com/TableProApp/TablePro/main/appcast.xml`):
///     `<h3>` section headings + `<ul><li>`, backticked inline code, literal `**`
///     the vendor typed (not markdown — kept as-is).
///   - Fork (`fork.dev/update/feed.xml`): flat `<ul><li>`, no headings at all.
///   - TablePlus (`tableplus.com/osx/version.xml`): `<h2>` title + `<h4>` "Release
///     date: …" + `<ol><li>`, then trailing `<h2><a href=…>` footer links with no
///     items under them — the shape that exercises both heading filters at once.
///
/// The one exception is `plainProseAppcast` below: no installed app's live feed
/// turned up a pure-paragraph `<description>` to slice (every real inline-HTML
/// feed found while building this — TablePro, Fork, TablePlus — already used
/// list markup), so that fixture is a constructed representative instead, used
/// only to pin the "don't convert prose" boundary.
final class AppcastHTMLChangelogParserTests: XCTestCase {

    // MARK: - isStructured

    func testIsStructuredRequiresListItems() {
        XCTAssertTrue(AppcastHTMLChangelogParser.isStructured("<ul><li>x</li></ul>"))
        XCTAssertTrue(AppcastHTMLChangelogParser.isStructured("<ol><li>x</li></ol>"))
        XCTAssertFalse(AppcastHTMLChangelogParser.isStructured("<p>Bug fixes and performance improvements.</p>"))
        XCTAssertFalse(AppcastHTMLChangelogParser.isStructured(""))
    }

    // MARK: - TablePro (h3 sections, backticks, literal **)

    func testTableProSectionHeadingsLandInOrderWithItemsAttached() throws {
        let entry = try XCTUnwrap(AppcastHTMLChangelogParser.entry(
            html: Self.tableProItem064Description, version: "0.64.0", date: "2026-08-10"))
        XCTAssertEqual(entry.version, "0.64.0")

        // Five sections, each heading immediately followed by its own items — not
        // reshuffled, not merged into one bucket.
        let expectedHeadings = ["Added", "Changed", "Removed", "Fixed", "Security"]
        let headingIndexes = expectedHeadings.map { heading in
            entry.items.firstIndex(of: heading)
        }
        XCTAssertEqual(headingIndexes.compactMap { $0 }.count, expectedHeadings.count,
                       "every section heading must survive")
        // Strictly ascending: sections appear in document order.
        let positions = headingIndexes.compactMap { $0 }
        XCTAssertEqual(positions, positions.sorted())

        // The first item after "Added" belongs to Added, not some other section.
        let addedIndex = try XCTUnwrap(entry.items.firstIndex(of: "Added"))
        XCTAssertTrue(entry.items[addedIndex + 1].contains("Match Case in the filter operator menu"))

        // TablePro wraps shortcuts/identifiers in literal backticks rather than an
        // actual `<code>` tag — since that's plain text, not markup, the tag
        // stripper never touches it, and it must survive verbatim (this is also
        // what the existing raw-HTML fallback path already shows the user, so
        // dropping the backticks here would be a visible regression, not a fix).
        XCTAssertTrue(entry.items.contains { $0.contains("`Cmd+F` finds in whatever is in front of you") })
        XCTAssertTrue(entry.items.contains { $0.contains("`database` argument, so another database can be inspected") })

        // The very last `<li>` in the document (under Security) must not be lost —
        // this is exactly the position the old chunk-splitter's `\n`-cut bug ate.
        XCTAssertEqual(entry.items.last, "Updated Sparkle to 2.9.5, patching CVE-2026-47121 and CVE-2026-47122 in the updater.")
    }

    func testTableProLiteralDoubleAsteriskIsNotMarkdownAndSurvives() throws {
        // This item's vendor-authored text contains a literal "**RDS Endpoint**" —
        // not markdown emphasis (itemSyntax stays .plain for this whole path), so
        // it must come through unchanged rather than being stripped like
        // AppcastMarkdownParser strips real markdown `**`.
        let entry = try XCTUnwrap(AppcastHTMLChangelogParser.entry(
            html: Self.tableProItem0601Description, version: "0.60.1", date: "2026-07-25"))
        XCTAssertEqual(entry.items, [
            "Added",
            "AWS IAM connections have an **RDS Endpoint** field, for when the connection points at a port forward you run yourself and TablePro cannot tell which database is behind it. The MySQL and PostgreSQL profile fields now list the profiles found on disk, like MariaDB already did. (#1432)",
            "Fixed",
            "AWS IAM authentication now works through a tunnel. The token was signed for the local forward instead of the database endpoint, so RDS rejected every connection made over SSH, Cloudflare, Cloud SQL Auth Proxy, or SOCKS. A tunneled connection also no longer needs the region filled in by hand. (#1432)",
        ])
        // items.last is the final <li> in the document — pinned explicitly since
        // that position is where a mid-document chunk cut used to lose bullets.
        XCTAssertEqual(entry.items.last, entry.items[3])
    }

    // MARK: - Fork (flat <ul><li>, no headings)

    func testForkFlatListNoHeadingsKeepsAllItemsInOrder() throws {
        let entry = try XCTUnwrap(AppcastHTMLChangelogParser.entry(
            html: Self.forkItem269Description, version: "2.69.0", date: "2026-07-10"))
        XCTAssertEqual(entry.items, [
            "Add \"Save as Patch\" option to stash context menu",
            "Show warning icon for active branch with invalid upstream",
            "Show submodule icon instead of blank file icon in file views",
            "Improved: Re-apply context search when switching files in diff view",
            "Fixed: Overlapping rows in commit list after fetch",
            "Fixed: Submodule diff when the commit is missing",
            "Fixed: Crash in binary image diff rendering",
        ])
        XCTAssertEqual(entry.items.last, "Fixed: Crash in binary image diff rendering")
    }

    // MARK: - TablePlus (h2 title + h4 date heading + ol/li + trailing link-only h2s)

    func testTablePlusDropsDateHeadingAndTrailingLinkFootersButKeepsTitleAndItems() throws {
        let entry = try XCTUnwrap(AppcastHTMLChangelogParser.entry(
            html: Self.tablePlusDescription, version: "26.9.6", date: "2026-08-12"))

        // The release-title h2 is kept (it precedes the <ol> items).
        XCTAssertEqual(entry.items.first, "Build 762 - Support MacOS 27 Golden Gate")
        // The "Release date: …" h4 duplicates `entry.date` and must not appear.
        XCTAssertFalse(entry.items.contains { $0.lowercased().hasPrefix("release date") })
        // The trailing footer headings are pure links to other pages, not section
        // titles — dropped, not shown as bare "Older change logs." / "Bug report." bullets.
        XCTAssertFalse(entry.items.contains("Older change logs."))
        XCTAssertFalse(entry.items.contains("Bug report."))
        // The three real <ol><li> change lines all survive, in order.
        XCTAssertEqual(entry.items, [
            "Build 762 - Support MacOS 27 Golden Gate",
            "Supported Cell Selection.",
            "Updated app layout.",
            "Bug fixes and new features.",
        ])
        XCTAssertEqual(entry.items.last, "Bug fixes and new features.")
    }

    // MARK: - Pure prose (constructed — see file-level note)

    func testPureProseDescriptionIsNotConverted() {
        XCTAssertNil(AppcastHTMLChangelogParser.entry(
            html: Self.plainProseAppcast, version: "4.2.0", date: "2026-08-01"))
    }

    // MARK: - End-to-end through SparkleAppcastSource.structuredChangelog

    func testStructuredChangelogFromRealTableProItems() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel>
          <item>
            <title>0.64.0</title>
            <pubDate>Mon, 10 Aug 2026 16:19:27 +0000</pubDate>
            <sparkle:version>117</sparkle:version>
            <sparkle:shortVersionString>0.64.0</sparkle:shortVersionString>
            <description><![CDATA[\(Self.tableProItem064Description)]]></description>
            <enclosure url="https://github.com/TableProApp/TablePro/releases/download/v0.64.0/TablePro-0.64.0-x86_64.zip" sparkle:version="117" sparkle:shortVersionString="0.64.0"/>
          </item>
          <item>
            <title>0.60.1</title>
            <pubDate>Sat, 25 Jul 2026 08:09:47 +0000</pubDate>
            <sparkle:version>113</sparkle:version>
            <sparkle:shortVersionString>0.60.1</sparkle:shortVersionString>
            <description><![CDATA[\(Self.tableProItem0601Description)]]></description>
            <enclosure url="https://github.com/TableProApp/TablePro/releases/download/v0.60.1/TablePro-0.60.1-arm64.zip" sparkle:version="113" sparkle:shortVersionString="0.60.1"/>
          </item>
        </channel>
        </rss>
        """
        let parsed = SparkleAppcastParser.parse(xml.data(using: .utf8)!)
        XCTAssertEqual(parsed.count, 2)

        let app = InstalledApp(
            name: "TablePro", bundleID: "com.TablePro",
            shortVersion: "0.60.1", buildVersion: "113",
            path: URL(fileURLWithPath: "/Applications/TablePro.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let usable = SparkleAppcastSource.usableItems(for: app, from: parsed, osVersion: "26.0.0")
        XCTAssertEqual(usable.count, 2)

        let changelog = try XCTUnwrap(SparkleAppcastSource.structuredChangelog(from: usable))
        XCTAssertEqual(changelog.entries.count, 2)
        XCTAssertEqual(changelog.entries.first?.version, "0.64.0", "highest version first")
        XCTAssertEqual(changelog.entries.first?.items.first, "Added")
    }

    // MARK: - Fixtures (real bytes; see file-level doc comment)

    private static let tableProItem064Description = """
    <h3>Added</h3>
    <ul>
    <li>Match Case in the filter operator menu, on every database that can express it. (#2048)</li>
    <li>Oracle SYSDBA and SYSOPER logons, on Mac and mobile. (#2039)</li>
    <li>Oracle in TablePro Mobile, with a Service Name or SID picker. (#2033)</li>
    <li>A workspace rail listing every open connection and database, with its own shortcuts. (#1282)</li>
    <li>Disconnect and Reconnect, from the Database menu, the rail, or the connection list.</li>
    <li>A Database menu, plus Minimize, Zoom, Move Tab to New Window, Show Toolbar, and Customize Toolbar.</li>
    <li>Show Object Icons, to turn sidebar icons off.</li>
    <li>Redshift external schemas now list their tables, marked in the sidebar and opened read-only.</li>
    </ul>
    <h3>Changed</h3>
    <ul>
    <li>The menu bar is rebuilt on native macOS menus, so every command follows the window you are using.</li>
    <li>`Cmd+F` finds in whatever is in front of you: rows in a table, text in the editor, the CSV inspector.</li>
    <li>Connecting fills the window and names the step it is on, and a failure shows the database's own error.</li>
    <li>Running a query or opening a table replaces whatever that tab was already running.</li>
    <li>Reopening the last session connects the window you land on first.</li>
    <li>A saved pre-connect script no longer runs on an automatic reopen.</li>
    <li>Settings opens in a standard preferences window.</li>
    <li>A tab's subtitle names the database it is bound to, and its toolbar repoints only that tab. (#2026)</li>
    <li>MCP and AI table tools take a `database` argument, so another database can be inspected. (#2026)</li>
    <li>Building from source now needs XcodeGen.</li>
    </ul>
    <h3>Removed</h3>
    <ul>
    <li>Show Tables Sidebar and Show Favorites Sidebar from the menu bar.</li>
    <li>The "Group all connections in one window" setting. Each connection has its own window. (#1282)</li>
    </ul>
    <h3>Fixed</h3>
    <ul>
    <li>A tab keeps running against the database it was opened on, so changing database no longer breaks it or writes to the wrong place. (#2026)</li>
    <li>Menu commands act on the selected row, column, and editor, and stay disabled when they would do nothing.</li>
    <li>A reconnect brings every window's tabs back, each in the window it was in.</li>
    <li>Window and tab names follow what the window is showing, and a name you chose is kept.</li>
    <li>Tabs are saved before a session ends, and a window that never loaded tabs no longer deletes them.</li>
    <li>A cancelled or failed connect leaves the window usable.</li>
    <li>A connection unreachable at launch is reopened next time, and reconnects once the server is up.</li>
    <li>Opening a connection that already has a window reuses it, and MCP-opened windows connect.</li>
    <li>Row counts refine to an exact count, and stop when you close the window or leave the table. (#2059)</li>
    <li>Clicking through the sidebar no longer loads tables you have left, or shows the previous table's rows. (#2058)</li>
    <li>Stop cancels reads only, so it can no longer cut off a save or a schema change.</li>
    <li>A brief SSH tunnel reconnect no longer closes tabs, and a dead tunnel offers to retry.</li>
    <li>The JSON view follows the grid's sort, filters, and hidden columns, and updates with every query.</li>
    <li>The editor restores your cursor and selection, and keeps autocomplete after a reconnect.</li>
    <li>AI replies stream smoothly, render markdown as they arrive, and no longer slow the panel down.</li>
    <li>Claude, Gemini, and local models no longer fail on thinking and image settings. (#2031)</li>
    <li>Filters compare text columns as text, match NULL and TRUE literally, and no longer break IS EMPTY. (#2029)</li>
    <li>Alerts, focus, calendars, number formats, and Reduce Motion follow system conventions.</li>
    <li>Oracle connections turn on TCP keepalive, so idle sessions survive. (#2038)</li>
    <li>iPhone and iPad ask for Local Network access only when it is needed. (#2040)</li>
    </ul>
    <h3>Security</h3>
    <ul>
    <li>Requests to TablePro's own servers require TLS again.</li>
    <li>Updated Sparkle to 2.9.5, patching CVE-2026-47121 and CVE-2026-47122 in the updater.</li>
    </ul>
    """

    private static let tableProItem0601Description = """
    <h3>Added</h3>
    <ul>
    <li>AWS IAM connections have an **RDS Endpoint** field, for when the connection points at a port forward you run yourself and TablePro cannot tell which database is behind it. The MySQL and PostgreSQL profile fields now list the profiles found on disk, like MariaDB already did. (#1432)</li>
    </ul>
    <h3>Fixed</h3>
    <ul>
    <li>AWS IAM authentication now works through a tunnel. The token was signed for the local forward instead of the database endpoint, so RDS rejected every connection made over SSH, Cloudflare, Cloud SQL Auth Proxy, or SOCKS. A tunneled connection also no longer needs the region filled in by hand. (#1432)</li>
    </ul>
    """

    private static let forkItem269Description = """
    <ul>
                <li>Add "Save as Patch" option to stash context menu</li>
                <li>Show warning icon for active branch with invalid upstream</li>
                <li>Show submodule icon instead of blank file icon in file views</li>
                <li>Improved: Re-apply context search when switching files in diff view</li>
                <li>Fixed: Overlapping rows in commit list after fetch</li>
                <li>Fixed: Submodule diff when the commit is missing</li>
                <li>Fixed: Crash in binary image diff rendering</li>
            </ul>
    """

    /// TablePlus's `<description>` is not CDATA-wrapped — the vendor entity-
    /// escapes the HTML instead (`&lt;h2&gt;`) — but by the time it reaches us
    /// `SparkleAppcastParser`'s `foundCharacters` callback has already had
    /// `XMLParser` decode those entities once, same as it would for any other XML
    /// text node, so this fixture is written with literal tags (what
    /// `descriptionHTML` actually contains at runtime), not escaped ones.
    private static let tablePlusDescription = """
    <h2>Build 762 - Support MacOS 27 Golden Gate</h2>
            <h4>Release date: 12 August 2026</h4>
            <ol>
            \t<li>Supported Cell Selection.</li>
            \t<li>Updated app layout.</li>
            \t<li>Bug fixes and new features.</li>
    \t\t </ol>
            <h2><a href='https://tableplus.com/osx/changelog'>Older change logs.</a><h2>
            <h2><a href='https://github.com/TablePlus/TablePlus/issues'>Bug report.</a><h2>
    """

    /// Constructed — see file-level note. Modeled on the common "prose only, no
    /// vendor structure" appcast style: a version heading and plain paragraphs,
    /// no `<ul>`/`<ol>` anywhere.
    private static let plainProseAppcast = """
    <p>This release focuses on stability and performance.</p>
    <p>We fixed a number of crashes reported by users and improved startup time on older Macs.</p>
    <p>Thanks for your continued support!</p>
    """
}
