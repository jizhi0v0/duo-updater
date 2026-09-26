import Testing
import Foundation
@testable import DuoUpdaterCore

/// Issue #877: a cask whose `installer` is an unprivileged `script` was sent to
/// the system-installer route, which looks for a `.pkg` inside the download and
/// found only the vendor's installer `.app` — so quarkclouddrive's update failed
/// every time. brew runs that script itself; the other installer shapes still
/// need a person and keep the package route.
///
/// Fixture: `Fixtures/homebrew-cask-installer-kinds.json`, four entries copied
/// verbatim from `https://formulae.brew.sh/api/cask.json` on 2026-09-26
/// (`analytics` dropped), one per shape:
///
/// | token | artifact | package route? |
/// |---|---|---|
/// | quarkclouddrive | `installer: [{script: {executable, args}}]` | no — brew runs it |
/// | expressvpn | `installer: [{script: {…, sudo: true}}]` | yes — needs a password |
/// | figma-agent | `installer: [{manual: …}]` | yes — brew only prints "open …" |
/// | adguard | `pkg` | yes |
struct HomebrewCaskInstallerKindTests {

    private static func index() throws -> CaskIndex {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/homebrew-cask-installer-kinds.json")
        return try HomebrewCaskCatalog.index(fromCatalogJSON: Data(contentsOf: url))
    }

    private static func entry(bundleID: String) throws -> CaskEntry {
        try #require(index().allByBundleID[bundleID]?.first)
    }

    @Test func anUnprivilegedInstallerScriptIsNotAPackage() throws {
        #expect(try !Self.entry(bundleID: "com.quark.clouddrive.desktop").isPkg)
    }

    @Test func aSudoInstallerScriptStaysAPackage() throws {
        #expect(try Self.entry(bundleID: "com.express.vpn").isPkg)
    }

    @Test func aManualInstallerStaysAPackage() throws {
        #expect(try Self.entry(bundleID: "com.figma.agent").isPkg)
    }

    @Test func aPkgArtifactStaysAPackage() throws {
        #expect(try Self.entry(bundleID: "com.adguard.mac.adguard").isPkg)
    }

    /// The issue's path end to end: a brew-installed Quark resolves through
    /// `HomebrewCaskSource`, and the row routes to `brew` — not to the system
    /// installer that failed.
    @Test func aBrewInstalledQuarkUpdatesThroughBrew() async throws {
        let path = "/Applications/ZZFixture-877/QuarkCloudDrive.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        let app = InstalledApp(
            name: "QuarkCloudDrive", bundleID: "com.quark.clouddrive.desktop",
            shortVersion: "7.0.0", buildVersion: nil, path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = try #require(try await HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: Self.index()),
            inventory: BrewLocalInventory(installedTokens: ["quarkclouddrive"]),
            hostOSVersion: "26.0"
        ).latestVersion(for: app))
        #expect(remote.shortVersion == "7.3.5.810")
        #expect(remote.sourceIdentifier == "quarkclouddrive")
        #expect(!remote.requiresManualInstaller)

        let result = UpdateResult(
            app: app, remote: remote, status: .updateAvailable(latest: "7.3.5.810"))
        let environment = InstallEnvironment(
            isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        let requiresInstaller = UpdatePolicy.requiresInstaller(result, environment: environment)
        #expect(!requiresInstaller)
        #expect(UpdatePolicy.canAutoInstall(
            result,
            settings: UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite),
            environment: environment))
        #expect(InstallCoordinator.route(for: result, requiresInstaller: requiresInstaller) == .homebrew)
    }
}
