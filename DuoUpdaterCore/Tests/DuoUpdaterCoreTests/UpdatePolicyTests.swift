import Testing
import Foundation
@testable import DuoUpdaterCore

/// Characterisation tests for the install-eligibility policy, written against
/// the behaviour of `AppListModel.canAutoInstall` / `requiresInstaller` /
/// `defersToSelfUpdater` as they lived inside the app before the move to
/// `UpdatePolicy`. Every row below was derived by tracing the pre-move code,
/// not from what the policy "should" do — if a row looks wrong, the bug is in
/// the original and the table must not be "fixed" to paper over a behaviour
/// change. The tables exist to prove the move is byte-for-byte; they double as
/// the policy's first unit tests.

private let fixturePath = "/Applications/Fixture.app"

private func fixtureApp(
    sparkleEdKey: String? = nil,
    sparkleFeedURL: URL? = nil,
    isiOSAppOnMac: Bool = false
) -> InstalledApp {
    InstalledApp(
        name: "Fixture",
        bundleID: "com.example.fixture",
        shortVersion: "1.0",
        buildVersion: "1",
        path: URL(fileURLWithPath: fixturePath),
        isMASApp: false,
        isiOSAppOnMac: isiOSAppOnMac,
        sparkleFeedURL: sparkleFeedURL,
        sparkleEdPublicKey: sparkleEdKey)
}

private func fixtureResult(
    source: String,
    displayVersion: String? = "2.0",
    downloadURL: URL? = URL(string: "https://example.com/fixture.zip"),
    edSignature: String? = nil,
    sourceIdentifier: String? = nil,
    requiresManualInstaller: Bool = false,
    vendorInstallerKind: VendorInstallerKind? = nil,
    appStore: AppStoreAvailability? = nil,
    app: InstalledApp = fixtureApp()
) -> UpdateResult {
    UpdateResult(
        app: app,
        remote: RemoteVersion(
            shortVersion: displayVersion,
            version: nil,
            downloadURL: downloadURL,
            edSignature: edSignature,
            sourceName: source,
            sourceIdentifier: sourceIdentifier,
            appStore: appStore,
            requiresManualInstaller: requiresManualInstaller,
            vendorInstallerKind: vendorInstallerKind),
        status: .updateAvailable(latest: displayVersion ?? "2.0"))
}

private func defaultSettings(
    strategy: AppStoreUpdateStrategy = .full,
    policy: VendorInstallPolicy = .deferWhenRunning
) -> UpdateSettings {
    UpdateSettings(appStoreUpdateStrategy: strategy, vendorInstallPolicy: policy)
}

private func environment(
    helperEnabled: Bool = false,
    running: Set<String> = [],
    staged: [String: StagedSelfUpdate] = [:]
) -> InstallEnvironment {
    InstallEnvironment(isHelperEnabled: helperEnabled, runningAppPaths: running, stagedSelfUpdates: staged)
}

private func staged(_ version: String) -> StagedSelfUpdate {
    StagedSelfUpdate(version: version, buildVersion: nil, stagedBundlePath: URL(fileURLWithPath: "/tmp/staged.app"))
}

private func storeAvailability(
    availableRegion: String = "us",
    homeRegion: String? = "us",
    latestMacCompatible: Bool? = nil
) -> AppStoreAvailability {
    AppStoreAvailability(
        trackID: 123, availableRegion: availableRegion, homeRegion: homeRegion,
        latestMacCompatible: latestMacCompatible)
}

// MARK: - canAutoInstall

