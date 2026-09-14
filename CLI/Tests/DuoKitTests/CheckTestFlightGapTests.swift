import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// What `duo check` says when it could not read TestFlight's side.
///
/// Reproduced 2026-09-13 on macOS 27.0 from a `launchctl submit` job: a beta the
/// same binary reported an update for from a terminal came back as "Everything is
/// up to date.", exit 0, nothing on stderr — the store's `open` was refused and
/// nothing said so.
///
/// Every input here is passed in — whether each store exists, whether it opened,
/// what Full Disk Access reads as — so no case asks the machine running it what it
/// has granted. Each case names the mutation it exists to catch.
@Suite struct CheckTestFlightGapTests {

    /// stdout and stderr in the order a user reads them.
    private final class Transcript {
        var lines: [(stream: String, text: String)] = []
        var out: [String] { lines.filter { $0.stream == "out" }.map(\.text) }
        var err: [String] { lines.filter { $0.stream == "err" }.map(\.text) }
    }

    private func run(
        _ rows: [Check.Row], gap: Check.TestFlightGap?, scanAbandoned: Bool = false
    ) -> (status: Int32, transcript: Transcript) {
        let t = Transcript()
        let status = Check.finish(
            rows, command: "check", json: false, scanAbandoned: scanAbandoned, testFlightGap: gap,
            out: { t.lines.append(("out", $0)) },
            err: { t.lines.append(("err", $0)) })
        return (status, t)
    }

    private func row(_ name: String, hasUpdate: Bool) -> Check.Row {
        Check.Row(
            name: name, bundleID: "com.zzfixture.\(name.lowercased())",
            path: "/Applications/ZZFixture-\(name).app",
            installedVersion: "1.0", installedBuild: "1",
            latestVersion: hasUpdate ? "1.1" : "1.0", latestBuild: nil,
            source: "Sparkle", status: hasUpdate ? "update 1.1" : "up-to-date",
            hasUpdate: hasUpdate, hidden: false, route: nil)
    }

    /// The reproduced case: detection on, the store on disk, its open refused,
    /// Full Disk Access missing. The beta comes back `testflight` with no version
    /// and is filtered out, so the rows are empty.
    private func refusedStore(fullDiskAccess: TCCAuthStatus = .denied) -> Check.TestFlightGap? {
        Check.testFlightGap(
            readsStore: true, storeOpened: false, storeExists: true,
            announcementsOpened: false, announcementsExist: true,
            fullDiskAccess: fullDiskAccess, betasPresent: true,
            sourcesAdmitTestFlight: true)
    }

    /// Mutations: drop the `unread` branch (no gap → no note, old summary);
    /// make `emitText` print the up-to-date line for `.verdictsUnproven`; emit
    /// the note before the rows (order).
    @Test func aRefusedStoreIsSaidAndNothingIsCalledUpToDate() throws {
        let gap = refusedStore()
        #expect(gap == .storeUnread(fullDiskAccessMissing: true))

        let (status, t) = run([], gap: gap)

        #expect(!t.lines.contains { $0.text.localizedCaseInsensitiveContains("up to date") })
        #expect(t.out == ["No updates found, but not every app could be checked in full (see below)."])
        let note = try #require(t.err.first)
        #expect(t.err.count == 1)
        #expect(note.hasPrefix("duo: TestFlight betas were not checked — without Full Disk Access,"))
        #expect(note.contains("Privacy & Security ▸ Full Disk Access"))
        // After the result, never before it.
        #expect(t.lines.map(\.stream) == ["out", "err"])
        // Exit status is not moved by the gap — see `finish`.
        #expect(status == 0)
    }

    /// Rows still print, the note still follows, and the exit status still says
    /// "there is something to do".
    ///
    /// Mutation: return a distinct status whenever a gap is present.
    @Test func theExitStatusIsStillDecidedByTheRows() {
        let (withUpdate, t) = run([row("Updated", hasUpdate: true)], gap: refusedStore())
        #expect(withUpdate == 1)
        #expect(t.err.count == 1)
        #expect(t.out.last?.contains("1 update available of 1 app shown.") == true)

        let (withNothing, _) = run([], gap: refusedStore())
        #expect(withNothing == 0)
    }

