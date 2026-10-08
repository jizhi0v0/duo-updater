import Testing
import Foundation
@testable import DuoUpdaterCore

/// AppCleaner (`freemacsoft.net/appcleaner/updates.xml`) writes September as
/// `Sept` in its RFC822 `<pubDate>` (`Tue, 22 Sept 2026 12:00:00 +0200`), and
/// MacWhisper's appcast does too. ICU reads `Sep` and `September` there but not
/// `Sept`, so those releases had no date in the Release Log.
///
/// `appCleanerFeed` is the live feed verbatim, fetched 2026-10-08 (all four
/// items). The MacWhisper strings are the two `Sept` `<pubDate>`s in
/// `macwhisper-site.vercel.app/appcast.xml` on the same day, verbatim.
struct SparkleSeptPubDateTests {

    // MARK: - Through the real parser

    @Test func appCleanerReleaseHistoryHasEveryRelease() {
        let items = SparkleAppcastParser.parse(Data(Self.appCleanerFeed.utf8))
        #expect(items.map(\.pubDate) == [
            "Wed, 21 Sept 2016 15:00:00 +0200",
            "Tue, 2 February 2021 13:30:00 +0200",
            "Wed, 5 July 2023 14:00:00 +0200",
            "Tue, 22 Sept 2026 12:00:00 +0200",
        ])
        let history = SparkleAppcastSource.releaseHistory(from: items)
        #expect(history.map(\.version) == ["3.4", "3.6.0", "3.6.8", "3.7.0"])
        #expect(history.map(\.publishedAt) == [
            Date(timeIntervalSince1970: 1_474_462_800),  // 2016-09-21T13:00:00Z
            Date(timeIntervalSince1970: 1_612_265_400),  // 2021-02-02T11:30:00Z
            Date(timeIntervalSince1970: 1_688_558_400),  // 2023-07-05T12:00:00Z
            Date(timeIntervalSince1970: 1_790_071_200),  // 2026-09-22T10:00:00Z
        ])
        #expect(history.allSatisfy { $0.vendorDay == nil })
    }

    // MARK: - The date shape itself

    @Test func septIsReadAsSeptemberToTheMinute() {
        let cases: [(String, TimeInterval)] = [
            ("Tue, 22 Sept 2026 12:00:00 +0200", 1_790_071_200),
            ("Wed, 21 Sept 2016 15:00:00 +0200", 1_474_462_800),
            ("Wed, 19 Sept 2024 09:00:00 +0000", 1_726_736_400),  // MacWhisper 9.15
            ("Wed, 4 Sept 2024 16:00:00 +0000", 1_725_465_600),   // MacWhisper 9.13
        ]
        for (raw, epoch) in cases {
            let date = Date(timeIntervalSince1970: epoch)
            #expect(ReleaseDate.parseWithPrecision(raw)
                == ReleaseDate.Parsed(date: date, precision: .minute), "\(raw)")
            #expect(ReleaseDate.publishedFields(from: raw).publishedAt == date, "\(raw)")
            #expect(ReleaseDate.parse(raw) == date, "\(raw)")
        }
    }

    /// `Sept` is read only as the whole month word: no other spelling is
    /// rewritten, and the rewrite does not make anything else parse.
    @Test func nearMissesOfSeptStayUnparsed() {
        let rejects = [
            "Tue, 22 Sept. 2026 12:00:00 +0200",   // abbreviation dot
            "Tue, 22 Septe 2026 12:00:00 +0200",   // longer prefix
            "Tue, 22 sept 2026 12:00:00 +0200",    // lowercase
            "Tue, 22 Sept 2026",                   // no time
            "Tue, 22 Sept 2026 12:00:00",          // no zone
            "Tue, 31 Sept 2026 12:00:00 +0200",    // no such day
        ]
        for raw in rejects {
            #expect(ReleaseDate.parseWithPrecision(raw) == nil, "\(raw)")
            #expect(ReleaseDate.parse(raw) == nil, "\(raw)")
        }
    }

    /// The rewrite runs only after every formatter has rejected the string as
    /// written, so nothing that already parsed may change — pinned here at the
    /// exact instant and precision, including the full month names AppCleaner's
    /// other items use.
    @Test func shapesThatAlreadyParsedKeepTheirInstantAndPrecision() {
        let cases: [(String, TimeInterval, ReleaseDate.Precision)] = [
            ("Wed, 24 Jun 2026 17:07:24 +0000", 1_782_320_844, .minute),
            ("Wed, 24 Jun 2026 10:07:24 PDT", 1_782_320_844, .minute),
            ("24 Jun 2026 17:07:24 +0000", 1_782_320_844, .minute),
            ("Sun, 27 Sep 2026 16:09:46 GMT+0200", 1_790_518_186, .minute),
            ("Tue, 22 Sep 2026 12:00:00 +0200", 1_790_071_200, .minute),
            ("Tue, 22 September 2026 12:00:00 +0200", 1_790_071_200, .minute),
            ("Tue, 2 February 2021 13:30:00 +0200", 1_612_265_400, .minute),
            ("Wed, 5 July 2023 14:00:00 +0200", 1_688_558_400, .minute),
            ("2026-06-24T17:07:24Z", 1_782_320_844, .minute),
            ("2026-06-24T17:07:24.500Z", 1_782_320_844.5, .minute),
            ("2026-06-24T17:07:24", 1_782_320_844, .minute),
            ("1782320844", 1_782_320_844, .minute),
            ("2026-08-31", 1_788_134_400, .day),
            ("20260831", 1_788_134_400, .day),
            ("Oct 2, 2026 at 9:47:01\u{202F}PM", 1_790_899_200, .day),
        ]
        for (raw, epoch, precision) in cases {
            #expect(ReleaseDate.parseWithPrecision(raw)
                == ReleaseDate.Parsed(date: Date(timeIntervalSince1970: epoch), precision: precision),
                "\(raw)")
        }
    }

    // MARK: - Fixture

    static let appCleanerFeed = #"""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
	<channel>
	<title>AppCleaner Changelog</title>
	<link>https://freemacsoft.net/appcleaner/updates.xml</link>
	<description>Most recent changes with links to updates.</description>
	<language>en</language>
	<item>
		<title>Version 3.4</title>
		<sparkle:minimumSystemVersion>10.10.0</sparkle:minimumSystemVersion>
		<sparkle:releaseNotesLink>https://freemacsoft.net/appcleaner/releasenotes.html</sparkle:releaseNotesLink>
		<pubDate>Wed, 21 Sept 2016 15:00:00 +0200</pubDate>
		<enclosure url="https://freemacsoft.net/downloads/AppCleaner_3.4.zip"
			sparkle:version="3804"
			sparkle:shortVersionString="3.4"
			length="2570378"
			type="application/octet-stream"
			sparkle:dsaSignature="MCwCFEgJmatSNBcrwPYL1872nZrL6UFrAhQeCO4IyPyJQ6EZpUW0hI7OtFxzBw==" />
	</item>
	<item>
		<title>Version 3.6</title>
		<sparkle:minimumSystemVersion>10.13</sparkle:minimumSystemVersion>
		<sparkle:releaseNotesLink>https://freemacsoft.net/appcleaner/releasenotes.html</sparkle:releaseNotesLink>
		<pubDate>Tue, 2 February 2021 13:30:00 +0200</pubDate>
		<enclosure url="https://freemacsoft.net/downloads/AppCleaner_3.6.zip"
			sparkle:version="4070"
			sparkle:shortVersionString="3.6.0"
			length="3976206"
			type="application/octet-stream"
			sparkle:dsaSignature="MC0CFQDMajPNoyMAPN4z4OBRHkB8sd9daQIUZ5hvkJT1KDpnogBAiI1J0m32MWA=" />
	</item>
	<item>
		<title>Version 3.6.8</title>
		<sparkle:minimumSystemVersion>10.14</sparkle:minimumSystemVersion>
		<sparkle:releaseNotesLink>https://freemacsoft.net/appcleaner/releasenotes.html</sparkle:releaseNotesLink>
		<pubDate>Wed, 5 July 2023 14:00:00 +0200</pubDate>
		<enclosure url="https://rawcdn.githack.com/freemacsoft/appcleaner/8c3b52858a454d14fba343cf565ff710eaff4bcd/AppCleaner_3.6.8.zip"
			sparkle:version="4332"
			sparkle:shortVersionString="3.6.8"
			length="4165467"
			type="application/octet-stream"
			sparkle:dsaSignature="MCwCFE/LlszSZT/8CCCFMk0OGTI9p1GuAhRFcJhJkDEaA0DVD4MQPd5xBcLewA=="
			sparkle:edSignature="BLc+yGKZ/dIjNvfbb7YtMYOjJqYK5d756tyfn9PiUodhuohjNLBcz8J7RA6cKOHL+SLu7XJixLwVDD4BLbjrDQ=="/>
	</item>
	<item>
		<title>Version 3.7</title>
		<sparkle:minimumSystemVersion>15.6</sparkle:minimumSystemVersion>
		<sparkle:releaseNotesLink>https://freemacsoft.net/appcleaner/releasenotes.html</sparkle:releaseNotesLink>
		<pubDate>Tue, 22 Sept 2026 12:00:00 +0200</pubDate>
		<enclosure url="https://github.com/freemacsoft/appcleaner/releases/download/3.7/AppCleaner_3.7.zip"
			sparkle:version="4485"
			sparkle:shortVersionString="3.7.0"
			length="4148798"
			type="application/octet-stream"
			sparkle:dsaSignature="MC0CFQC+yl8Th1+cWUwpSidn+FjAddiNEAIUSxu+VvJJz3kvke7FOo1Vm2i42Ps="
			sparkle:edSignature="9qwhKaR0Cu4WSxlwRTsmxSE2YsfkmDmkIKB+yZEDWmb+SSGFSHeIcJN6I8Emb7nXgyuSr/6rL35VwXzx4V9+CA=="/>
	</item>
	</channel>
</rss>
"""#
}
