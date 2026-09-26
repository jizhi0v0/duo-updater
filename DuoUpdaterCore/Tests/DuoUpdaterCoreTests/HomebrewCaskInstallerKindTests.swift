import Testing
import Foundation
@testable import DuoUpdaterCore

/// Issue #877: a cask whose `installer` is an unprivileged `script` was sent to
/// the system-installer route, which looks for a `.pkg` inside the download and
/// found only the vendor's installer `.app` — so quarkclouddrive's update failed
/// every time. brew runs that script itself. The installer shapes that need a
/// person keep the package route only when the download holds a package
/// `PackageInstaller` can reach; the rest are detection-only, where they used to
/// download in full and then fail the same way.
///
/// A `pkg` artifact is held to the same test: brew runs its `installer` under
/// sudo, which has no terminal here either, and a package in a `.zip` failed
/// the same way after the whole download.
///
/// Fixture: `Fixtures/homebrew-cask-installer-kinds.json`, ten entries copied
/// verbatim from `https://formulae.brew.sh/api/cask.json` on 2026-09-26
/// (`analytics` dropped), one per shape:
///
/// | token | artifact | url | kind |
/// |---|---|---|---|
/// | quarkclouddrive | `installer: [{script: {executable, args}}]` | `.dmg` | brew — brew runs it |
/// | expressvpn | `installer: [{script: {…, sudo: true}}]` | `.zip` | detection-only — needs a password, no package |
/// | figma-agent | `installer: [{manual: "Install Figma Agent.app"}]` | `.dmg` | detection-only — an `.app`, not a package |
/// | adguard | `pkg` | `.dmg` | package |
/// | pivy-app | `installer: [{manual: "pivy-….pkg"}]` | `.pkg` | package — the download is the package |
/// | qsync-client | `installer: [{manual: "Qsync Client.pkg"}]` | `.dmg` | package — at the image's root |
/// | autofirma | `installer: [{manual: "AutoFirma_….pkg"}]` | `.zip` | detection-only — only a `.dmg` is opened |
/// | fxfactory | `pkg` | `.zip` | detection-only — only a `.dmg` is opened |
/// | wch-ch34x-usb-serial-driver | `pkg: CH341SER_MAC/….pkg` | none | detection-only — in a folder |
/// | meta-quest-remote-desktop | `pkg` | none | package — the server names it `.pkg` |
struct HomebrewCaskInstallerKindTests {

    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/homebrew-cask-installer-kinds.json")

    private static func index() throws -> CaskIndex {
        try HomebrewCaskCatalog.index(fromCatalogJSON: Data(contentsOf: fixtureURL))
    }

    private static func entry(bundleID: String) throws -> CaskEntry {
        try #require(index().allByBundleID[bundleID]?.first)
    }

    @Test func anUnprivilegedInstallerScriptIsBrew() throws {
        #expect(try Self.entry(bundleID: "com.quark.clouddrive.desktop").installKind == .brew)
    }

    @Test func aSudoInstallerScriptWithNoPackageIsDetectionOnly() throws {
        #expect(try Self.entry(bundleID: "com.express.vpn").installKind == .detectionOnly)
    }

    @Test func aManualInstallerAppIsDetectionOnly() throws {
        #expect(try Self.entry(bundleID: "com.figma.agent").installKind == .detectionOnly)
    }

    @Test func aPkgArtifactStaysAPackage() throws {
        #expect(try Self.entry(bundleID: "com.adguard.mac.adguard").installKind == .package)
    }

    @Test func aManualInstallerWhoseDownloadIsThePackageStaysAPackage() throws {
        #expect(try Self.entry(bundleID: "net.cooperi.pivy-agent").installKind == .package)
    }

    @Test func aManualPackageAtADiskImageRootStaysAPackage() throws {
        #expect(try Self.entry(bundleID: "com.qnap.qsync").installKind == .package)
    }

    /// The `manual` target is a `.pkg`, but inside a `.zip`, which
    /// `PackageInstaller` hands to `verifyOpenable` unopened.
    @Test func aManualPackageInsideAZipIsDetectionOnly() throws {
        #expect(try Self.entry(bundleID: "es.gob.afirma").installKind == .detectionOnly)
    }

    /// The package route used to be taken for every `pkg` artifact; FxFactory's
    /// is inside a `.zip`, which `PackageInstaller` never opens.
    @Test func aPkgArtifactInsideAZipIsDetectionOnly() throws {
        #expect(try Self.entry(bundleID: "com.fxfactory.fxfactory").installKind == .detectionOnly)
    }

    /// The url has no extension; the server named the file `CH34XSER_MAC.ZIP`
    /// on 2026-09-26. The catalog cannot say that, but the package's folder
    /// does: a folder is in neither a bare package nor an image's top level.
    @Test func aPkgArtifactInAFolderBehindAnExtensionlessURLIsDetectionOnly() throws {
        #expect(try Self.entry(bundleID: "cn.wch.ch34xvcpdriver").installKind == .detectionOnly)
    }