@Test func canAutoInstallCoversEveryBranch() {
    let cases: [(name: String, result: UpdateResult, settings: UpdateSettings, environment: InstallEnvironment, expected: Bool)] = [
        // Staged latest: the app's own updater owns it — Relaunch, never our install.
        (
            name: "staged latest is not auto-installable even when otherwise installable",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(),
            environment: environment(staged: [fixturePath: staged("2.0")]),
            expected: false
        ),
        // Sparkle, signed feed (non-empty SUPublicEDKey): requires an EdDSA signature.
        (
            name: "sparkle signed feed with signature is auto-installable",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.dmg"),
                edSignature: "sig", app: fixtureApp(sparkleEdKey: "key")),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "sparkle signed feed without signature is not auto-installable",
            result: fixtureResult(source: "Sparkle", app: fixtureApp(sparkleEdKey: "key")),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        // Sparkle, unsigned feed: only an extractable archive enclosure qualifies.
        (
            name: "sparkle unsigned feed with archive enclosure is auto-installable",
            result: fixtureResult(source: "Sparkle", app: fixtureApp(sparkleEdKey: "")),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "sparkle feed with no Ed key (nil) is treated as unsigned",
            result: fixtureResult(source: "Sparkle", app: fixtureApp(sparkleEdKey: nil)),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "sparkle unsigned feed with pkg enclosure is not auto-installable",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.pkg"),
                app: fixtureApp(sparkleEdKey: nil)),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "sparkle unsigned feed with no enclosure URL is not auto-installable",
            result: fixtureResult(source: "Sparkle", downloadURL: nil, app: fixtureApp(sparkleEdKey: nil)),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "sparkle unsigned feed with unrecognised enclosure extension is not auto-installable",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.exe"),
                app: fixtureApp(sparkleEdKey: nil)),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        // Homebrew: needs the cask token and must not require the system installer.
        (
            name: "homebrew cask with token and no manual installer is auto-installable",
            result: fixtureResult(source: "Homebrew", sourceIdentifier: "fixture"),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "homebrew without a cask token is not auto-installable",
            result: fixtureResult(source: "Homebrew", sourceIdentifier: nil),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "homebrew pkg cask (requiresManualInstaller) is not auto-installable",
            result: fixtureResult(source: "Homebrew", sourceIdentifier: "fixture", requiresManualInstaller: true),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        // Vendor / GitHub: needs a resolved installer kind and no manual installer.
        (
            name: "vendor with an installer archive is auto-installable",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "vendor with installer kind but requiresManualInstaller is not auto-installable",
            result: fixtureResult(source: "Vendor", requiresManualInstaller: true, vendorInstallerKind: .zip),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "vendor with no installer kind (detection-only) is not auto-installable",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: nil),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "github release with an installer archive is auto-installable",
            result: fixtureResult(source: "GitHub", vendorInstallerKind: .dmg),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        // App Store: needs availability info, and the route gate (full → helper).
        (
            name: "app store with full strategy and helper approved is auto-installable",
            result: fixtureResult(source: "App Store", appStore: storeAvailability()),
            settings: defaultSettings(strategy: .full), environment: environment(helperEnabled: true),
            expected: true
        ),
        (
            name: "app store with full strategy but helper not approved is not auto-installable",
            result: fixtureResult(source: "App Store", appStore: storeAvailability()),
            settings: defaultSettings(strategy: .full), environment: environment(helperEnabled: false),
            expected: false
        ),
        (
            name: "app store with incremental strategy needs no helper",
            result: fixtureResult(source: "App Store", appStore: storeAvailability()),
            settings: defaultSettings(strategy: .incremental), environment: environment(helperEnabled: false),
            expected: true
        ),
        (
            name: "app store region mismatch is not auto-installable",
            result: fixtureResult(
                source: "App Store",
                appStore: storeAvailability(availableRegion: "cn", homeRegion: "us")),
            settings: defaultSettings(), environment: environment(helperEnabled: true),
            expected: false
        ),
        (
            name: "app store build that dropped Mac support is not auto-installable",
            result: fixtureResult(
                source: "App Store", appStore: storeAvailability(latestMacCompatible: false)),
            settings: defaultSettings(), environment: environment(helperEnabled: true),
            expected: false
        ),
        (
            name: "iOS-on-Mac app is not auto-installable",
            result: fixtureResult(
                source: "App Store", appStore: storeAvailability(), app: fixtureApp(isiOSAppOnMac: true)),
            settings: defaultSettings(), environment: environment(helperEnabled: true),
            expected: false
        ),
        (
            name: "app store without availability info is not auto-installable",
            result: fixtureResult(source: "App Store", appStore: nil),
            settings: defaultSettings(), environment: environment(helperEnabled: true),
            expected: false
        ),
        // Everything else: managed sources and unknown ones are never a one-click.
        (
            name: "toolbox-managed result is not auto-installable",
            result: fixtureResult(source: "Toolbox", requiresManualInstaller: true),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "testflight result is not auto-installable",
            result: fixtureResult(source: "TestFlight", requiresManualInstaller: true),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "no remote is not auto-installable",
            result: UpdateResult(app: fixtureApp(), remote: nil, status: .unknown),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "unknown source is not auto-installable",
            result: fixtureResult(source: "SomeOtherSource"),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
    ]
    for c in cases {
        let actual = UpdatePolicy.canAutoInstall(c.result, settings: c.settings, environment: c.environment)
        #expect(actual == c.expected, "\(c.name): expected \(c.expected), got \(actual)")
    }
}

// MARK: - requiresInstaller

@Test func requiresInstallerCoversEveryBranch() {
    let cases: [(name: String, result: UpdateResult, settings: UpdateSettings, environment: InstallEnvironment, expected: Bool)] = [
        (
            name: "staged latest never routes to the system installer",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .pkg),
            settings: defaultSettings(),
            environment: environment(staged: [fixturePath: staged("2.0")]),
            expected: false
        ),
        (
            name: "homebrew pkg cask needs the system installer",
            result: fixtureResult(source: "Homebrew", sourceIdentifier: "fixture", requiresManualInstaller: true),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "homebrew archive cask does not need the system installer",
            result: fixtureResult(source: "Homebrew", sourceIdentifier: "fixture", requiresManualInstaller: false),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "vendor pkg needs the system installer",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .pkg),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "vendor zip does not need the system installer",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "vendor detection-only (no installer kind) does not need the system installer",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: nil),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "github pkg needs the system installer",
            result: fixtureResult(source: "GitHub", vendorInstallerKind: .pkg),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "sparkle never routes to the system installer",
            result: fixtureResult(source: "Sparkle", app: fixtureApp(sparkleEdKey: "key")),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "app store never routes to the system installer",
            result: fixtureResult(source: "App Store", appStore: storeAvailability()),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "toolbox never routes to the system installer",
            result: fixtureResult(source: "Toolbox", requiresManualInstaller: true),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "testflight never routes to the system installer",
            result: fixtureResult(source: "TestFlight", requiresManualInstaller: true),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "no remote never routes to the system installer",
            result: UpdateResult(app: fixtureApp(), remote: nil, status: .unknown),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
    ]
    for c in cases {
        let actual = UpdatePolicy.requiresInstaller(c.result, environment: c.environment)
        #expect(actual == c.expected, "\(c.name): expected \(c.expected), got \(actual)")
    }
}

