import Foundation
import Testing
@testable import DuoUpdaterCore

/// A row an interrupted install left: shown as usual, with the way back in
/// place of its update (§5.7, Q7).
@Suite struct InterruptedInstallRowTests {

    private let path = URL(fileURLWithPath: "/Applications/ZZFixture-Interrupted.app")

    private func interrupted(
        at path: URL, oldVersion: String? = "1.0", damage: InstallJournal.Damage = .missing
    ) -> InstallJournal.InterruptedInstall {
        InstallJournal.InterruptedInstall(
            id: UUID().uuidString, appID: path.path, appName: "ZZFixture-Interrupted",
            bundleID: "com.example.zzfixture.interrupted", appPath: path,
            oldVersion: oldVersion, oldBuild: "100", route: "homebrew", damage: damage,
            restoreFrom: nil, iconSource: nil)
    }

    /// With a copy to restore from, Restore — over the update the row has, and
    /// over the user's verdicts on it.
    /// Mutation: put the rung below `isIgnored` → an ignored broken app reads
    /// `.ignored`, red.
    @Test(arguments: [false, true])
    func aWayBackIsRestore(ignored: Bool) {
        let state = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            interruptedHasWayBack: true,
            isIgnored: ignored))
        #expect(state == .interruptedInstall(.restore))
        #expect(!state.offersUpdate)
    }

    /// No copy kept: Reinstall, when the update runs in one click; otherwise
    /// nothing to click.
    /// Mutation: drop the `.autoInstall` condition → a major upgrade (whose
    /// licence warning the popover owns) reads `.reinstall`, red.
    @Test func noWayBackIsReinstallOnlyForAOneClickUpdate() {
        func state(_ status: UpdateStatus, route: UpdateRoute) -> RowActionState {
            RowAction.state(for: RowActionFacts(
                status: status, interruptedHasWayBack: false, route: route))
        }
        #expect(state(.updateAvailable(latest: "2.0"), route: .autoInstall) == .interruptedInstall(.reinstall))
        #expect(state(.updateAvailable(latest: "2.0"), route: .majorUpgrade) == .interruptedInstall(.noWayBack))
        #expect(state(.unknown, route: .autoInstall) == .interruptedInstall(.noWayBack))
    }

    /// The Restore (or Reinstall) running on the row is its install stage, and
    /// a row that is not interrupted keeps its update.
    @Test func theStageAndAnUntouchedRowAreUnchanged() {
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"), installStage: .installing,
            interruptedHasWayBack: true)) == .installing(.installing))
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"))) == .updateAvailable(.autoInstall))
    }

    /// The table is read under the row's id, the install path.
    /// Mutation: assemble without `tables.interrupted` → red.
    @Test func theTableIsReadUnderTheRowsPath() {
        let app = InstalledApp(
            name: "ZZFixture-Interrupted", bundleID: "com.example.zzfixture.interrupted",
            shortVersion: "1.0", buildVersion: nil, path: path, isMASApp: false, sparkleFeedURL: nil)
        let result = UpdateResult(app: app, remote: nil, status: .upToDate)
        let facts = RowActionFacts.assemble(
            for: result, tables: RowStateTables(interrupted: [result.id: true]),
            isIgnored: false, isVersionSkipped: false, route: .autoInstall)
        #expect(RowAction.state(for: facts) == .interruptedInstall(.restore))
    }

    /// "v<old version> · Last update was interrupted" outranks every other line.
    @Test func theVersionLineNamesTheVersionFromBefore() {
        #expect(RowVersionLine.state(
            staged: nil, armedWithUnknownVersion: true, pendingBatchRestartMarketing: "1.5",
            restartFrom: nil, downgradeVersion: nil,
            interrupted: interrupted(at: path)) == .interrupted(oldVersion: "1.0"))
        #expect(RowVersionLine.state(
            staged: nil, armedWithUnknownVersion: false, pendingBatchRestartMarketing: nil,
            restartFrom: nil, downgradeVersion: nil) == .status)
    }

    /// A missing app has no scanned row, so it gets one from the journal; a
    /// broken one the scan still found keeps its own. Two records of one app
    /// are one row.
    /// Mutation: drop the `paths` check → the broken app is listed twice, red.
    @Test func aMissingAppGetsAStandInAndAScannedOneDoesNot() {
        let broken = URL(fileURLWithPath: "/Applications/ZZFixture-Broken.app")
        let scanned = [UpdateResult(
            app: InstalledApp(
                name: "ZZFixture-Broken", bundleID: nil, shortVersion: "1.5", buildVersion: nil,
                path: broken, isMASApp: false, sparkleFeedURL: nil),
            remote: nil, status: .upToDate)]
        let rows = InterruptedInstallRows.standIns(
            [interrupted(at: path), interrupted(at: path, oldVersion: "0.9"),
             interrupted(at: broken, damage: .signatureBroken)],
            scanned: scanned)
        #expect(rows.count == 1)
        let row = try? #require(rows.first)
        #expect(row?.app.path == path)
        #expect(row?.app.name == "ZZFixture-Interrupted")
        #expect(row?.app.shortVersion == "1.0")
        #expect(row?.app.buildVersion == "100")
        #expect(row?.status == .unknown)
    }
}
