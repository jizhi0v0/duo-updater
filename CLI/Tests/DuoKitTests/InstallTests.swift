import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// What `duo install` agrees to touch. These are the cases where saying yes
/// wrongly means replacing a bundle we shouldn't have, or failing halfway
/// through a route a CLI cannot finish.
@Suite struct InstallClassificationTests {

    private let fixturePath = "/Applications/Fixture.app"

    private func app(running: Bool = false, feed: URL? = nil) -> InstalledApp {
        InstalledApp(
            name: "Fixture", bundleID: "com.example.fixture",
            shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: fixturePath), isMASApp: false,
            sparkleFeedURL: feed)
    }

    private func result(
        source: String,
        vendorKind: VendorInstallerKind? = .dmg,
        appStore: AppStoreAvailability? = nil,
        app: InstalledApp? = nil
    ) -> UpdateResult {
        UpdateResult(
            app: app ?? self.app(),
            remote: RemoteVersion(
                shortVersion: "2.0", version: nil,
                downloadURL: URL(string: "https://example.com/fixture.dmg"),
                sourceName: source, appStore: appStore,
                requiresManualInstaller: false, vendorInstallerKind: vendorKind),
            status: .updateAvailable(latest: "2.0"))
    }

    private func settings(
        vendorPolicy: VendorInstallPolicy = .deferWhenRunning
    ) -> Settings {
        Settings(
            updateSettings: UpdateSettings(
                appStoreUpdateStrategy: .full, vendorInstallPolicy: vendorPolicy),
            ignoredKeys: [], skippedVersions: [:], customScanPaths: [],
            maxConcurrency: 12, keepBackups: true, githubToken: nil, alcove: nil)
    }

    private func environment(running: Bool = false) -> InstallEnvironment {
        InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: running ? [fixturePath] : [],
            stagedSelfUpdates: [:])
    }

    @Test func aVendorArchiveInstalls() {
        let decision = Install.classify(
            result(source: "Vendor"), settings: settings(), environment: environment())
        guard case .install(let route) = decision else {
            Issue.record("expected an install, got \(decision)")
            return
        }
        #expect(route == .vendor)
    }

    /// The store route is refused up front rather than attempted and failed
    /// halfway: it needs the privileged helper or the Accessibility API, and a
    /// standalone binary has neither.
    @Test func theAppStoreIsRefusedWithAReason() {
        let decision = Install.classify(
            result(source: "App Store",
                   appStore: AppStoreAvailability(
                    trackID: 1, availableRegion: "us", homeRegion: "us")),
            settings: settings(), environment: environment())
        guard case .refuse(let why) = decision else {
            Issue.record("expected a refusal, got \(decision)")
            return
        }
        #expect(why.contains("App Store"))
    }

    /// Detection-only apps have no artefact we vet, so there is nothing to
    /// install even though the row shows a newer version.
    @Test func detectionOnlyIsRefused() {
        let decision = Install.classify(
            result(source: "Vendor", vendorKind: nil),
            settings: settings(), environment: environment())
        guard case .refuse(let why) = decision else {
            Issue.record("expected a refusal, got \(decision)")
            return
        }
        #expect(why.contains("detection only"))
    }

    /// The same rule the app applies: don't swap a bundle under a running app
    /// that updates itself, unless the user asked for exactly that.
    @Test func aRunningSelfUpdaterIsDeferredUnlessOverridden() {
        let running = environment(running: true)
        guard case .refuse = Install.classify(
            result(source: "Vendor"), settings: settings(), environment: running)
        else {
            Issue.record("a running vendor app should defer under deferWhenRunning")
            return
        }
        guard case .install = Install.classify(
            result(source: "Vendor"),
            settings: settings(vendorPolicy: .alwaysOverwrite), environment: running)
        else {
            Issue.record("alwaysOverwrite should install anyway")
            return
        }
    }
}

@Suite struct InstallRouteTests {

    /// An unrecognised source falls to `.sparkle`, matching what the menu-bar
    /// app's switch has always done. Returning nil here instead would have
    /// silently stopped installing anything the app still installs.
    @Test func anUnknownSourceFallsToSparkle() {
        let unknown = UpdateResult(
            app: InstalledApp(
                name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1.0",
                buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Fixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: "2.0", version: nil, downloadURL: nil,
                sourceName: "Alcove", requiresManualInstaller: false),
            status: .updateAvailable(latest: "2.0"))
        #expect(InstallCoordinator.route(for: unknown, requiresInstaller: false) == .sparkle)
    }

    @Test func requiringAnInstallerBeatsTheSourceName() {
        let brew = UpdateResult(
            app: InstalledApp(
                name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1.0",
                buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Fixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: "2.0", version: nil, downloadURL: nil,
                sourceName: "Homebrew", requiresManualInstaller: true),
            status: .updateAvailable(latest: "2.0"))
        #expect(InstallCoordinator.route(for: brew, requiresInstaller: true) == .installer)
    }
}

@Suite struct RouteFilterParsingTests {

    @Test func namesResolveCaseInsensitively() throws {
        // The raw values are camelCase; nobody types `appStore` on a shell.
        #expect(try Install.routes(named: ["appstore"]).get() == [.appStore])
        #expect(try Install.routes(named: ["homebrew", "VENDOR"]).get() == [.homebrew, .vendor])
    }

    @Test func anUnknownNameIsRefusedAndListsTheValidOnes() {
        guard case .failure(let failure) = Install.routes(named: ["brew"]) else {
            Issue.record("expected a refusal for 'brew'")
            return
        }
        #expect(failure.description.contains("homebrew"),
                "the error has to say what to type instead")
    }

    @Test func noNamesMeansNoFilter() throws {
        #expect(try Install.routes(named: []).get().isEmpty)
    }
}