    /// The url has no extension and the server names the download
    /// `Meta Quest Remote Desktop.pkg` (HEAD on 2026-09-26), which
    /// `PackageInstaller` opens.
    @Test func aPkgArtifactBehindAnExtensionlessURLStaysAPackage() throws {
        #expect(try Self.entry(bundleID: "com.meta.virtualdesktop").installKind == .package)
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

    /// No cask in the catalog has this shape; it is qsync-client's entry with the
    /// package moved into a folder, which `preferredPackage` (the image's top
    /// level only) would not find.
    @Test func aManualPackageBelowADiskImageRootIsDetectionOnly() throws {
        var casks = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.fixtureURL)) as? [[String: Any]])
        var qsync = try #require(casks.first { $0["token"] as? String == "qsync-client" })
        qsync["artifacts"] = (qsync["artifacts"] as? [Any])?.map { artifact -> Any in
            guard var dict = artifact as? [String: Any], dict["installer"] != nil else { return artifact }
            dict["installer"] = [["manual": "Qsync/Qsync Client.pkg"]]
            return dict
        }
        casks = [qsync]
        let index = try HomebrewCaskCatalog.index(
            fromCatalogJSON: JSONSerialization.data(withJSONObject: casks))
        #expect(try #require(index.allByBundleID["com.qnap.qsync"]?.first).installKind == .detectionOnly)
    }

    /// A brew-installed Figma Agent is still reported as having an update, but
    /// offers no install: no Update button, nothing for "Update All" to fetch, and
    /// no URL for `PackageInstaller` to download.
    @Test func aBrewInstalledFigmaAgentIsDetectionOnly() async throws {
        let path = "/Applications/ZZFixture-877/Figma Agent.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        let app = InstalledApp(
            name: "Figma Agent", bundleID: "com.figma.agent",
            shortVersion: "100.0.0", buildVersion: nil, path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = try #require(try await HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: Self.index()),
            inventory: BrewLocalInventory(installedTokens: ["figma-agent"]),
            hostOSVersion: "26.0"
        ).latestVersion(for: app))
        let latest = try #require(remote.shortVersion)
        #expect(remote.downloadURL == nil)
        #expect(remote.pageURL == URL(string: "https://formulae.brew.sh/cask/figma-agent"))

        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: latest))
        let environment = InstallEnvironment(
            isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        let settings = UpdateSettings(
            appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite)
        let canAutoInstall = UpdatePolicy.canAutoInstall(
            result, settings: settings, environment: environment)
        let requiresInstaller = UpdatePolicy.requiresInstaller(result, environment: environment)
        #expect(!canAutoInstall)
        #expect(!requiresInstaller)
        #expect(UpdateRoute.resolve(RouteInputs(
            isToolboxManaged: false, isTestFlight: false, defersToSelfUpdater: false,
            isMajorUpgrade: result.isMajorUpgrade, canAutoInstall: canAutoInstall,
            requiresInstaller: requiresInstaller, stagedFileName: nil,
            hasAppStoreAvailability: false, appStoreManagedHere: false, appStoreGate: .none
        )) == .detectionOnly)
    }

    /// A brew-installed FxFactory, which went to the system installer and failed
    /// there after the download, is detection-only now.
    @Test func aBrewInstalledFxFactoryIsDetectionOnly() async throws {
        let path = "/Applications/ZZFixture-877/FxFactory.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        let app = InstalledApp(
            name: "FxFactory", bundleID: "com.fxfactory.FxFactory",
            shortVersion: "9.0.0", buildVersion: nil, path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = try #require(try await HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: Self.index()),
            inventory: BrewLocalInventory(installedTokens: ["fxfactory"]),
            hostOSVersion: "26.0"
        ).latestVersion(for: app))
        #expect(remote.shortVersion == "9.0.6")
        #expect(remote.downloadURL == nil)

        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "9.0.6"))
        let environment = InstallEnvironment(
            isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        #expect(!UpdatePolicy.requiresInstaller(result, environment: environment))
        #expect(!UpdatePolicy.canAutoInstall(
            result,
            settings: UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite),
            environment: environment))
    }

    /// The package route is unchanged for a cask that has one: the URL is carried
    /// and the row goes to the system installer.
    @Test func aBrewInstalledQsyncClientGoesToTheSystemInstaller() async throws {
        let path = "/Applications/ZZFixture-877/Qsync Client.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        let app = InstalledApp(
            name: "Qsync Client", bundleID: "com.qnap.qsync",
            shortVersion: "5.0.0", buildVersion: nil, path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = try #require(try await HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: Self.index()),
            inventory: BrewLocalInventory(installedTokens: ["qsync-client"]),
            hostOSVersion: "26.0"
        ).latestVersion(for: app))
        #expect(remote.downloadURL == URL(
            string: "https://download.qnap.com/Storage/Utility/QNAPQsyncClientMac-5.1.7.0923.dmg"))
        #expect(remote.requiresManualInstaller)

        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "5.1.7"))
        let environment = InstallEnvironment(
            isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        let requiresInstaller = UpdatePolicy.requiresInstaller(result, environment: environment)
        #expect(requiresInstaller)
        #expect(!UpdatePolicy.canAutoInstall(
            result,
            settings: UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite),
            environment: environment))
        #expect(InstallCoordinator.route(for: result, requiresInstaller: requiresInstaller) == .installer)
    }
}
