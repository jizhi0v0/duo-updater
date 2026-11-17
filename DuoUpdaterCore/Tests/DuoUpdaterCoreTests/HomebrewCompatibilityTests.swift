import Foundation
import Testing
@testable import DuoUpdaterCore

struct HomebrewCompatibilityTests {
    private static func app(path: URL, version: String = "1.0") -> InstalledApp {
        InstalledApp(name: "Example", bundleID: "org.example.app", shortVersion: version,
                     buildVersion: "101", path: path, isMASApp: false, sparkleFeedURL: nil)
    }

    @Test func variationResolvesEveryFieldBeforeIndexing() throws {
        let data = Data(#"[{"token":"example","version":"2.0","url":"https://example.com/base.pkg","artifacts":[{"pkg":["Base.pkg"]}],"depends_on":{"macos":{">=":["27"]}},"variations":{"arm64_sequoia":{"version":"1.0","url":"https://example.com/arm.zip","artifacts":[{"app":["Arm.app"]}],"depends_on":{"macos":{">=":["15"]}}}}]"#.utf8)
        let index = try HomebrewCaskCatalog.index(fromCatalogJSON: data, platformTag: "arm64_sequoia")
        let entry = try #require(index.byToken["example"])
        #expect(entry.version == "1.0")
        #expect(entry.url?.absoluteString == "https://example.com/arm.zip")
        #expect(entry.installKind == .brew)
        #expect(entry.macOS?.admits("15.0") == true)
        #expect(index.allByAppFilename["arm.app"]?.map(\.token) == ["example"])
        #expect(index.allByAppFilename["base.app"] == nil)
        let base = try HomebrewCaskCatalog.index(fromCatalogJSON: data, platformTag: "arm64_tahoe")
        #expect(base.byToken["example"]?.version == "2.0")
        #expect(base.byToken["example"]?.macOS?.admits("15.0") == false)
    }

    @Test func variationNullRemovesBaseConstraintAndURL() throws {
        let data = Data(#"[{"token":"example","version":"2","url":"https://example.com/app.zip","depends_on":{"macos":{">=":["27"]}},"variations":{"arm64_sequoia":{"url":null,"depends_on":null}}}]"#.utf8)
        let entry = try #require(HomebrewCaskCatalog.index(
            fromCatalogJSON: data, platformTag: "arm64_sequoia").byToken["example"])
        #expect(entry.url == nil)
        #expect(entry.macOS == nil)
    }

    @Test func supportedHostTagsMatchHomebrew() {
        #expect(HomebrewCaskCatalog.hostPlatformTag(osVersion: "15.7.1") == "arm64_sequoia")
        #expect(HomebrewCaskCatalog.hostPlatformTag(osVersion: "26.2") == "arm64_tahoe")
        #expect(HomebrewCaskCatalog.hostPlatformTag(osVersion: "27.0") == "arm64_golden_gate")
    }

