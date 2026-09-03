import Testing
import Foundation
@testable import DuoUpdaterCore

/// #255: a check round publishes from a scan snapshot taken minutes earlier, and
/// must not revert a row that moved while it ran — whoever moved it.
@Suite("CheckRoundWriteBack")
struct CheckRoundWriteBackTests {

    /// `InstalledApp.id` is the bundle PATH, not the bundle id.
    private func id(_ name: String) -> String { "/Applications/\(name).app" }

    private func result(_ name: String, installed: String, offering: String?) -> UpdateResult {
        let app = InstalledApp(
            name: name, bundleID: name,
            shortVersion: installed, buildVersion: installed,
            path: URL(fileURLWithPath: "/Applications/\(name).app"),
            isMASApp: false, sparkleFeedURL: nil)
        guard let offering else {
            return UpdateResult(app: app, remote: nil, status: .upToDate)
        }
        let remote = RemoteVersion(
            shortVersion: offering, version: offering,
            downloadURL: URL(string: "https://example.com/\(name).dmg"),
            downloadSize: nil, sourceName: "Sparkle")
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: offering))
    }

    // MARK: - The bug

    /// The round scanned Foo at 1.0 and wants to publish "1.0, update to 2.0".
    /// Something landed 2.0 while it ran. The round must not revert it.
    @Test("a row that moved during the round is not reverted")
    func movedRowSurvives() {
        let baseline = [result("Foo", installed: "1.0", offering: "2.0")]
        let live     = [result("Foo", installed: "2.0", offering: nil)]
        let fromRound = [result("Foo", installed: "1.0", offering: "2.0")]

        let published = CheckRoundWriteBack.publishing(
            fromRound, changedSince: baseline, live: live)

        #expect(published[0].app.shortVersion == "2.0")
        #expect(published[0].hasUpdate == false)
    }

    /// The pre-fix behaviour, pinned: with the live list identical to the baseline
    /// the round wins, which is what made #255. If someone wires the baseline to
    /// always equal `live`, this suite stays green — so the test below
    /// (`unmovedRowTakesTheRoundsVerdict`) is what holds the other direction.
    @Test("a row nobody touched takes the round's fresh verdict")
    func unmovedRowTakesTheRoundsVerdict() {
        let stale = result("Bar", installed: "3.0", offering: nil)
        let published = CheckRoundWriteBack.publishing(
            [result("Bar", installed: "3.0", offering: "4.0")],
            changedSince: [stale], live: [stale])

        #expect(published[0].hasUpdate)
        #expect(published[0].remote?.shortVersion == "4.0")
    }

    // MARK: - Why it is a diff and not a list of our own write sites

    /// The writer is irrelevant. These are the paths an enumeration missed: a
    /// staged relaunch begun BEFORE the round, a quit-handoff swap landing minutes
    /// late, a channel-switch recheck off an FS watcher, and an app's own updater
    /// (not our code at all). Each shows up here only as "the row differs".
    @Test("any writer is covered, because none is named", arguments: [
        "staged relaunch started before the round",
        "quit-handoff swap landing late",
        "channel switch recheck",
        "the app's own updater",
    ])
    func writerIsIrrelevant(_ writer: String) {
        let baseline = [result("Foo", installed: "1.0", offering: "2.0")]
        let live     = [result("Foo", installed: "2.0", offering: nil)]

        let published = CheckRoundWriteBack.publishing(
            [result("Foo", installed: "1.0", offering: "2.0")],
            changedSince: baseline, live: live)

        #expect(published[0].app.shortVersion == "2.0", "\(writer) must be covered")
    }

    /// Intent to change is not change. A click that failed, was cancelled, or
    /// applied nothing leaves the row untouched — so it diffs to nothing and the
    /// round's fresh verdict wins. The marking design got this wrong: it froze the
    /// row on intent and held back a good check result.
    @Test("a failed install does not freeze the row")
    func failedInstallDoesNotFreezeTheRow() {
        // Row errored last round; the user clicked Update and it failed, so the row
        // never moved. This round's check succeeded and found 3.0.
        let errored = result("Foo", installed: "1.0", offering: nil)
        let published = CheckRoundWriteBack.publishing(
            [result("Foo", installed: "1.0", offering: "3.0")],
            changedSince: [errored], live: [errored])

        #expect(published[0].hasUpdate)
        #expect(published[0].remote?.shortVersion == "3.0")
    }

    // MARK: - Scope

    @Test("only the moved row is held back")
    func onlyMovedRowsAreHeldBack() {
        let baseline = [
            result("Foo", installed: "1.0", offering: "2.0"),
            result("Bar", installed: "3.0", offering: nil),
        ]
        let live = [
            result("Foo", installed: "2.0", offering: nil),   // moved
            result("Bar", installed: "3.0", offering: nil),   // untouched
        ]
        let fromRound = [
            result("Foo", installed: "1.0", offering: "2.0"),
            result("Bar", installed: "3.0", offering: "4.0"), // fresh verdict
        ]

        let published = CheckRoundWriteBack.publishing(
            fromRound, changedSince: baseline, live: live)

        #expect(published[0].app.shortVersion == "2.0")
        #expect(published[1].remote?.shortVersion == "4.0")
    }

    /// A status change with no version change still counts as movement — a row that
    /// became `.error`, or picked up a restart, was written by someone.
    @Test("a status-only change counts as movement")
    func statusOnlyChangeCounts() {
        let baseline = [result("Foo", installed: "1.0", offering: "2.0")]
        let live     = [result("Foo", installed: "1.0", offering: nil)]

        let published = CheckRoundWriteBack.publishing(
            [result("Foo", installed: "1.0", offering: "2.0")],
            changedSince: baseline, live: live)

        #expect(published[0].hasUpdate == false)
    }

    @Test("row order and count are the round's")
    func shapeIsPreserved() {
        let baseline = ["A", "B", "C"].map { result($0, installed: "1", offering: "2") }
        let live = [result("B", installed: "2", offering: nil)]
        let published = CheckRoundWriteBack.publishing(
            ["A", "B", "C"].map { result($0, installed: "1", offering: "2") },
            changedSince: baseline, live: live)

        #expect(published.map(\.id) == ["A", "B", "C"].map(id))
    }

    /// A row missing from the live list keeps the round's copy rather than
    /// vanishing: dropping it would make the app disappear from the list.
    @Test("a row missing from the live list is kept, not dropped")
    func missingLiveRowFallsBack() {
        let published = CheckRoundWriteBack.publishing(
            [result("Foo", installed: "1.0", offering: "2.0")],
            changedSince: [result("Foo", installed: "1.0", offering: "2.0")],
            live: [])

        #expect(published.count == 1)
        #expect(published[0].id == id("Foo"))
    }

    /// A row absent from the baseline but present live appeared during the round —
    /// the snapshot never described it, so the live copy wins.
    @Test("a row that appeared during the round is taken live")
    func rowAppearingMidRoundIsTakenLive() {
        let published = CheckRoundWriteBack.publishing(
            [result("Foo", installed: "1.0", offering: "2.0")],
            changedSince: [],
            live: [result("Foo", installed: "2.0", offering: nil)])

        #expect(published[0].app.shortVersion == "2.0")
    }

    /// The overwhelmingly common case: nothing moved, so every row is the round's.
    @Test("an untouched round publishes exactly what it checked")
    func quietRoundIsIdentity() {
        let settled = ["A", "B"].map { result($0, installed: "1", offering: nil) }
        let fromRound = [
            result("A", installed: "1", offering: "2"),
            result("B", installed: "1", offering: nil),
        ]
        let published = CheckRoundWriteBack.publishing(
            fromRound, changedSince: settled, live: settled)

        #expect(published.map(\.hasUpdate) == fromRound.map(\.hasUpdate))
    }
}
