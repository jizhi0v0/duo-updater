import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// What each command prints after the app scan was given up on.
///
/// `Inventory.scanIfFinished` returns nil then, and there is no longer a spelling
/// that turns that into `[]` — the one that did made every command below report
/// "nothing was looked at" as a fact about the Mac. Each case here is one of those
/// lines; `check` and `list` are in `CheckTestFlightGapTests`. Exit statuses are
/// deliberately unchanged, and the cases say so where a status is decided.
@Suite struct AbandonedScanOutputTests {

    private func app(_ name: String) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: "com.zzfixture.\(name.lowercased())",
            shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-\(name).app"),
            isMASApp: false, sparkleFeedURL: nil)
    }

    /// Naming an app after an abandoned scan — `check`/`list <app>`, `install`,
    /// `restart`, `ignore`/`unignore`/`skip`/`unskip`: the app may well be
    /// installed, so "no installed app matches" is the one thing duo cannot say.
    /// Naming none selects nothing and leaves the caller to explain.
    ///
    /// Mutation: `guard let apps` → `let apps = apps ?? []` in `Inventory.select`.
    @Test func namingAnAppAfterAnAbandonedScanDoesNotCallItMissing() throws {
        guard case .failure(let failure) = Inventory.select(nil, matching: ["ZZFixture-Named"]) else {
            Issue.record("an abandoned scan selected something")
            return
        }
        #expect(failure.description
            == "can't tell whether 'ZZFixture-Named' is installed: the app scan was abandoned (see above)")
        #expect(!failure.description.contains("no installed app matches"))

        let none = try Inventory.select(nil, matching: []).get()
        #expect(none.isEmpty)

        // A finished scan with nothing matching still says so.
        guard case .failure(let missing) = Inventory.select([app("Other")], matching: ["ZZFixture-Named"]) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(missing.description == "no installed app matches 'ZZFixture-Named'")
    }

    /// `backups restore <app>` goes through the same selection.
    ///
    /// Mutation: pass `installed ?? []` to `Inventory.select` in `resolveTarget`.
    @Test func restoringAfterAnAbandonedScanDoesNotCallTheAppMissing() {
        guard case .failure(let failure) = Backups.resolveTarget(query: "ZZFixture-Named", installed: nil) else {
            Issue.record("an abandoned scan resolved a restore target")
            return
        }
        #expect(failure.description.hasPrefix("can't tell whether 'ZZFixture-Named' is installed"))
    }

    /// `install --all` after an abandoned scan checked nothing. Exit status stays 0.
    ///
    /// Mutation: have `emptyPlanLine` ignore `scanAbandoned`.
    @Test func installAllAfterAnAbandonedScanDoesNotSayNothingToInstall() {
        #expect(Install.emptyPlanLine(scanAbandoned: true)
            == "Nothing was checked: the app scan was abandoned (see above).")
        #expect(Install.emptyPlanLine(scanAbandoned: false) == "Nothing to install.")
    }

    /// `doctor`'s rollback line: an abandoned scan examined no app, so it is
    /// neither ✓ nor ✗. The exit status is App Management's alone, unchanged.
    ///
    /// Mutation: `guard let unbackupable` → `let unbackupable = unbackupable ?? []`.
    @Test func doctorDoesNotVouchForAppsItDidNotExamine() {
        let notChecked = Doctor.rollbackLine(nil)
        #expect(notChecked.ok == nil)
        #expect(notChecked.detail == "not checked — the app scan was abandoned (see above)")

        let clean = Doctor.rollbackLine([])
        #expect(clean.ok == true)
        #expect(clean.detail == "every app can be copied before an update")

        let blocked = Doctor.rollbackLine([
            Doctor.Unbackupable(app: "ZZFixture-Root", blockedBy: "/Applications/ZZFixture-Root.app/x")
        ])
        #expect(blocked.ok == false)
        #expect(blocked.detail.hasPrefix("1 app(s) cannot be backed up"))
    }

    /// `doctor --json`: "not checked" is the key being absent, not `null` — the
    /// synthesized `Encodable` skips a nil optional, as it does for
    /// `installLockHolder` — and `[]` stays "checked, none". The doc comment on
    /// `Report.unbackupable` promises exactly this.
    ///
    /// Mutation: give `Doctor.Report` an `encode(to:)` that writes `unbackupable`
    /// with `encode` (a `null` for nil).
    @Test func doctorJSONOmitsUnbackupableWhenNotChecked() throws {
        func report(_ unbackupable: [Doctor.Unbackupable]?) -> Doctor.Report {
            Doctor.Report(
                executable: "/ZZFixture/duo", appManagement: "granted",
                isResponsibleForItself: true, installedApp: nil,
                privilegedHelper: "registered", githubToken: "none",
                alcoveCredentials: false, masInstalled: false, brewInstalled: false,
                stateDirectory: "/ZZFixture/state", installLockHolder: nil,
                unbackupable: unbackupable)
        }
        func object(_ r: Doctor.Report) throws -> [String: Any] {
            let data = try JSONEncoder().encode(r)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let notChecked = try object(report(nil))
        #expect(notChecked["unbackupable"] == nil)
        #expect(notChecked.keys.contains("appManagement"), "fixture encoded nothing")

        let checked = try object(report([]))
        #expect((checked["unbackupable"] as? [Any])?.isEmpty == true)
    }

    /// `backups list` after an abandoned scan: every backup is listed by its key,
    /// which otherwise means nothing installed claims it — so the listing says why.
    /// With no backups at all, "No backups stored." is true either way.
    ///
    /// Mutation: drop the `if scanAbandoned` block in `Backups.emitText`.
    @Test func backupsListSaysWhyEveryBackupIsListedByKey() {
        let row = Backups.Row(
            app: "com.zzfixture.keyed", bundleID: nil, path: nil, key: "com.zzfixture.keyed",
            version: "1.0", savedAt: Date(timeIntervalSince1970: 0), bytes: 1, disk: nil,
            held: false)
        func lines(_ rows: [Backups.Row], abandoned: Bool) -> [String] {
            var out: [String] = []
            Backups.emitText(rows, scanAbandoned: abandoned, print: { out.append($0) })
            return out
        }
        let note = "  Listed by key, not app: the app scan was abandoned (see above), "
            + "so no backup could be matched to an installed app."
        #expect(lines([row], abandoned: true).last == note)
        #expect(!lines([row], abandoned: false).contains(note))
        #expect(lines([], abandoned: true) == ["No backups stored."])
    }
}
