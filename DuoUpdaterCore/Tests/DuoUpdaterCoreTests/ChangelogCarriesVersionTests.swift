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

    /// And the same when it is the KEY that isn't version-shaped and the page
    /// spells its entries another way — Xcode's "27.2 beta 1 (27B5019j)" under a
    /// page whose entry reads "Xcode 27" (the real `xcode-27` and `xcode-26_6`
    /// notes decode to "Xcode 27" and "Xcode 26.6", 2026-10-16), and AdGuard's
    /// nightly, whose page lists build numbers. Judging these would re-read them
    /// every provisional window.
    @Test func aVersionThatIsNotVersionShapedIsNotJudgedAgainstOtherSpellings() {
        #expect(Self.log("Xcode 27.2 Beta").carries(version: "27.2 beta 1 (27B5019j)"))
        #expect(Self.log("Xcode 27").carries(version: "27.2 beta 1 (27B5019j)"))
        #expect(Self.log("Xcode 26.6").carries(version: "26.6 RC 2 (17F113)"))
        #expect(Self.log("2.20.0.2625", "2.20.0.2619").carries(version: "2.20 Nightly 10"))
    }

    /// AdGuard's beta feed and versions page both spell `2.20 RC 1`. A page that
    /// tops out at RC 1 has not published RC 2 — the CleanShot shape, for a
    /// version `comparableMarketingVersion` cannot read. Entry versions copied
    /// from the beta page (2026-10-16).
    ///
    /// Mutation that turns this red: returning true for every version that is
    /// not version-shaped, as before.
    @Test func aPageSpellingEntriesLikeTheVersionIsJudgedByTheWholeString() {
        let beta = Self.log("2.20 RC 1", "2.20 beta 3", "2.19 RC", "2.17 beta")
        #expect(!beta.carries(version: "2.20 RC 2"))
        #expect(beta.carries(version: "2.20 RC 1"))
        #expect(beta.carries(version: "2.20  rc 1 "))
        #expect(beta.carries(version: "2.20 beta 3"))
        #expect(!beta.carries(version: "2.20 beta 4"))
    }

    /// The two other apps with such versions on the machine this was written
    /// on spell their entries exactly as their versions, so they carry them and
    /// are not re-read (cached entries, 2026-10-16).
    @Test func sublimeAndHyperFramesStillCarryTheirOwnVersion() {
        #expect(Self.log("Build 4215", "Build 4213").carries(version: "Build 4215"))
        #expect(!Self.log("Build 4213", "Build 4200").carries(version: "Build 4215"))
        #expect(Self.log("b272").carries(version: "b272"))
    }
}