    /// Full Disk Access is named only when the app's own test says it is missing.
    /// Granted, or unreadable, and the store still did not open (a timed-out open):
    /// no cause is offered.
    ///
    /// Mutation: `let missing = true`.
    @Test func fullDiskAccessIsBlamedOnlyWhenItIsMissing() throws {
        for status in [TCCAuthStatus.granted, .unknown] {
            let gap = refusedStore(fullDiskAccess: status)
            #expect(gap == .storeUnread(fullDiskAccessMissing: false), "\(status)")
            let (_, t) = run([], gap: gap)
            let note = try #require(t.err.first)
            #expect(!note.contains("Full Disk Access"), "\(status): \(note)")
            #expect(note.hasPrefix("duo: TestFlight betas were not checked"))
            #expect(!t.out.contains { $0.contains("up to date") })
        }
        #expect(refusedStore(fullDiskAccess: .notDetermined)
            == .storeUnread(fullDiskAccessMissing: true))
    }

    /// A Mac that has never run TestFlight has no store, and `accessible` is false
    /// for a missing store too. It must not be told its betas were missed — and a
    /// refused notification store beside it has nothing to witness.
    ///
    /// Mutations: drop `storeExists &&`; drop `storeOpened &&` from `unwitnessed`.
    @Test func noTestFlightStoreIsNotAGap() {
        let gap = Check.testFlightGap(
            readsStore: true, storeOpened: false, storeExists: false,
            announcementsOpened: false, announcementsExist: true,
            fullDiskAccess: .denied, betasPresent: true,
            sourcesAdmitTestFlight: true)
        #expect(gap == nil)

        let (status, t) = run([], gap: gap)
        #expect(t.out == ["Everything is up to date."])
        #expect(t.err.isEmpty)
        #expect(status == 0)
    }

    /// The store opened but TestFlight's notifications did not: verdicts the
    /// store gave stand unwitnessed, so "up to date" is not ours to say either.
    ///
    /// Mutation: drop the `unwitnessed` branch.
    @Test func aRefusedNotificationStoreIsSaid() throws {
        let gap = Check.testFlightGap(
            readsStore: true, storeOpened: true, storeExists: true,
            announcementsOpened: false, announcementsExist: true,
            fullDiskAccess: .denied, betasPresent: true,
            sourcesAdmitTestFlight: true)
        #expect(gap == .announcementsUnread(fullDiskAccessMissing: true))

        let (_, t) = run([], gap: gap)
        #expect(!t.out.contains { $0.contains("up to date") })
        let note = try #require(t.err.first)
        #expect(note.contains("can't read TestFlight's notifications"))
    }

    /// Both reads in: nothing to say, and the summary is the one it always was.
    @Test func bothReadsInIsNotAGap() {
        let gap = Check.testFlightGap(
            readsStore: true, storeOpened: true, storeExists: true,
            announcementsOpened: true, announcementsExist: true,
            fullDiskAccess: .denied, betasPresent: true,
            sourcesAdmitTestFlight: true)
        #expect(gap == nil)
    }

    /// Nothing checked looks like a beta: every refusal is beside the point.
    ///
    /// Mutation: drop `guard betasPresent`.
    @Test func noBetasNoNote() {
        let gap = Check.testFlightGap(
            readsStore: true, storeOpened: false, storeExists: true,
            announcementsOpened: false, announcementsExist: true,
            fullDiskAccess: .denied, betasPresent: false,
            sourcesAdmitTestFlight: true)
        #expect(gap == nil)
    }

    /// Detection off keeps exactly what it printed before this type existed: the
    /// usual summary, then its own note.
    ///
    /// Mutation: have `leavesVerdictsUnproven` return true for `.detectionOff`.
    @Test func detectionOffKeepsItsSummaryAndNote() {
        let gap = Check.testFlightGap(
            readsStore: false, storeOpened: false, storeExists: true,
            announcementsOpened: false, announcementsExist: true,
            fullDiskAccess: .denied, betasPresent: true,
            sourcesAdmitTestFlight: true)
        #expect(gap == .detectionOff)

        let (_, t) = run([], gap: gap)
        #expect(t.out == ["Everything is up to date."])
        #expect(t.err == [
            "duo: TestFlight betas were not checked — detection is off (DuoUpdater ▸ Settings ▸ General)."
        ])
    }

    /// A run filtered to sources that never answer as TestFlight shows no beta
    /// row, so it has no TestFlight gap to report — not the refusal, and not
    /// detection off either.
    ///
    /// Mutations: drop `sourcesAdmitTestFlight` from the guard; drop
    /// `sources.isEmpty ||` from `admitsTestFlight`.
    @Test func aSourceFilterThatCannotShowBetasHasNoGap() {
        for readsStore in [true, false] {
            let gap = Check.testFlightGap(
                readsStore: readsStore, storeOpened: false, storeExists: true,
                announcementsOpened: false, announcementsExist: true,
                fullDiskAccess: .denied, betasPresent: true,
                sourcesAdmitTestFlight: Check.admitsTestFlight(["homebrew", "vendor"]))
            #expect(gap == nil, "readsStore=\(readsStore)")
        }
        let (_, t) = run([], gap: nil)
        #expect(t.out == ["Everything is up to date."])
        #expect(t.err.isEmpty)

        #expect(Check.admitsTestFlight([]))
        #expect(Check.admitsTestFlight(["testflight"]))
        #expect(Check.admitsTestFlight(["sparkle", "testflight"]))
        #expect(!Check.admitsTestFlight(["app store"]))
    }

    /// A scan given up on checked nothing; its stderr line has already said so,
    /// and the summary must not turn that into "everything is current". It wins
    /// over a TestFlight gap, and the exit status stays 0.
    ///
    /// Mutation: pass `scanAbandoned` through as false / drop the `.scanAbandoned`
    /// arm's text.
    @Test func anAbandonedScanIsNotCalledUpToDate() {
        let (status, t) = run([], gap: nil, scanAbandoned: true)
        #expect(t.out == ["No apps were checked: the app scan was abandoned (see above)."])
        #expect(!t.lines.contains { $0.text.localizedCaseInsensitiveContains("up to date") })
        #expect(t.err.isEmpty)
        #expect(status == 0)
    }

    /// `duo list` after an abandoned scan: nothing was looked at, which "No apps
    /// found." would call an empty Mac. Its exit status stays 0, and a scan that
    /// finished with nothing still says "No apps found."
    ///
    /// Mutation: have the `list` branch of `emitText` ignore `incomplete`.
    @Test func anAbandonedListIsNotCalledEmpty() {
        func list(scanAbandoned: Bool) -> (Int32, Transcript) {
            let t = Transcript()
            let status = Check.finish(
                [], command: "list", json: false, scanAbandoned: scanAbandoned, testFlightGap: nil,
                out: { t.lines.append(("out", $0)) },
                err: { t.lines.append(("err", $0)) })
            return (status, t)
        }
        let (abandonedStatus, abandoned) = list(scanAbandoned: true)
        #expect(abandoned.out == ["No apps listed: the app scan was abandoned (see above)."])
        #expect(abandoned.err.isEmpty)
        #expect(abandonedStatus == 0)

        let (emptyStatus, empty) = list(scanAbandoned: false)
        #expect(empty.out == ["No apps found."])
        #expect(emptyStatus == 0)
    }

    /// The Full Disk Access test opens files; it runs only when there is a refusal
    /// to explain.
    ///
    /// Mutation: evaluate `fullDiskAccess()` before the `guard unread || unwitnessed`.
    @Test func fullDiskAccessIsNotAskedWithoutARefusal() {
        var asked = 0
        func probe() -> TCCAuthStatus { asked += 1; return .denied }
        _ = Check.testFlightGap(
            readsStore: true, storeOpened: true, storeExists: true,
            announcementsOpened: true, announcementsExist: true,
            fullDiskAccess: probe(), betasPresent: true,
            sourcesAdmitTestFlight: true)
        #expect(asked == 0)
        _ = Check.testFlightGap(
            readsStore: true, storeOpened: false, storeExists: true,
            announcementsOpened: true, announcementsExist: true,
            fullDiskAccess: probe(), betasPresent: true,
            sourcesAdmitTestFlight: true)
        #expect(asked == 1)
    }
}