// MARK: - defersToSelfUpdater

@Test func defersToSelfUpdaterCoversEveryBranch() {
    let cases: [(name: String, result: UpdateResult, settings: UpdateSettings, environment: InstallEnvironment, expected: Bool)] = [
        (
            name: "alwaysOverwrite policy never defers, even while running",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(policy: .alwaysOverwrite),
            environment: environment(running: [fixturePath]),
            expected: false
        ),
        (
            name: "defer policy ignores a not-running app",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: []),
            expected: false
        ),
        (
            name: "running vendor app defers to its own updater",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: true
        ),
        (
            name: "running detection-only vendor app does not defer (nothing installable to defer)",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: nil),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: false
        ),
        (
            name: "running sparkle app with a feed defers to its own updater",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.dmg"),
                edSignature: "sig", app: fixtureApp(sparkleEdKey: "key", sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: true
        ),
        (
            name: "running sparkle app without a feed URL does not defer",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.dmg"),
                edSignature: "sig", app: fixtureApp(sparkleEdKey: "key", sparkleFeedURL: nil)),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: false
        ),
        (
            name: "running sparkle app that is not installable does not defer",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.pkg"),
                app: fixtureApp(sparkleEdKey: nil, sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: false
        ),
        (
            name: "running homebrew app never defers to a self-updater",
            result: fixtureResult(source: "Homebrew", sourceIdentifier: "fixture"),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: false
        ),
        (
            name: "running app store app never defers to a self-updater",
            result: fixtureResult(source: "App Store", appStore: storeAvailability()),
            settings: defaultSettings(strategy: .incremental, policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: false
        ),
        (
            name: "running toolbox-managed app never defers to a self-updater",
            result: fixtureResult(source: "Toolbox", requiresManualInstaller: true),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: false
        ),
        (
            name: "staged latest wins over deferral (Relaunch owns it)",
            result: fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath], staged: [fixturePath: staged("2.0")]),
            expected: false
        ),
    ]
    for c in cases {
        let actual = UpdatePolicy.defersToSelfUpdater(c.result, settings: c.settings, environment: c.environment)
        #expect(actual == c.expected, "\(c.name): expected \(c.expected), got \(actual)")
    }
}

