import Testing
import Foundation
@testable import DuoUpdaterCore

/// Arc (`releases.arc.net/updates.xml`) and Dia
/// (`releases.diabrowser.com/BoostBrowser-updates.xml`) write every item's date
/// as `<pubdate>Oct 2, 2026 at 9:45:23 PM</pubdate>`: the element name all
/// lowercase, and the value what an en_US `DateFormatter` prints at
/// `.medium`/`.medium` style (`MMM d, y 'at' h:mm:ss a`, U+202F before the
/// AM/PM marker), with no time zone. Both feeds came back with no dates at all,
/// so neither app had any release history.
///
/// Fixtures are verbatim: the feed header, the first `<item>` and the closing
/// tags of each live feed, fetched 2026-10-08. The only thing removed is the
/// other items.
struct SparkleLowercasePubdateTests {

    /// 2026-10-02T00:00:00Z: the calendar day both fixtures state, as a
    /// `.day`-precision value (start of that day in UTC, like `"2026-10-02"`).
    static let october2 = Date(timeIntervalSince1970: 1_790_899_200)

    // MARK: - Through the real parser

    @Test func arcLowercasePubdateBecomesADayInReleaseHistory() throws {
        let items = SparkleAppcastParser.parse(Data(Self.arcFeed.utf8))
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.pubDate == "Oct 2, 2026 at 9:45:23\u{202F}PM")

