import Testing
import Foundation
@testable import DuoUpdaterCore

/// An install error must not outlive the situation it describes.
///
/// Regression for a row that read "up to date ✓" while still carrying
/// "another DuoUpdater install is in progress (process 76712)" from an attempt
/// that had been refused minutes earlier: every write site for `installErrors`
/// is the start of *another action on that row*, so nothing on the refresh path
/// ever cleared one and the line survived until the app was relaunched.
///
/// The negative cases are the point. The obvious rule ("no update pending →
/// clear it") passes the first test and quietly breaks the rest: a networked
/// refresh blanks every row to `.unknown` first, so it would wipe every error on
/// every refresh — including the ones the user has not read yet.
private func row(_ path: String, _ status: UpdateStatus) -> UpdateResult {
    UpdateResult(
        app: InstalledApp(
            name: (path as NSString).lastPathComponent,
            bundleID: "com.example.fixture",
            shortVersion: "1.0",
            buildVersion: "1",
            path: URL(fileURLWithPath: path),
            isMASApp: false,
            sparkleFeedURL: nil),
        remote: nil,
        status: status)
}

private let noTunes = "/Users/me/Applications/noTunes.app"
private let other = "/Applications/Other.app"

@Suite("Install errors clear once the row settles")
struct SettledInstallErrorTests {

    @Test func aRowThatWentUpToDateDropsItsError() {
        let settled = UpdatePolicy.settledRowIDs(
            [noTunes], results: [row(noTunes, .upToDate)], installing: [])
        #expect(settled == [noTunes])
    }

    @Test func aRowStillOfferingTheUpdateKeepsItsReason() {
        let settled = UpdatePolicy.settledRowIDs(
            [noTunes],
            results: [row(noTunes, .updateAvailable(latest: "3.5"))],
            installing: [])
        #expect(settled.isEmpty)
    }

    /// The blanking window of a networked refresh: `performRefresh` resets every
    /// row to `.unknown` before the check answers. Treating that as "settled"
    /// would clear every error on every refresh.
    @Test func theBlankRowOfARefreshInFlightIsNotASettlement() {
        let settled = UpdatePolicy.settledRowIDs(
            [noTunes], results: [row(noTunes, .unknown)], installing: [])
        #expect(settled.isEmpty)
    }

    /// A failed check is a non-answer, not a settlement — the update it could not
    /// see may still be waiting.
    @Test func aRowWhoseCheckFailedKeepsItsError() {
        let settled = UpdatePolicy.settledRowIDs(
            [noTunes], results: [row(noTunes, .error("dns"))], installing: [])
        #expect(settled.isEmpty)
    }

    /// A row can be up to date *and* have an install running on it (a batch that
    /// re-enters, an install whose bookkeeping has landed the new version before
    /// the row is released). Clearing there would race the error that install is
    /// about to write.
    @Test func aRowMidInstallIsLeftAloneEvenWhenItLooksSettled() {
        let settled = UpdatePolicy.settledRowIDs(
            [noTunes], results: [row(noTunes, .upToDate)], installing: [noTunes])
        #expect(settled.isEmpty)
    }

    /// The managed verdicts look like settlements and are not. `UpdateChecker`
    /// reaches all three from the same "no source could answer" branch that hands
    /// everything else `.unknown` — so an App Store row whose lookup simply came
    /// back empty must keep its error, and with it the recovery buttons that
    /// `showsHelperApprovalFallback` and friends gate on that same text.
    @Test(arguments: [UpdateStatus.appStoreManaged, .toolboxManaged, .testFlightManaged])
    func managedIsANonAnswerNotASettlement(status: UpdateStatus) {
        let settled = UpdatePolicy.settledRowIDs(
            [noTunes], results: [row(noTunes, status)], installing: [])
        #expect(settled.isEmpty)
    }

    @Test func anAppThatIsNoLongerInstalledSettles() {
        let settled = UpdatePolicy.settledRowIDs(
            [noTunes], results: [row(other, .upToDate)], installing: [])
        #expect(settled == [noTunes])
    }