// MARK: - isRunning

@Test func isRunningMatchesTheNormalizedBundlePath() {
    let plain = fixtureResult(source: "Vendor", vendorInstallerKind: .zip)
    #expect(UpdatePolicy.isRunning(plain, environment: environment(running: [fixturePath])))
    #expect(!UpdatePolicy.isRunning(plain, environment: environment(running: [])))
    #expect(!UpdatePolicy.isRunning(plain, environment: environment(running: ["/Applications/Other.app"])))

    // A process can stay mapped to DuoUpdater's temporary staging name after a
    // hot swap — the running set carries the plain bundle, the app path the
    // staged variant, and they must still match.
    let stagedPathApp = fixtureResult(
        source: "Vendor", vendorInstallerKind: .zip,
        app: InstalledApp(
            name: "Fixture", bundleID: "com.example.fixture",
            shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/.duoupdater-staged-Fixture.app"),
            isMASApp: false, sparkleFeedURL: nil))
    #expect(UpdatePolicy.isRunning(stagedPathApp, environment: environment(running: [fixturePath])))
}

// MARK: - actionableStaged

@Test func actionableStagedOnlyWhenTheStagedBuildIsTheLatest() {
    let remote = fixtureResult(source: "Vendor", vendorInstallerKind: .zip)

    #expect(UpdatePolicy.actionableStaged(remote, staged: nil) == nil)
    #expect(UpdatePolicy.actionableStaged(remote, staged: staged("2.0")) != nil, "staged == latest is actionable")
    #expect(UpdatePolicy.actionableStaged(remote, staged: staged("1.5")) == nil, "staged trailing the latest is not actionable")
    #expect(UpdatePolicy.actionableStaged(remote, staged: staged("3.0")) != nil, "a staged build ahead of the latest stays actionable")

    // No remote version to compare against: nothing proves the staged build
    // trails, so it stays actionable.
    let noRemote = UpdateResult(app: fixtureApp(), remote: nil, status: .unknown)
    #expect(UpdatePolicy.actionableStaged(noRemote, staged: staged("9.9")) != nil)
}

// MARK: - runtimeBundlePath

@Test func runtimeBundlePathNormalizesStagedSuffixes() {
    func path(_ name: String) -> String {
        UpdatePolicy.runtimeBundlePath(URL(fileURLWithPath: "/Applications/\(name)"))
    }
    #expect(path("Fixture.app") == "/Applications/Fixture.app")
    #expect(path(".duoupdater-staged-Fixture.app") == "/Applications/Fixture.app")
    #expect(path("Fixture.app.duoupdater-old") == "/Applications/Fixture.app")
    #expect(path("Fixture.app.duoupdater-new") == "/Applications/Fixture.app")
}