    private static func fixture(token: String, tap: String = "homebrew/cask") throws -> (URL, InstalledApp) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = root.appendingPathComponent("Applications/Example.app")
        let cask = root.appendingPathComponent("Caskroom/\(token)")
        let saved = cask.appendingPathComponent(".metadata/1.0,101/20261117/Casks")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        try Data().write(to: saved.appendingPathComponent("\(token).rb"))
        try Data("{\"source\":{\"tap\":\"\(tap)\"}}".utf8)
            .write(to: cask.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
        let staged = cask.appendingPathComponent("1.0,101")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: staged.appendingPathComponent("Example.app"), withDestinationURL: path)
        return (root, app(path: path))
    }

    private static func catalog() throws -> HomebrewCaskCatalog {
        let data = Data(#"[{"token":"new-example","old_tokens":["old-example"],"version":"1.0,102","url":"https://example.com/app.zip","artifacts":[{"app":["Example.app"]}]}]"#.utf8)
        return HomebrewCaskCatalog(testIndex: try HomebrewCaskCatalog.index(fromCatalogJSON: data))
    }

    @Test func oldTokenMatchesOnlyTheExactOfficialCopy() async throws {
        let (root, app) = try Self.fixture(token: "old-example")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HomebrewCaskSource(catalog: try Self.catalog(), inventory: BrewLocalInventory(
            caskroomPaths: [root.appendingPathComponent("Caskroom").path]))
        let remote = try #require(try await source.latestVersion(for: app))
        #expect(remote.sourceIdentifier == "new-example")
        #expect(remote.homebrewInstalledCaskVersion == "1.0,101")
        #expect(remote.homebrewCaskVersion == "1.0,102")
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .updateAvailable(latest: "1.0,102"))
        let another = Self.app(path: root.appendingPathComponent("Other/Example.app"))
        #expect(try await source.latestVersion(for: another) == nil)
    }

    @Test func oldTokenFromAnotherTapCannotBeAdopted() async throws {
        let (root, app) = try Self.fixture(token: "old-example", tap: "someone/else")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = HomebrewCaskSource(catalog: try Self.catalog(), inventory: BrewLocalInventory(
            caskroomPaths: [root.appendingPathComponent("Caskroom").path]))
        #expect(try await source.latestVersion(for: app) == nil)
    }

    @Test func activeTokenWinsOverAnOldAlias() throws {
        let data = Data(#"[{"token":"current","old_tokens":["other"],"version":"1"},{"token":"other","version":"2"}]"#.utf8)
        let index = try HomebrewCaskCatalog.index(fromCatalogJSON: data)
        #expect(index.byToken["other"]?.token == "other")
        #expect(index.byToken["current"]?.oldTokens.isEmpty == true)
    }

    @Test func pinBlocksBrewWithoutBecomingAnotherSourcesHold() async throws {
        let (root, app) = try Self.fixture(token: "old-example")
        defer { try? FileManager.default.removeItem(at: root) }
        let pins = root.appendingPathComponent("var/homebrew/pinned_casks")
        try FileManager.default.createDirectory(at: pins, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: pins.appendingPathComponent("old-example"),
            withDestinationURL: root.appendingPathComponent("Caskroom/old-example/1.0,101"))
        let source = HomebrewCaskSource(catalog: try Self.catalog(), inventory: BrewLocalInventory(
            caskroomPaths: [root.appendingPathComponent("Caskroom").path]))
        let remote = try #require(try await source.latestVersion(for: app))
        #expect(remote.homebrewPinned)
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .upToDate)
        var vendor = RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: nil, sourceName: "Vendor")
        vendor.homebrewPinned = true
        #expect(UpdateChecker.evaluate(installed: app, remote: vendor) == .updateAvailable(latest: "2.0"))
        let downstream = CountingVendor()
        let normal = await UpdateChecker(sources: [source, downstream], installedTeam: { _ in nil }).check(app)
        #expect(!normal.hasUpdate)
        #expect(await downstream.calls == 0)
        let explicit = await UpdateChecker(sources: [source, downstream],
            brewFallback: BrewFallbackPolicy(allowedKeys: [InstallPreferenceKey.key(for: app)]),
            installedTeam: { _ in nil }).check(app)
        #expect(explicit.remote?.sourceName == "Vendor")
        #expect(explicit.hasUpdate)
        #expect(await downstream.calls == 1)
    }

    private actor CountingVendor: UpdateSource {
        let name = "Vendor"
        var calls = 0
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            calls += 1
            return RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: nil, sourceName: name)
        }
    }

    @Test(arguments: ["1.0,102", "1.0:2026-11-17", "1.0,abcdef"])
    func opaqueVersionSuffixIsNotInterpretedAsABundleBuild(latest: String) {
        let app = Self.app(path: URL(fileURLWithPath: "/Applications/Example.app"))
        var remote = RemoteVersion(shortVersion: "1.0", version: nil, downloadURL: nil, sourceName: "Homebrew")
        remote.homebrewCaskVersion = latest
        remote.homebrewInstalledCaskVersion = "1.0,101"
        #expect(remote.version == nil)
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .updateAvailable(latest: latest))
        remote.homebrewInstalledCaskVersion = latest
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .upToDate)
        remote.homebrewInstalledCaskVersion = "1.0,101"
        let newer = Self.app(path: app.path, version: "2.0")
        #expect(UpdateChecker.evaluate(installed: newer, remote: remote) == .upToDate)
    }

    @Test(arguments: [false, true])
    func staleBrewReceiptDoesNotReofferAnInstalledMarketingRelease(packageRoute: Bool) {
        let current = Self.app(path: URL(fileURLWithPath: "/Applications/Example.app"), version: "2.0")
        var remote = RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: nil,
            sourceName: "Homebrew", requiresManualInstaller: packageRoute)
        remote.homebrewCaskVersion = "2.0"
        remote.homebrewInstalledCaskVersion = "1.0"
        remote.homebrewRecordedVersion = "1.0"
        #expect(UpdateChecker.evaluate(installed: current, remote: remote) == .upToDate)
        let old = Self.app(path: current.path, version: "1.0")
        #expect(UpdateChecker.evaluate(installed: old, remote: remote) == .updateAvailable(latest: "2.0"))
    }

    @Test(arguments: ["1.0,102", "1.0:2026-11-17", "1.0,abcdef"])
    func packageRouteCannotInferAnOpaqueSuffixUpdateFromItsUnchangedBrewRecord(latest: String) {
        let current = Self.app(path: URL(fileURLWithPath: "/Applications/Example.app"))
        var remote = RemoteVersion(shortVersion: "1.0", version: nil, downloadURL: nil,
            sourceName: "Homebrew", requiresManualInstaller: true)
        remote.homebrewCaskVersion = latest
        remote.homebrewInstalledCaskVersion = "1.0,101"
        remote.homebrewRecordedVersion = "1.0"
        #expect(UpdateChecker.evaluate(installed: current, remote: remote) == .upToDate)
        #expect(remote.displayVersion == "1.0")
        let old = Self.app(path: current.path, version: "0.9")
        remote.homebrewRecordedVersion = "0.9"
        #expect(UpdateChecker.evaluate(installed: old, remote: remote) == .updateAvailable(latest: "1.0"))
    }

}
