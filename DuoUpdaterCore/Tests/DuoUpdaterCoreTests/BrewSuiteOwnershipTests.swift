import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct BrewSuiteOwnershipTests {
    private struct Disk {
        let root: URL
        let tap: String
        let fm = FileManager.default
        var caskroom: URL { root.appendingPathComponent("Caskroom") }
        var cask: URL { caskroom.appendingPathComponent("racket") }
        var applications: URL { root.appendingPathComponent("Applications") }
        var suite: URL { applications.appendingPathComponent("Racket v9.2") }
        var staged: URL { cask.appendingPathComponent("9.2/Racket v9.2") }
        var main: URL { suite.appendingPathComponent("DrRacket.app") }
        var games: URL { suite.appendingPathComponent("PLT Games.app") }

        init(tap: String = "homebrew/cask") throws {
            self.tap = tap
            root = FileManager.default.temporaryDirectory.appendingPathComponent("BrewSuite-\(UUID().uuidString)")
            let metadata = cask.appendingPathComponent(".metadata/9.2/20261117000000/Casks")
            try fm.createDirectory(at: metadata, withIntermediateDirectories: true)
            try Data().write(to: metadata.appendingPathComponent("racket.json"))
            try fm.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            try app(main, version: "9.2")
            // A suite's individual app versions need not match its cask record.
            try app(games, version: "3.1")
            try fm.createSymbolicLink(at: staged, withDestinationURL: suite)
            try receipt()
            let config: [String: Any] = ["default": ["appdir": applications.path]]
            try JSONSerialization.data(withJSONObject: config)
                .write(to: cask.appendingPathComponent(".metadata/config.json"))
        }

        func remove() { try? fm.removeItem(at: root) }

        func app(_ path: URL, version: String = "1.0") throws {
            let contents = path.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: [String: Any] = [
                "CFBundleShortVersionString": version,
                "CFBundleIdentifier": "test.suite.\(path.lastPathComponent)",
            ]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }

        func receipt(version: String = "9.2", artifacts: [[String: Any]]? = nil) throws {
            let object: [String: Any] = [
                "source": ["tap": tap, "version": version],
                "uninstall_artifacts": artifacts ?? [["suite": ["Racket v9.2"]]],
            ]
            try JSONSerialization.data(withJSONObject: object)
                .write(to: cask.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
        }

        var expected: Set<String> {
            Set([main, games].map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        }

        func installed(_ path: URL? = nil, isMASApp: Bool = false,
                       isToolboxManaged: Bool = false, isTestFlightApp: Bool = false) -> InstalledApp {
            InstalledApp(name: "DrRacket", bundleID: "org.racket-lang.DrRacket", shortVersion: "9.2",
                         buildVersion: nil, path: path ?? main, isMASApp: isMASApp,
                         isToolboxManaged: isToolboxManaged, isTestFlightApp: isTestFlightApp,
                         sparkleFeedURL: nil)
        }

        func officialSource() -> HomebrewCaskSource {
            HomebrewCaskSource(
                catalog: HomebrewCaskCatalog(testIndex: CaskIndex(allByAppFilename: [:], allByBundleID: [:])),
                inventory: BrewLocalInventory(caskroomPaths: [caskroom.path]))
        }
    }

    private actor Downstream: UpdateSource {
        nonisolated let name = "Vendor"
        var calls = 0
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            calls += 1
            return RemoteVersion(shortVersion: "99.0", version: nil,
                                 downloadURL: URL(string: "https://example.com/app.dmg"), sourceName: name)
        }
    }

    @Test(arguments: ["homebrew/cask", "example/tap"])
    func registeredSuiteOwnsItsExactScannableMembers(tap: String) async throws {
        let disk = try Disk(tap: tap)
        defer { disk.remove() }
        let nested = disk.suite.appendingPathComponent("Tools/Helper.app")
        try disk.app(nested)
        try disk.app(disk.main.appendingPathComponent("Contents/Helpers/Nested.app"))
        try disk.app(disk.suite.appendingPathComponent(".Hidden.app"))
        try disk.app(disk.suite.appendingPathComponent("DrRacket copy.app"))
        let outside = disk.root.appendingPathComponent("Elsewhere/Unrelated.app")
        try disk.app(outside)
        try disk.fm.createSymbolicLink(at: disk.suite.appendingPathComponent("Escaping.app"), withDestinationURL: outside)
        try disk.fm.createSymbolicLink(at: disk.suite.appendingPathComponent("DeepAlias.app"), withDestinationURL: nested)
        #expect(AppScanner.hasRow(outside))
        #expect(AppScanner.hasRow(nested))

        let owners = await ThirdPartyCaskSource.ownership(in: [disk.caskroom.path], includeOfficial: true)
        let owner = try #require(owners.first { $0.token == "racket" })
        #expect(owner.suitePaths == disk.expected)
        #expect(owner.paths == disk.expected)
        #expect(BrewLocalInventory.suiteAppPaths(token: "racket", caskroomPaths: [disk.caskroom.path]) == disk.expected)
        let unrelatedCopy = disk.root.appendingPathComponent("Other/Racket v9.2/DrRacket.app")
        try disk.app(unrelatedCopy)
        #expect(try ThirdPartyCaskSource.suiteOwner(of: disk.installed(unrelatedCopy), owners: owners) == nil)
    }

    @Test func missingSuiteLinkUsesOnlyTheVersionMatchedReceiptTarget() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        try disk.fm.removeItem(at: disk.staged)
        #expect(BrewLocalInventory.suiteAppPaths(token: "racket", caskroomPaths: [disk.caskroom.path]) == disk.expected)
        try disk.receipt(version: "9.1")
        #expect(BrewLocalInventory.suiteAppPaths(token: "racket", caskroomPaths: [disk.caskroom.path]).isEmpty)
        let owners = await ThirdPartyCaskSource.ownership(in: [disk.caskroom.path], includeOfficial: true)
        #expect(owners.allSatisfy { $0.suitePaths.isEmpty })
    }

    @Test func relocatedLiveSuiteLinkDoesNotAdoptItsOldReceiptTarget() throws {
        let disk = try Disk()
        defer { disk.remove() }
        let relocated = disk.root.appendingPathComponent("Moved/Suite")
        let movedApp = relocated.appendingPathComponent("DrRacket.app")
        try disk.app(movedApp)
        try disk.fm.removeItem(at: disk.staged)
        try disk.fm.createSymbolicLink(at: disk.staged, withDestinationURL: relocated)
        let found = BrewLocalInventory.suiteAppPaths(token: "racket", caskroomPaths: [disk.caskroom.path])
        #expect(found == [movedApp.standardizedFileURL.resolvingSymlinksInPath().path])
        #expect(found.isDisjoint(with: disk.expected))
        try disk.fm.removeItem(at: relocated)
        #expect(BrewLocalInventory.missingRegisteredAppPath(token: "racket", caskroomPaths: [disk.caskroom.path])
                == relocated.path)
    }

    @Test func extractedInstallerAndUndeclaredDirectoryLinkAreNotSuites() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        try disk.receipt(artifacts: [["installer": [["manual": "Installer.app"]]]])
        let installer = disk.cask.appendingPathComponent("9.2/Installer.app")
        try disk.app(installer)
        let owners = await ThirdPartyCaskSource.ownership(in: [disk.caskroom.path], includeOfficial: true)
        #expect(owners.allSatisfy { $0.paths.isEmpty })
        #expect(owners.allSatisfy { $0.suitePaths.isEmpty })
    }

    @Test(arguments: ["../Racket v9.2", "/Racket v9.2"])
    func suiteSourceCannotEscapeItsStagedVersion(source: String) throws {
        let disk = try Disk()
        defer { disk.remove() }
        try disk.receipt(artifacts: [["suite": [source, ["target": disk.suite.path]]]])
        #expect(BrewLocalInventory.registeredSuiteTargets(directory: disk.cask, version: "9.2").isEmpty)
    }

    @Test func intermediateStagedSymlinkCannotSupplyAnOutsideSuiteLink() throws {
        let disk = try Disk()
        defer { disk.remove() }
        let outside = disk.root.appendingPathComponent("OtherStaging")
        try disk.fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try disk.fm.createSymbolicLink(at: outside.appendingPathComponent("Suite"), withDestinationURL: disk.suite)
        try disk.fm.createSymbolicLink(at: disk.cask.appendingPathComponent("9.2/Aliases"), withDestinationURL: outside)
        try disk.receipt(artifacts: [["suite": ["Aliases/Suite", ["target": disk.suite.path]]]])
        #expect(BrewLocalInventory.registeredSuiteTargets(directory: disk.cask, version: "9.2").isEmpty)
    }

    @Test func suiteTargetUsesSavedExplicitAppdirAndTargetName() throws {
        let disk = try Disk()
        defer { disk.remove() }
        try disk.fm.removeItem(at: disk.staged)
        let custom = disk.root.appendingPathComponent("Custom")
        let app = custom.appendingPathComponent("Renamed Suite/Main.app")
        try disk.app(app)
        try disk.receipt(artifacts: [["suite": ["Racket v9.2", ["target": "Renamed Suite"]]]])
        let config: [String: Any] = [
            "explicit": ["appdir": custom.path],
            "env": ["appdir": disk.root.appendingPathComponent("Wrong").path],
            "default": ["appdir": disk.applications.path],
        ]
        try JSONSerialization.data(withJSONObject: config)
            .write(to: disk.cask.appendingPathComponent(".metadata/config.json"))
        #expect(BrewLocalInventory.suiteAppPaths(token: "racket", caskroomPaths: [disk.caskroom.path])
                == [app.standardizedFileURL.resolvingSymlinksInPath().path])
    }

    @Test func terminalSuiteOwnershipWinsBeforeAnAnsweringDownstreamSource() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        let downstream = Downstream()
        let source = disk.officialSource()
        let apps = [disk.installed(), disk.installed(disk.games)]
        let results = await UpdateChecker(sources: [downstream, source]).check(apps)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status == .homebrewSuiteManaged(cask: "racket") })
        #expect(results.allSatisfy { !$0.hasUpdate && $0.remote == nil && $0.homebrewSourceIdentifier == "racket" })
        #expect(await downstream.calls == 0)
        #expect(try await source.latestVersion(for: apps[0]) == nil)
        #expect(UpdateSourceGroup(results[0]) == .homebrew)
        #expect(RowAction.state(for: RowActionFacts(status: results[0].status)) == .managedElsewhere(.homebrewSuite("racket")))
        #expect(PreInstallGate.decision(for: results[0].status, offered: .init(marketing: "9.3"),
                                       confirmed: .init()) == .managedElsewhere)
    }

    @Test func thirdPartySuiteAlsoTerminatesBeforeOtherSources() async throws {
        let disk = try Disk(tap: "example/tap")
        defer { disk.remove() }
        let downstream = Downstream()
        let source = ThirdPartyCaskSource(caskroomPaths: [disk.caskroom.path]) { _ in
            Issue.record("A suite member must not request a per-app remote")
            return nil
        }
        let result = await UpdateChecker(sources: [downstream, source]).check([disk.installed()])[0]
        #expect(result.status == .homebrewSuiteManaged(cask: "example/tap/racket"))
        #expect(await downstream.calls == 0)
        #expect(try await source.latestVersion(for: disk.installed()) == nil)
    }

    @Test func storeAndOtherTerminalManagersOutrankSuiteAssociation() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        let source = disk.officialSource()
        let checker = UpdateChecker(sources: [source])
        #expect(await checker.check(disk.installed(isMASApp: true)).status == .appStoreManaged)
        #expect(await checker.check(disk.installed(isToolboxManaged: true)).status == .toolboxManaged)
        #expect(await checker.check(disk.installed(isTestFlightApp: true)).status == .testFlightManaged)
    }

    @Test func anAmbiguousSuiteOwnerDoesNotFallThroughToAnIndependentInstall() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        let second = try Disk(tap: "example/tap")
        defer { second.remove() }
        try second.fm.removeItem(at: second.staged)
        try second.fm.createSymbolicLink(at: second.staged, withDestinationURL: disk.suite)
        let roots = [disk.caskroom.path, second.caskroom.path]
        let owners = await ThirdPartyCaskSource.ownership(in: roots, includeOfficial: true)
        let mainPath = disk.main.standardizedFileURL.resolvingSymlinksInPath().path
        #expect(owners.filter { $0.suitePaths.contains(mainPath) }.count == 2)
        #expect(throws: ThirdPartyCaskSource.Unavailable.self) {
            try ThirdPartyCaskSource.suiteOwner(of: disk.installed(), owners: owners)
        }
        let downstream = Downstream()
        let source = HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: CaskIndex(allByAppFilename: [:], allByBundleID: [:])),
            inventory: BrewLocalInventory(caskroomPaths: roots))
        let result = await UpdateChecker(sources: [downstream, source]).check([disk.installed()])[0]
        guard case .error = result.status else { Issue.record("Ambiguous suite ownership must refuse"); return }
        #expect(result.remote == nil)
        #expect(await downstream.calls == 0)
    }
}
