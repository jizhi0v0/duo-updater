import Testing
import Foundation
@testable import DuoUpdaterCore

/// Normal cask artifacts, including PKGs and sudo scripts, run through Brew's
/// downloader, prerequisite checks and existing AskPass channel. A declared
/// manual installer is prepared by Brew, then opened for the person to finish.
/// Its exact path survives independently of the wrapper's extension or depth.
///
/// The ten catalog entries in `homebrew-cask-installer-kinds.json` retain the
/// real installer shapes collected on 2026-09-26. The tests pin the resolved
/// platform instead of depending on the machine running the suite.
struct HomebrewCaskInstallerKindTests {
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/homebrew-cask-installer-kinds.json")

    private static func index() throws -> CaskIndex {
        try HomebrewCaskCatalog.index(fromCatalogJSON: Data(contentsOf: fixtureURL), platformTag: "arm64_tahoe")
    }

    private static func entry(bundleID: String) throws -> CaskEntry {
        try #require(index().allByBundleID[bundleID.lowercased()]?.first)
    }

    @Test func complexManualCasksRemainDetectionOnly() {
        let artifacts: [[String: Any]] = [["installer": [["manual": "Install.app"]]]]
        #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts,
                    dependsOn: ["cask": ["dependency"]]) == .detectionOnly)
        #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts,
                    conflictsWith: ["cask": ["conflict"]]) == .detectionOnly)
        #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts,
                    disabled: true) == .detectionOnly)
        #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts + [["preflight": NSNull()]]) == .detectionOnly)
        #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts + [["binary": ["tool"]]]) == .detectionOnly)
        #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts + [["uninstall_postflight_steps": []]])
                == .manualInstaller(path: "Install.app"))
        #expect(HomebrewCaskCatalog.installKind(artifacts: [["installer": [
                    ["manual": "Install.app"], ["script": "run"]]]]) == .detectionOnly)
    }

    @Test func anUnprivilegedInstallerScriptIsBrew() throws {
        #expect(try Self.entry(bundleID: "com.quark.clouddrive.desktop").installKind == .brew)
    }

    @Test func aSudoInstallerScriptUsesBrewAndAskPass() throws {
        #expect(try Self.entry(bundleID: "com.express.vpn").installKind == .brew)
    }

    @Test func aManualInstallerAppRetainsItsDeclaredPath() throws {
        #expect(try Self.entry(bundleID: "com.figma.agent").installKind
                == .manualInstaller(path: "Install Figma Agent.app"))
    }

    @Test(arguments: ["com.adguard.mac.adguard", "com.fxfactory.FxFactory",
                      "cn.wch.CH34xVCPDriver", "com.meta.virtualdesktop"])
    func normalPackagesUseBrewRegardlessOfWrapperOrNestedPath(bundleID: String) throws {
        #expect(try Self.entry(bundleID: bundleID).installKind == .brew)
    }

    @Test func aManualPackageIsNotConvertedToAnUnattendedPackage() throws {
        #expect(try Self.entry(bundleID: "com.gyazo.menu").installKind
                == .manualInstaller(path: "Gyazo-11.2.0.pkg"))
        #expect(try Self.entry(bundleID: "com.qnap.qsync").installKind
                == .manualInstaller(path: "Qsync Client.pkg"))
    }

    @Test func aManualPackageInsideAZipRetainsItsPlatformSpecificPath() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let arm = try HomebrewCaskCatalog.index(fromCatalogJSON: data, platformTag: "arm64_tahoe")
        let intel = try HomebrewCaskCatalog.index(fromCatalogJSON: data, platformTag: "tahoe")
        #expect(arm.byToken["autofirma"]?.installKind
                == .manualInstaller(path: "AutoFirma_1_9_2_aarch64_signed.pkg"))
        #expect(intel.byToken["autofirma"]?.installKind
                == .manualInstaller(path: "AutoFirma_1_9_2_x64_signed.pkg"))
    }

    @Test func aManualPackageBelowTheImageRootRetainsItsWholePath() throws {
        let artifacts: [[String: Any]] = [["installer": [["manual": "Qsync/Qsync Client.pkg"]]]]
        #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts)
                == .manualInstaller(path: "Qsync/Qsync Client.pkg"))
    }

    @Test(arguments: ["", "/Applications/Install.app", "../Install.app", "Folder/../Install.app",
                      "Folder//Install.app", "Folder/./Install.app", "Folder/Install.app/"])
    func unsafeManualPathsStayDetectionOnly(path: String) {
        let artifacts: [[String: Any]] = [["installer": [["manual": path]]]]
        #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts) == .detectionOnly)
    }

    @Test func malformedOrAmbiguousManualDeclarationsStayDetectionOnly() {
        let declarations: [Any] = [
            [["installer": "Install.app"]],
            [["installer": []]],
            [["installer": [["manual": 42]]]],
            [["installer": [["manual": NSNull()]]]],
            [["installer": [["manual": "One.app"], ["manual": "Two.app"]]]],
            [["installer": [["manual": "Install.app", "script": "run"]]]],
        ]
        for artifacts in declarations {
            #expect(HomebrewCaskCatalog.installKind(artifacts: artifacts) == .detectionOnly)
        }
    }

    private static func sourceResult(token: String, name: String, bundleID: String,
                                     installed: String) async throws -> UpdateResult {
        let path = "/Applications/ZZFixture-877/\(name).app"
        #expect(!FileManager.default.fileExists(atPath: path))
        let app = InstalledApp(
            name: name, bundleID: bundleID, shortVersion: installed, buildVersion: nil,
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
        let remote = try #require(try await HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: Self.index()),
            inventory: BrewLocalInventory(installedTokens: [token]),
            hostOSVersion: "26.0", hostArchitecture: .arm64
        ).latestVersion(for: app))
        return UpdateResult(app: app, remote: remote, status: UpdateChecker.evaluate(installed: app, remote: remote))
    }

    private static let settings = UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite)

    private static func environment(helper: Bool = false) -> InstallEnvironment {
        InstallEnvironment(isHelperEnabled: helper, runningAppPaths: [], stagedSelfUpdates: [:],
                           packageInstallerAvailable: helper)
    }

    /// The original script regression remains an end-to-end source/policy check.
    @Test func aBrewInstalledQuarkUpdatesThroughBrew() async throws {
        let result = try await Self.sourceResult(token: "quarkclouddrive", name: "QuarkCloudDrive",
                                                 bundleID: "com.quark.clouddrive.desktop", installed: "7.0.0")
        #expect(result.remote?.shortVersion == "7.3.5.810")
        #expect(result.remote?.sourceIdentifier == "quarkclouddrive")
        #expect(result.remote?.requiresManualInstaller == false)
        #expect(result.remote?.homebrewManualInstaller == nil)
        #expect(result.hasUpdate)
        #expect(!UpdatePolicy.requiresInstaller(result, environment: Self.environment()))
        #expect(UpdatePolicy.canAutoInstall(result, settings: Self.settings, environment: Self.environment()))
        #expect(InstallCoordinator.route(for: result, requiresInstaller: false) == .homebrew)
    }

    @Test func aNormalBrewPackageUsesBrewEvenWithAnApprovedPackageHelper() async throws {
        let result = try await Self.sourceResult(token: "adguard", name: "AdGuard",
                                                 bundleID: "com.adguard.mac.adguard", installed: "2.18.0")
        #expect(result.hasUpdate)
        #expect(result.remote?.requiresManualInstaller == false)
        #expect(result.remote?.homebrewManualInstaller == nil)
        #expect(!UpdatePolicy.requiresInstaller(result, environment: Self.environment(helper: true)))
        #expect(UpdatePolicy.canAutoInstall(result, settings: Self.settings, environment: Self.environment(helper: true)))
        #expect(InstallCoordinator.route(for: result, requiresInstaller: false) == .homebrew)
    }

    /// The old ZIP-to-PackageInstaller failure now has a normal Brew action.
    @Test func aBrewInstalledFxFactoryUpdatesThroughBrew() async throws {
        let result = try await Self.sourceResult(token: "fxfactory", name: "FxFactory",
                                                 bundleID: "com.fxfactory.FxFactory", installed: "9.0.0")
        #expect(result.remote?.shortVersion == "9.0.6")
        #expect(result.remote?.requiresManualInstaller == false)
        #expect(result.hasUpdate)
        #expect(!UpdatePolicy.requiresInstaller(result, environment: Self.environment()))
        #expect(UpdatePolicy.canAutoInstall(result, settings: Self.settings, environment: Self.environment()))
        #expect(InstallCoordinator.route(for: result, requiresInstaller: false) == .homebrew)
    }

    @Test func aBrewInstalledFigmaAgentOffersTheDeclaredManualInstaller() async throws {
        let result = try await Self.sourceResult(token: "figma-agent", name: "Figma Agent",
                                                 bundleID: "com.figma.agent", installed: "100.0.0")
        #expect(result.remote?.homebrewManualInstaller == "Install Figma Agent.app")
        #expect(result.remote?.requiresManualInstaller == true)
        #expect(result.remote?.pageURL == URL(string: "https://formulae.brew.sh/cask/figma-agent"))
        #expect(result.hasUpdate)
        let facts = Self.environment()
        #expect(!UpdatePolicy.canAutoInstall(result, settings: Self.settings, environment: facts))
        #expect(UpdatePolicy.requiresInstaller(result, environment: facts))
        #expect(InstallCoordinator.route(for: result, requiresInstaller: true) == .homebrew)
    }

    @Test func aManualPackageIsPreparedByBrewForInteractiveHandoff() async throws {
        let result = try await Self.sourceResult(token: "qsync-client", name: "Qsync Client",
                                                 bundleID: "com.qnap.qsync", installed: "5.0.0")
        #expect(result.remote?.homebrewManualInstaller == "Qsync Client.pkg")
        #expect(result.remote?.requiresManualInstaller == true)
        #expect(result.hasUpdate)
        #expect(UpdatePolicy.requiresInstaller(result, environment: Self.environment(helper: true)))
        #expect(!UpdatePolicy.canAutoInstall(result, settings: Self.settings, environment: Self.environment(helper: true)))
        #expect(InstallCoordinator.route(for: result, requiresInstaller: true) == .homebrew)
    }

    /// A helper-trusted bundle ID makes the policy's ordinary PKG fast path
    /// reachable. A manual declaration must still withhold unattended install.
    @Test func aManualCaskCannotTakeThePackageHelpersUnattendedShortcut() {
        let app = InstalledApp(
            name: "Manual fixture", bundleID: "io.tailscale.ipn.macsys", shortVersion: "1.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-877/Manual.app"), isMASApp: false, sparkleFeedURL: nil)
        #expect(PackageInstallTrust.teamIdentifier(for: app.bundleID) != nil)
        var remote = RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: URL(string: "https://example.invalid/cask.dmg"),
                                   sourceName: "Homebrew", sourceIdentifier: "manual-fixture", requiresManualInstaller: true)
        remote.homebrewManualInstaller = "Install.app"
        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "2.0"))
        #expect(UpdatePolicy.requiresInstaller(result, environment: Self.environment(helper: true)))
        #expect(!UpdatePolicy.canAutoInstall(result, settings: Self.settings, environment: Self.environment(helper: true)))
        #expect(InstallCoordinator.route(for: result, requiresInstaller: true) == .homebrew)
        #expect(!AutomaticInstall.supports(.homebrew, packageInstallerAvailable: true))
    }
}
