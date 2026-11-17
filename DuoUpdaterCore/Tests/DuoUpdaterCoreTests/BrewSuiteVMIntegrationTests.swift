import Foundation
import Testing
@testable import DuoUpdaterCore

/// Opt-in coverage of the genuine suite prepared by
/// `verify/issues-2057-2064/fixed/racket-suite-fixture.py`. These are repository
/// tests, compiled through the usual test target, never a temporary diagnostic
/// executable. No fixture is installed or changed by this test.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DUO206X_VM_SUITE"] == "1",
                "Requires the explicitly prepared, genuine Racket suite in the macOS VM"))
struct BrewSuiteVMIntegrationTests {
    private actor Downstream: UpdateSource {
        nonisolated let name = "Vendor"
        var calls = 0
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            calls += 1
            return RemoteVersion(shortVersion: "99.0", version: nil, downloadURL: nil, sourceName: name)
        }
    }

    @Test func genuineSuiteHasOnePackageUpdateUnitBeforeAndAfterUpgrade() async throws {
        let hardware = try await ChildProcess.run("/usr/sbin/sysctl", ["-n", "hw.model"], onCancel: .terminateChild)
        let model = String(decoding: hardware.standardOutput, as: UTF8.self)
        try #require(hardware.terminationStatus == 0 && model.hasPrefix("VirtualMac"), "VM execution only")
        let stage = try #require(ProcessInfo.processInfo.environment["DUO206X_VM_SUITE_STAGE"])
        try #require(stage == "before" || stage == "after")
        let installedVersion = stage == "before" ? "9.2" : "9.3"
        let suitePath = "/Applications/Racket v\(installedVersion)"
        let expectedNames: Set<String> = ["DrRacket.app", "PLT Games.app", "Slideshow.app"]
        let apps = AppScanner(locations: [URL(fileURLWithPath: "/Applications")]).scan()
            .filter { $0.path.deletingLastPathComponent().path == suitePath }
        try #require(Set(apps.map { $0.path.lastPathComponent }) == expectedNames,
                     "The genuine three-member suite must be scanned before asserting ownership")
        let expectedPaths = Set(apps.map { $0.path.standardizedFileURL.resolvingSymlinksInPath().path })
        let owners = await ThirdPartyCaskSource.ownership(in: BrewLocalInventory.defaultCaskroomPaths, includeOfficial: true)
        let suiteOwners = owners.filter { !$0.suitePaths.isDisjoint(with: expectedPaths) }
        try #require(suiteOwners.count == 1)
        let owner = try #require(suiteOwners.first)
        #expect(owner.token == "racket")
        #expect(owner.tap == "homebrew/cask")
        #expect(owner.brewPrefix == "/opt/homebrew")
        #expect(owner.suitePaths == expectedPaths)

        let downstream = Downstream()
        let source = HomebrewCaskSource()
        // Source priority cannot give one suite member an independent update.
        let rows = await UpdateChecker(sources: [downstream, ThirdPartyCaskSource(), source]).check(apps)
        #expect(Set(rows.map(\.id)) == Set(apps.map(\.id)))
        #expect(rows.allSatisfy { $0.status == .homebrewSuiteManaged(cask: "racket") && $0.remote == nil && !$0.hasUpdate })
        #expect(await downstream.calls == 0)

        let service = BrewFormulaService()
        let report = await service.installedReport()
        try #require(report.casksRead)
        let packageAssociations = report.appCasks.filter { $0.row.name == "racket" }
        try #require(packageAssociations.count == 1)
        let cask = try #require(packageAssociations.first)
        #expect(cask.isSuite)
        #expect(Set(cask.appPaths) == expectedPaths)
        #expect(cask.row.installedVersion == installedVersion)
        #expect(report.appLessCasks.allSatisfy { $0.name != "racket" })
        #expect(BrewAppCask.unclaimed(packageAssociations, rows: rows, checked: true) { _ in false } == ["racket"])
        let outdated = try await service.outdatedCasks().filter { $0.name == "racket" }
        if stage == "before" {
            try #require(outdated.count == 1)
            #expect(outdated.first?.currentVersion == "9.3")
            #expect(BrewFormulaService.merge([cask.row], outdated: outdated).first?.canUpgrade == true)
        } else {
            #expect(outdated.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: "/Applications/Racket v9.2"))
            #expect(BrewLocalInventory().installedVersion(caskToken: "racket") == "9.3")
        }
        let members = apps.map { ["name": $0.path.lastPathComponent, "version": $0.shortVersion ?? "?", "path": $0.path.path] }
        let record: [String: Any] = [
            "stage": stage, "installedCaskVersion": installedVersion, "members": members,
            "suiteOwner": owner.qualifiedName, "ownerPaths": owner.suitePaths.sorted(),
            "packageRows": packageAssociations.map { $0.row.name },
            "outdated": outdated.map { $0.currentVersion }, "downstreamCalls": await downstream.calls,
        ]
        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("DUO206X_SUITE " + String(decoding: json, as: UTF8.self))
    }
}
