import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct BrewSuitePackageTests {
    private struct Disk {
        let root: URL
        var applications: URL { root.appendingPathComponent("Applications") }
        var caskroom: URL { root.appendingPathComponent("Caskroom") }
        var cask: URL { caskroom.appendingPathComponent("racket") }
        var suite: URL { applications.appendingPathComponent("Racket v9.2") }
        var paths: [String] { ["DrRacket.app", "PLT Games.app"].map { suite.appendingPathComponent($0).path } }

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("BrewSuitePackage-\(UUID().uuidString)")
            let metadata = cask.appendingPathComponent(".metadata/9.2/20261117000000/Casks")
            try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
            try Data().write(to: metadata.appendingPathComponent("racket.json"))
            for (filename, version) in [("DrRacket.app", "9.2"), ("PLT Games.app", "3.1")] {
                let contents = suite.appendingPathComponent(filename + "/Contents")
                try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
                let plist: [String: String] = ["CFBundleIdentifier": "test.suite.\(filename)", "CFBundleShortVersionString": version]
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                    .write(to: contents.appendingPathComponent("Info.plist"))
            }
            let staged = cask.appendingPathComponent("9.2/Racket v9.2")
            try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: staged, withDestinationURL: suite)
            let receipt: [String: Any] = [
                "source": ["tap": "homebrew/cask", "version": "9.2"],
                "uninstall_artifacts": [["suite": ["Racket v9.2"]]],
            ]
            try JSONSerialization.data(withJSONObject: receipt)
                .write(to: cask.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
            try JSONSerialization.data(withJSONObject: ["default": ["appdir": applications.path]])
                .write(to: cask.appendingPathComponent(".metadata/config.json"))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private let info = Data(#"""
        {"casks":[{"token":"racket","tap":"homebrew/cask","installed":"9.2","version":"9.3",
                    "artifacts":[{"suite":["Racket v9.3"],"target":"/Applications/Racket v9.3"}]}]}
        """#.utf8)

    @Test func registeredSuiteWithScannedMembersHasOnePersistentPackageRow() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        let fact = await BrewFormulaService.caskFacts(
            caskToken: "racket", appTargets: [], caskroomPaths: [disk.caskroom.path],
            scannedFolders: [disk.applications.path], receiptApps: { _ in nil })
        #expect(fact.isSuite)
        #expect(fact.installsAnApp)
        #expect(Set(fact.appPaths) == Set(disk.paths))
        #expect(BrewFormulaService.appLessCasks(installedInfo: info, facts: ["racket": fact]).isEmpty)
        let associations = BrewFormulaService.appCasks(installedInfo: info, facts: ["racket": fact])
        let cask = try #require(associations.first)
        #expect(associations.count == 1)
        #expect(cask.isSuite)
        let members = disk.paths.enumerated().map { index, path in
            UpdateResult(app: InstalledApp(
                name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                bundleID: "test.suite.\(index)", shortVersion: index == 0 ? "9.2" : "3.1", buildVersion: nil,
                path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil),
                remote: nil, status: .homebrewSuiteManaged(cask: "racket"))
        }
        let beforeChecks = BrewAppCask.unclaimed(associations, rows: [], checked: false) { _ in true }
        let afterChecks = BrewAppCask.unclaimed(associations, rows: members, checked: true) { _ in true }
        #expect(beforeChecks == ["racket"])
        #expect(afterChecks == ["racket"])
        #expect(BrewAppCask.onDiskAtRecord(cask) { $0 == disk.paths[0] ? "9.2" : "3.1" })
        let rows = BrewFormulaService.merge(associations.map(\.row), outdated: [
            BrewOutdatedFormula(name: "racket", installedVersion: "9.2", currentVersion: "9.3", kind: .cask),
        ])
        #expect(Set(rows.filter(\.canUpgrade).map(\.name)) == ["racket"])
        #expect(members.allSatisfy { !$0.hasUpdate })
    }

    @Test func suiteOutsideTheScanRootsKeepsItsAppLessPackageRow() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        let fact = await BrewFormulaService.caskFacts(
            caskToken: "racket", appTargets: [], caskroomPaths: [disk.caskroom.path],
            scannedFolders: [], receiptApps: { _ in nil })
        #expect(fact.isSuite)
        #expect(!fact.installsAnApp)
        #expect(fact.appPaths.isEmpty)
        #expect(BrewFormulaService.appCasks(installedInfo: info, facts: ["racket": fact]).isEmpty)
        let rows = BrewFormulaService.appLessCasks(installedInfo: info, facts: ["racket": fact])
        #expect(rows.map(\.name) == ["racket"])
    }

    @Test func suiteVisibilityMatchesTheScannerForAnExplicitSymlinkRoot() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        // Prove the fixture really supplies scanner rows before comparing an
        // alias root. A scan that always returned nothing would otherwise pass.
        let directScanner = AppScanner(
            locations: [disk.applications], toolbox: ToolboxInventory(managedPaths: []),
            testflight: TestFlightInventory(macRows: []), channelBinding: { _, _, _ in nil })
        try #require(Set(directScanner.scan().map { $0.path.path }) == Set(disk.paths))
        // Preferences.customScanLocations always supplies directory URLs. This
        // alias is built before it exists, so give it that same directory hint.
        let alias = disk.root.appendingPathComponent("ApplicationAlias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: disk.applications)
        let scanner = AppScanner(
            locations: [alias], toolbox: ToolboxInventory(managedPaths: []),
            testflight: TestFlightInventory(macRows: []), channelBinding: { _, _, _ in nil })
        let scanned = Set(scanner.scan().map { $0.path.path })
        let facts = await BrewFormulaService.caskFacts(
            caskToken: "racket", appTargets: [], caskroomPaths: [disk.caskroom.path],
            scannedFolders: [alias.path], receiptApps: { _ in nil })
        #expect(facts.isSuite)
        #expect(Set(facts.appPaths) == scanned)
    }
}