    /// Before the first scan there are no rows at all. That is not "every app
    /// vanished" — nothing should be cleared off an empty list.
    @Test func anEmptyRowListSettlesNothing() {
        let settled = UpdatePolicy.settledRowIDs(
            [noTunes], results: [], installing: [])
        #expect(settled.isEmpty)
    }
}

/// The same staleness, one row lower: `installNotes` renders in the same slot as
/// the error and had the same defect — "brought it to the front so its own
/// updater applies the update" stayed under a row that had long since finished
/// updating.
///
/// What makes notes harder than errors is that the dictionary carries two kinds
/// of text. `backupCurrent` writes "this update was applied without a rollback
/// point" *into the same slot*, and that one is only worth reading after the row
/// settles. Clearing notes on settle without discriminating is how that warning
/// once became unreadable to everyone. So the negative cases below — an
/// unregistered note, and a registered one whose text has since been replaced —
/// are the whole point of the rule.
@Suite("In-flight notes retract, standing facts don't")
struct RetractableNoteTests {

    private static let opened = "Opened noTunes — its own updater is applying the update."
    private static let backup = "Couldn’t back up the current version."

    @Test func aSettledRowRetractsTheNoteWeWrote() {
        let ids = UpdatePolicy.retractableNoteIDs(
            notes: [noTunes: Self.opened],
            writtenByUs: [noTunes: Self.opened],
            results: [row(noTunes, .upToDate)],
            installing: [])
        #expect(ids == [noTunes])
    }

    @Test func aNoteNobodyRegisteredIsNeverRetracted() {
        // `backupCurrent`'s warning: no registry entry, so it stands even though
        // the row is as settled as a row gets.
        let ids = UpdatePolicy.retractableNoteIDs(
            notes: [noTunes: Self.backup],
            writtenByUs: [:],
            results: [row(noTunes, .upToDate)],
            installing: [])
        #expect(ids.isEmpty)
    }

    @Test func aRegisteredNoteSomebodyElseOverwroteIsLeftAlone() {
        // We registered the hand-off note; the backup warning replaced it before
        // the row settled. Retracting on the id alone would take theirs down.
        let ids = UpdatePolicy.retractableNoteIDs(
            notes: [noTunes: Self.backup],
            writtenByUs: [noTunes: Self.opened],
            results: [row(noTunes, .upToDate)],
            installing: [])
        #expect(ids.isEmpty)
    }

    @Test func aRowStillOfferingTheUpdateKeepsTheHandOffNote() {
        // The self-updater hasn't finished; the note is still the truth.
        let ids = UpdatePolicy.retractableNoteIDs(
            notes: [noTunes: Self.opened],
            writtenByUs: [noTunes: Self.opened],
            results: [row(noTunes, .updateAvailable(latest: "2.0"))],
            installing: [])
        #expect(ids.isEmpty)
    }

    @Test func aRowMidInstallKeepsItsNote() {
        // The App Store "quit it to finish" note is written *during* the install
        // and retracted by the install itself; a rescan mustn't beat it to it.
        let ids = UpdatePolicy.retractableNoteIDs(
            notes: [noTunes: Self.opened],
            writtenByUs: [noTunes: Self.opened],
            results: [row(noTunes, .upToDate)],
            installing: [noTunes])
        #expect(ids.isEmpty)
    }

    @Test func anAppThatIsNoLongerInstalledRetracts() {
        let ids = UpdatePolicy.retractableNoteIDs(
            notes: [noTunes: Self.opened],
            writtenByUs: [noTunes: Self.opened],
            results: [row(other, .upToDate)],
            installing: [])
        #expect(ids == [noTunes])
    }

    @Test func anEmptyRegistryAsksNothingOfTheRows() {
        let ids = UpdatePolicy.retractableNoteIDs(
            notes: [noTunes: Self.backup], writtenByUs: [:], results: [], installing: [])
        #expect(ids.isEmpty)
    }
}