        let history = SparkleAppcastSource.releaseHistory(from: items)
        #expect(history.map(\.version) == ["1.167.1 (88217)"])
        // No zone in the feed, so no time of day may reach `publishedAt`.
        #expect(history.first?.publishedAt == nil)
        #expect(history.first?.vendorDay == Self.october2)
    }

    @Test func diaLowercasePubdateBecomesADayInReleaseHistory() throws {
        let items = SparkleAppcastParser.parse(Data(Self.diaFeed.utf8))
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.pubDate == "Oct 2, 2026 at 9:47:01\u{202F}PM")

        let history = SparkleAppcastSource.releaseHistory(from: items)
        #expect(history.map(\.version) == ["1.51.1 (88214)"])
        #expect(history.first?.publishedAt == nil)
        #expect(history.first?.vendorDay == Self.october2)
    }

    /// `<pubDate>` keeps priority: `<pubdate>` is only a fallback for an item
    /// that has no `<pubDate>`, so a feed carrying both reads exactly what it
    /// read before, whichever comes first.
    @Test func camelCasePubDateWinsOverLowercaseWhicheverComesFirst() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel>
          <item>
            <sparkle:version>2</sparkle:version>
            <pubdate>Oct 2, 2026 at 9:45:23 PM</pubdate>
            <pubDate>Wed, 24 Jun 2026 17:07:24 +0000</pubDate>
          </item>
          <item>
            <sparkle:version>1</sparkle:version>
            <pubDate>Wed, 24 Jun 2026 17:07:24 +0000</pubDate>
            <pubdate>Oct 2, 2026 at 9:45:23 PM</pubdate>
          </item>
        </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(xml.utf8))
        #expect(items.map(\.pubDate) == [
            "Wed, 24 Jun 2026 17:07:24 +0000",
            "Wed, 24 Jun 2026 17:07:24 +0000",
        ])
    }

    /// A `<pubdate>` in a foreign namespace is not RSS's, exactly like a
    /// prefixed `<x:pubDate>`.
    @Test func prefixedLowercasePubdateIsIgnored() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
             xmlns:x="https://example.invalid/x">
        <channel>
          <item>
            <sparkle:version>1</sparkle:version>
            <x:pubdate>Oct 2, 2026 at 9:45:23 PM</x:pubdate>
          </item>
        </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(xml.utf8))
        #expect(items.count == 1)
        #expect(items.first?.pubDate == nil)
    }

    // MARK: - The date shape itself

    @Test func mediumStyleZonelessDateIsADayNeverAMoment() {
        // Both separators: U+202F is what macOS 14+ prints, a plain space what
        // the same formatter printed before.
        for raw in ["Oct 2, 2026 at 9:47:01\u{202F}PM", "Oct 2, 2026 at 9:47:01 PM"] {
            let parsed = ReleaseDate.parseWithPrecision(raw)
            #expect(parsed == ReleaseDate.Parsed(date: Self.october2, precision: .day), "\(raw)")
            let fields = ReleaseDate.publishedFields(from: raw)
            #expect(fields.publishedAt == nil, "\(raw)")
            #expect(fields.vendorDay == Self.october2, "\(raw)")
            // `parse` answers only for a moment it can trust to the minute.
            #expect(ReleaseDate.parse(raw) == nil, "\(raw)")
        }
    }

    @Test func theStatedCalendarDayIsKeptWhateverTheHour() {
        // Just after midnight and just before: the same stated day both times.
        // Which UTC day the release fell on is unknown — that is the point.
        for raw in ["Oct 2, 2026 at 12:00:00\u{202F}AM", "Oct 2, 2026 at 11:59:59\u{202F}PM"] {
            #expect(ReleaseDate.publishedFields(from: raw).vendorDay == Self.october2, "\(raw)")
        }
        #expect(ReleaseDate.publishedFields(from: "Sep 23, 2026 at 7:12:27\u{202F}PM").vendorDay
            == Date(timeIntervalSince1970: 1_790_121_600))
    }

    @Test func nearMissesOfTheMediumStyleShapeStayUnparsed() {
        let rejects = [
            "Feb 30, 2026 at 9:47:01\u{202F}PM",   // no such day
            "Oct 2, 2026 at 13:47:01\u{202F}PM",   // 12-hour clock
            "Oct 2, 2026 at 9:47:01PM",            // no separator
            "Oct 2, 2026 at 9:47:01\u{202F}PM UTC", // trailing text
            "Oct 2, 2026 9:47:01\u{202F}PM",        // no "at"
            "Oct 2, 2026",                          // no time at all
            "October 2, 2026 at 9:47:01\u{202F}PM", // long month name
            "Oct 2, 26 at 9:47:01\u{202F}PM",       // two-digit year
            "Oct 2, 2026 at 9:47:01\u{00A0}PM",     // non-breaking space
            "Oct 2, 2026 at 9:47:01\u{202F}pm",     // lowercase marker
            "Oct 2, \u{FF12}\u{FF10}\u{FF12}\u{FF16} at 9:47:01\u{202F}PM", // full-width year
        ]
        for raw in rejects {
            #expect(ReleaseDate.parseWithPrecision(raw) == nil, "\(raw)")
        }
    }

    /// The new shape is tried after every existing one, so nothing that already
    /// parsed may change — pinned here at the exact instant and precision.
    @Test func shapesThatAlreadyParsedKeepTheirInstantAndPrecision() {
        let cases: [(String, TimeInterval, ReleaseDate.Precision)] = [
            ("Wed, 24 Jun 2026 17:07:24 +0000", 1_782_320_844, .minute),
            ("Wed, 24 Jun 2026 10:07:24 PDT", 1_782_320_844, .minute),
            ("Sun, 27 Sep 2026 16:09:46 GMT+0200", 1_790_518_186, .minute),
            ("2026-06-24T17:07:24Z", 1_782_320_844, .minute),
            ("2026-06-24T17:07:24.500Z", 1_782_320_844.5, .minute),
            ("2026-06-24T17:07:24", 1_782_320_844, .minute),
            ("1782320844", 1_782_320_844, .minute),
            ("2026-08-31", 1_788_134_400, .day),
            ("20260831", 1_788_134_400, .day),
        ]
        for (raw, epoch, precision) in cases {
            #expect(ReleaseDate.parseWithPrecision(raw)
                == ReleaseDate.Parsed(date: Date(timeIntervalSince1970: epoch), precision: precision),
                "\(raw)")
        }
    }

    // MARK: - Fixtures

    static let arcFeed = #"""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>New Version Available</title>
        <description>There's a new version available</description>
        <language>en</language>
        <item>
            <title>New Version Available</title>
            <description><![CDATA[<h3>Welcome back to another Arc update! Version 1.167.1 brings Arc to Chromium 154.0.8037.98, patching dozens of security vulnerabilities (one of them flagged critical) so you can keep exploring the web with confidence. That's everything in this release. Talk soon!</h3>]]></description>
            <pubdate>Oct 2, 2026 at 9:45:23 PM</pubdate>
            <sparkle:version>88217</sparkle:version>
            <sparkle:shortVersionString>1.167.1 (88217)</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0.0</sparkle:minimumSystemVersion>
            <enclosure url="https://releases.arc.net/release/Arc-1.167.1-88217.zip" sparkle:version="88217" sparkle:shortVersionString="1.167.1 (88217)" length="452211252" type="application/octet-stream" sparkle:edSignature="4Oul2UGmVoX77c1fIqv7wYzk478kksEiZ07YnO+vtMOThZtWosNWx/2r4AiCsrOMEJ1VytbqKWc5ULU/FmQAAA=="></enclosure>
            <sparkle:deltas>
                <enclosure url="https://releases.arc.net/release/Arc-from-88045-to-88217.delta" sparkle:deltaFrom="88045" length="42151554" type="application/octet-stream" sparkle:edSignature="uxe+S0cVVGF9u/FE9UMGE2qVFCaJFLtySW1IyVpplMNFyf7+k+xVrQPuZK/aNi6ezK1Q0+h/LNXCApe8iK2UCA=="></enclosure>
                <enclosure url="https://releases.arc.net/release/Arc-from-87668-to-88217.delta" sparkle:deltaFrom="87668" length="54671034" type="application/octet-stream" sparkle:edSignature="/SeuM4p08vx+xKEN3gLB2mhirg9Xb+4L4aG06mJdTUpGsIzPay3S+hJwAGK9it4vqvqsE62Vt/FwLrfFIRenBg=="></enclosure>
            </sparkle:deltas>
        </item>
    </channel>
</rss>
"""#

    static let diaFeed = #"""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:_xmlns="xmlns" _xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" _xmlns:dc="http://purl.org/dc/elements/1.1/">
    
    <channel>
        
        <title>New Version Available</title>
        
        <description>There&#39;s a new version available</description>
        
        <language>en</language>
        
        <item>
            
            <title>New Version Available</title>
            
            <description>&lt;p&gt;Dia 1.51.1 brings queued and steerable chat, Loom tools, and a round of tab and performance improvements.&lt;/p&gt;&lt;ul&gt;&lt;li&gt;&lt;strong&gt;Option for Calmer Automatic Tab Group Icons.&lt;/strong&gt; Adds an option to turn off emoji for automatic Tab Groups, replacing them with simpler icons. Shipped by Connor.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Simpler Tab Switching.&lt;/strong&gt; The tab switcher now has 5 tabs, instead of 10, making it clearer and easier to move between tabs with CTRL + Tab. Shipped by Connor.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Additional Keyboard Shortcuts for Developer Tools.&lt;/strong&gt; Adds shortcuts for opening the JS Console and Inspect Element, and fixes an issue with closed Dev Tools windows sometimes still consuming background resources. Shipped by Patrick.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Pinned Tabs Included in Tab Search.&lt;/strong&gt; Pinned Tabs now appear in Tab Search results, making it easier to find and switch to any tab. Shipped by Connor.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Improved Profile Swiping Performance.&lt;/strong&gt; Improves swipe-to-switch-profile animations to eliminate lag when releasing the gesture. Shipped by Connor.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Queue and Steering Controls.&lt;/strong&gt; Queue multiple chat messages and steer Dia mid-response without cancelling in-flight tool calls. Shipped by Nick.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Type into Command Bar While Dictating.&lt;/strong&gt; Lets users type in the command bar while actively dictating. Shipped by Samir.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Loom Automatic Tools.&lt;/strong&gt; Dia can automatically search Loom videos, read transcripts, and surface recent activity including videos watched, created, and their reactions and comments. Shipped by Ali.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Support HEIC image files in Chat.&lt;/strong&gt; Chat now accepts Apple .heic images, so users can paste phone photos directly. Shipped by Connor.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Faster and fuller Notion page reading.&lt;/strong&gt; Uses the Notion API for faster, more complete page scrapes (including collapsed sections) and respects enterprise restrictions. Shipped by Ali.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Smoother window resizing:&lt;/strong&gt; Resize even the heaviest pages without a hitch. Shipped by Sébastien&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Fix Enterprise Slack Domain Links.&lt;/strong&gt; Fixes broken Slack domain links in Chat and Morning Brief for enterprise users by correctly including enterprise hosts in URLs. Shipped by Rosey.&lt;/li&gt;&lt;li&gt;&lt;strong&gt;Chromium M155 Upgrade.&lt;/strong&gt; Upgrades the browser engine to Chromium M155. Shipped by Fabrice.&lt;/li&gt;&lt;/ul&gt;</description>
            
            <pubdate>Oct 2, 2026 at 9:47:01 PM</pubdate>
            
            <version xmlns="http://www.andymatuschak.org/xml-namespaces/sparkle">88214</version>
            
            <shortVersionString xmlns="http://www.andymatuschak.org/xml-namespaces/sparkle">1.51.1 (88214)</shortVersionString>
            
            <minimumSystemVersion xmlns="http://www.andymatuschak.org/xml-namespaces/sparkle">14.0</minimumSystemVersion>
            
            <enclosure url="https://releases.diabrowser.com/release/Dia-1.51.1-88214.zip" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" sparkle:version="88214" sparkle:shortVersionString="1.51.1 (88214)" length="852095538" type="application/octet-stream" sparkle:edSignature="NdzAOXlpl+YinWCtzYHHmHnG/L//n+AIDwpWSgSEvBmjpICzqutskfnl9eYbTbmOo+sTw9EkO5HixhQ5U7tfDg=="></enclosure>
            
            <deltas xmlns="http://www.andymatuschak.org/xml-namespaces/sparkle">
                
                <enclosure url="https://releases.diabrowser.com/release/Dia-from-88065-to-88214.delta" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" sparkle:deltaFrom="88065" length="21850370" type="application/octet-stream" sparkle:edSignature="Rjv/ZlPLWz3oaEVyVaubuwnFE9spNikCf+onUs5bdqRpGzMkaRS0b0DbwpkFemANPSHJGRp4FGoQmQmOHNcHAg=="></enclosure>
                
                <enclosure url="https://releases.diabrowser.com/release/Dia-from-87750-to-88214.delta" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" sparkle:deltaFrom="87750" length="132271078" type="application/octet-stream" sparkle:edSignature="rZ8EjJbFKSmjGbfnDMxHoblIoDT8HkJLM+Ax3e9aK4T2X3fjqwO1wVcJbcC1fOajaHN1ULBij+JFKoHx6/h3BQ=="></enclosure>
                
                <enclosure url="https://releases.diabrowser.com/release/Dia-from-87649-to-88214.delta" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" sparkle:deltaFrom="87649" length="132644306" type="application/octet-stream" sparkle:edSignature="vyt00dO1St/yp/0xU4c1lkSjCIa1hsmispDNUAoh/N4rkcWjrDJee6yrQMve74LgmQlxLWmBKybZg3X6bhjkCg=="></enclosure>
            
            </deltas>
        
        </item>
    
    </channel>

</rss>
"""#
}
