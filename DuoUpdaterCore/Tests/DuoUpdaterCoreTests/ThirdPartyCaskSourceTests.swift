import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct ThirdPartyCaskSourceTests {
    private func fixture(tap: String = "example/tap", version: String = "1.0") throws -> (URL, InstalledApp) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Applications/Nested/Example.app")
        let cask = root.appendingPathComponent("Caskroom/example")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cask.appendingPathComponent(".metadata"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cask.appendingPathComponent("1.0"), withIntermediateDirectories: true)
        try Data("{\"source\":{\"tap\":\"\(tap)\"}}".utf8)
            .write(to: cask.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
        try FileManager.default.createSymbolicLink(at: cask.appendingPathComponent("1.0/Example.app"), withDestinationURL: app)
        return (root, InstalledApp(name: "Example", bundleID: "example.app", shortVersion: version, buildVersion: nil,
                                   path: app, isMASApp: false, sparkleFeedURL: nil))
    }

    private struct Vendor: UpdateSource {
        let name = "GitHub"
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            RemoteVersion(shortVersion: "99.0", version: nil, downloadURL: URL(string: "https://example.com/app.dmg"),
                          sourceName: name, vendorInstallerKind: .dmg)
        }
    }

    @Test func originalTapWinsOverNewerGitHub() async throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let inventory = BrewLocalInventory(caskroomPaths: [root.appendingPathComponent("Caskroom").path])
        #expect(inventory.isInstalled(caskToken: "example"))
        #expect(!inventory.isOfficialCandidate(caskToken: "example"))
        let source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { args in
            #expect(args == ["info", "--json=v2", "--cask", "--", "example/tap/example"])
            return (0, Data(#"{"casks":[{"token":"example","tap":"example/tap","version":"2.0","auto_updates":true,"artifacts":[{"app":["Example.app"]}]}]}"#.utf8))
        }
        let result = await UpdateChecker(sources: [source, Vendor()]).check([app])[0]
        #expect(result.remote?.sourceName == "Homebrew")
        #expect(result.remote?.sourceIdentifier == "example/tap/example")
        #expect(result.remote?.shortVersion == "2.0")
        #expect(InstallCoordinator.route(for: result, requiresInstaller: false) == .homebrew)
    }

    /// The tap moved its cask to homebrew/cask through `tap_migrations.json`:
    /// `brew info --cask example/tap/example` then answers with the official
    /// cask (checked on brew 5, 2026-11-07, with a local tap migrating `iina`).
    /// The copy follows the official cask's rules, its `auto_updates` included.
    @Test(arguments: [true, false])
    func aTapMigratedToTheOfficialTapFollowsTheOfficialRules(autoUpdates: Bool) async throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { _ in
            (0, Data("{\"casks\":[{\"token\":\"example\",\"tap\":\"homebrew/cask\",\"version\":\"1.0\",\"auto_updates\":\(autoUpdates)}]}".utf8))
        }
        let downstream = CountingVendor()
        let result = await UpdateChecker(sources: [source, downstream]).check([app])[0]
        #expect(result.homebrewSelfUpdating == autoUpdates)
        #expect(result.remote?.sourceName == (autoUpdates ? "GitHub" : "Homebrew"))
        #expect(result.homebrewSourceIdentifier == "example/tap/example")
        #expect(await downstream.calls == (autoUpdates ? 1 : 0))
    }

    /// A move to another third-party tap is someone else's package.
    @Test func aTapMigratedToAnotherThirdPartyTapFailsClosed() async throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { _ in
            (0, Data(#"{"casks":[{"token":"example","tap":"someone/else","version":"1.0","auto_updates":true}]}"#.utf8))
        }
        let downstream = CountingVendor()
        let result = await UpdateChecker(sources: [source, downstream],
            brewFallback: BrewFallbackPolicy(checksOtherSourcesByDefault: true)).check([app])[0]
        guard case .error = result.status else { Issue.record("Expected a failed check, got \(result.status)"); return }
        #expect(await downstream.calls == 0)
    }

    /// How the copy under test reached its fallback choice.
    enum FallbackSetup: CaseIterable, Sendable {
        case off, perCopy, byDefault, byDefaultButHomebrewOnly, perCopyBeatsBlockedDefault

        func policy(_ key: String) -> BrewFallbackPolicy {
            switch self {
            case .off: return BrewFallbackPolicy()
            case .perCopy: return BrewFallbackPolicy(allowedKeys: [key])
            case .byDefault: return BrewFallbackPolicy(checksOtherSourcesByDefault: true)
            case .byDefaultButHomebrewOnly:
                return BrewFallbackPolicy(checksOtherSourcesByDefault: true, blockedKeys: [key])
            case .perCopyBeatsBlockedDefault:
                return BrewFallbackPolicy(checksOtherSourcesByDefault: false, allowedKeys: [key])
            }
        }

        var enabled: Bool {
            switch self {
            case .off, .byDefaultButHomebrewOnly: return false
            case .perCopy, .byDefault, .perCopyBeatsBlockedDefault: return true
            }
        }
    }

    @Test(arguments: FallbackSetup.allCases, ["0.5", "1.0", "2.0"])
    func fallbackRequiresOptInAndNoBrewUpdate(setup: FallbackSetup, brewVersion: String) async throws {
        for tap in ["example/tap", "homebrew/cask"] { for autoUpdates in [true, false] {
            // Only an official cask's `auto_updates` stands in for the opt-in,
            // and only for a copy without its own choice.
            let selfUpdating = tap == "homebrew/cask" && autoUpdates
            let enabled = setup == .off ? selfUpdating : setup.enabled
            let (root, app) = try fixture(tap: tap)
            defer { try? FileManager.default.removeItem(at: root) }
            let json = Data("[{\"token\":\"example\",\"tap\":\"\(tap)\",\"version\":\"\(brewVersion)\",\"auto_updates\":\(autoUpdates),\"artifacts\":[{\"app\":[\"Example.app\"]}]}]".utf8)
            let source: any UpdateSource
            if tap == "homebrew/cask" {
                source = HomebrewCaskSource(
                    catalog: HomebrewCaskCatalog(testIndex: try HomebrewCaskCatalog.index(fromCatalogJSON: json)),
                    inventory: BrewLocalInventory(installedTokens: ["example"]))
            } else {
                source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { _ in
                    (0, Data("{\"casks\":".utf8) + json + Data("}".utf8))
                }
            }
            let downstream = CountingVendor()
            let result = await UpdateChecker(sources: [source, downstream],
                brewFallback: setup.policy(InstallPreferenceKey.key(for: app))).check([app])[0]
            let fallsThrough = enabled && brewVersion != "2.0"
            #expect(result.remote?.sourceName == (fallsThrough ? "GitHub" : "Homebrew"))
            #expect(await downstream.calls == (fallsThrough ? 1 : 0))
            #expect(result.homebrewSourceIdentifier != nil)
            #expect(result.homebrewSelfUpdating == selfUpdating, "\(tap) auto_updates=\(autoUpdates)")
            if !fallsThrough && brewVersion != "2.0" { #expect(!result.hasUpdate) }
        } }
    }

    @Test func homebrewOnlyWinsWhenBothChoicesAreRecorded() {
        let policy = BrewFallbackPolicy(checksOtherSourcesByDefault: true, allowedKeys: ["k"], blockedKeys: ["k"])
        #expect(policy.override(for: "k") == .homebrewOnly)
        #expect(!policy.checksOtherSources("k", selfUpdating: true))
        #expect(policy.checksOtherSources("other", selfUpdating: false))
    }

    private actor CountingVendor: UpdateSource {
        nonisolated let name = "GitHub"
        var calls = 0
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            calls += 1
            return try await Vendor().latestVersion(for: app)
        }
    }

    @Test func enabledFallbackWithoutAnotherSourceKeepsBrew() async throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { _ in
            (0, Data(#"{"casks":[{"token":"example","tap":"example/tap","version":"1.0"}]}"#.utf8))
        }
        let result = await UpdateChecker(sources: [source],
            brewFallback: BrewFallbackPolicy(allowedKeys: [InstallPreferenceKey.key(for: app)])).check([app])[0]
        #expect(result.remote?.sourceName == "Homebrew")
        #expect(result.status == .upToDate)
    }

    private final class OfflineProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
        override func stopLoading() {}
    }

    @Test func officialCatalogueFailureDoesNotAuthorizeFallbackOrBlockUnrelatedCopy() async throws {
        let (root, app) = try fixture(tap: "homebrew/cask")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineProtocol.self]
        let source = HomebrewCaskSource(catalog: HomebrewCaskCatalog(session: URLSession(configuration: config)),
            inventory: BrewLocalInventory(caskroomPaths: [root.appendingPathComponent("Caskroom").path]))
        let downstream = CountingVendor()
        let checker = UpdateChecker(sources: [source, downstream],
            brewFallback: BrewFallbackPolicy(allowedKeys: [InstallPreferenceKey.key(for: app)]))
        let result = await checker.check(app)
        guard case .error = result.status else { Issue.record("Known owner must fail closed"); return }
        #expect(await downstream.calls == 0)
        let unrelated = InstalledApp(name: "Example", bundleID: "example.app", shortVersion: "1.0", buildVersion: nil,
            path: root.appendingPathComponent("Other/Example.app"), isMASApp: false, sparkleFeedURL: nil)
        #expect(await checker.check(unrelated).remote?.sourceName == "GitHub")
    }

    @Test func officialAutoUpdatingCaskOnlyOwnsItsRecordedPath() async throws {
        let (root, app) = try fixture(tap: "homebrew/cask")
        defer { try? FileManager.default.removeItem(at: root) }
        let json = Data(#"[{"token":"example","version":"2.0","auto_updates":true,"artifacts":[{"app":["Example.app"]}]}]"#.utf8)
        let source = HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: try HomebrewCaskCatalog.index(fromCatalogJSON: json)),
            inventory: BrewLocalInventory(caskroomPaths: [root.appendingPathComponent("Caskroom").path]))
        let copy = InstalledApp(name: "Example", bundleID: "example.app", shortVersion: "0.5", buildVersion: nil,
            path: root.appendingPathComponent("Manual/Example.app"), isMASApp: false, sparkleFeedURL: nil)
        #expect(try await source.latestVersion(for: app)?.sourceIdentifier == "example")
        #expect(try await source.latestVersion(for: copy) == nil)
        let result = await UpdateChecker(sources: [source, Vendor()]).check(copy)
        #expect(result.remote?.sourceName == "GitHub")
    }

    @Test func officialReceiptContinuesToOtherSources() async throws {
        let (root, app) = try fixture(tap: "homebrew/cask")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { _ in
            Issue.record("Official receipts must not enter the third-party route")
            return nil
        }
        let result = await UpdateChecker(sources: [source, Vendor()]).check([app])[0]
        #expect(result.remote?.sourceName == "GitHub")
        #expect(result.remote?.shortVersion == "99.0")
    }

    /// An official answer is a migration the tap declared, and is followed
    /// (`aTapMigratedToTheOfficialTapFollowsTheOfficialRules`); any other tap
    /// is not this copy's package.
    @Test(arguments: ["null", #""someone/else""#])
    func unreadableOrWrongTapCannotFallThrough(tap: String) async throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { _ in
            (0, Data("{\"casks\":[{\"token\":\"example\",\"tap\":\(tap),\"version\":\"2.0\"}]}".utf8))
        }
        let result = await UpdateChecker(sources: [source, Vendor()],
            brewFallback: BrewFallbackPolicy(allowedKeys: [InstallPreferenceKey.key(for: app)])).check([app])[0]
        guard case .error = result.status else { Issue.record("Must fail closed, got \(result.status)"); return }
        #expect(result.remote == nil)
    }

    @Test func commandFailureCannotFallThrough() async throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { _ in (1, Data()) }
        let result = await UpdateChecker(sources: [source, Vendor()],
            brewFallback: BrewFallbackPolicy(allowedKeys: [InstallPreferenceKey.key(for: app)])).check([app])[0]
        guard case .error = result.status else { Issue.record("Must fail closed"); return }
    }

    @Test func sameNamedCopyIsNotOwned() async throws {
        let (root, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let copy = InstalledApp(name: original.name, bundleID: original.bundleID, shortVersion: "1.0", buildVersion: nil,
                                path: root.appendingPathComponent("Other/Example.app"), isMASApp: false, sparkleFeedURL: nil)
        let source = ThirdPartyCaskSource(caskroomPaths: [root.appendingPathComponent("Caskroom").path]) { _ in
            Issue.record("An unrelated copy must not query the tap"); return nil
        }
        #expect(try await source.latestVersion(for: copy) == nil)
    }

    @Test func qualifiedInstallerKeepsTapAndUsesUpgrade() {
        #expect(HomebrewInstaller.installArguments(caskToken: "example/tap/example") ==
                ["upgrade", "--cask", "--greedy", "--", "example/tap/example"])
        #expect(HomebrewInstaller.installArguments(caskToken: "example/tap/example", dryRun: true) ==
                ["upgrade", "--cask", "--greedy", "--dry-run", "--", "example/tap/example"])
        #expect(HomebrewInstaller.installArguments(caskToken: "official") ==
                ["install", "--cask", "--force", "--", "official"])
    }
}
