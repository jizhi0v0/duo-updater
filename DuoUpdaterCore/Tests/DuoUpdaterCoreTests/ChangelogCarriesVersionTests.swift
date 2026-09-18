import Foundation
import Testing

@testable import DuoUpdaterCore

/// `Changelog.carries(version:)` — the question "does this page know that version
/// exists yet", which is what keeps a snapshot fetched inside a vendor's
/// feed-before-page window from being filed as that version's notes forever. See
/// the method's doc comment and `ChangelogDiskCache`'s for the releases that cost.
struct ChangelogCarriesVersionTests {

    private static func log(_ versions: String...) -> Changelog {
        Changelog(entries: versions.map {
            Changelog.Entry(version: $0, date: nil, items: ["A change"])
        })
    }

    @Test func aPageShowingTheVersionCarriesIt() {
        #expect(Self.log("5.0.1", "5.0", "4.8.11").carries(version: "5.0.1"))
    }

    /// CleanShot X on 2026-09-18: the feed offered 5.0.1 and the page, fetched 9
    /// minutes before the vendor published it, topped out at 5.0.
    @Test func aPageThatStopsShortOfTheVersionDoesNotCarryIt() {
        #expect(!Self.log("5.0", "4.8.11", "4.8.10").carries(version: "5.0.1"))
    }

    /// The vendor moved on while our key stayed put — nothing to re-read for.
    @Test func aPageAheadOfTheVersionCarriesIt() {
        #expect(Self.log("5.1", "5.0.1", "5.0").carries(version: "5.0.1"))
    }

    /// Judged over the whole page, not just its first entry: a page carrying two
    /// trains is newest-first within a train, not across them.
    @Test func beingAheadAnywhereOnThePageIsEnough() {
        #expect(Self.log("1.104.2", "2.4", "2.3").carries(version: "2.4"))
    }

    /// A spelling difference is not a missing version.
    @Test func aDifferentSpellingOfTheSameVersionCarriesIt() {
        #expect(Self.log("v5.0.1").carries(version: "5.0.1"))
        #expect(Self.log("2.4").carries(version: "2.4.0.0"))
    }

    /// Nothing version-shaped to compare against: Figma titles its entries (its
    /// feed is product announcements with no per-entry app version) and Cursor
    /// dates them. Not judged rather than judged wrongly. NOT Notion, whose active
    /// `.notionPageChunk` recipe numbers its versions — see `carries`'s own doc
    /// comment for why naming it here would point a reader at the wrong case.
    @Test func aPageWithNoVersionNumbersIsNeverBehind() {
        #expect(Self.log("AI credit user limits", "Sep 10, 2026").carries(version: "3.21.13"))
        #expect(Changelog(entries: []).carries(version: "3.21.13"))
    }

    /// And the same when it is the KEY that isn't version-shaped — Xcode's
    /// "27.2 beta 1 (27B5019j)".
    @Test func aVersionThatIsNotVersionShapedIsNeverJudged() {
        #expect(Self.log("Xcode 27.2 Beta").carries(version: "27.2 beta 1 (27B5019j)"))
    }
}
