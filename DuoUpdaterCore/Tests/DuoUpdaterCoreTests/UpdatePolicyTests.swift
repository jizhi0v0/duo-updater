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
    isiOSAppOnMac: Bool = false,
    path: String = fixturePath
) -> InstalledApp {
    InstalledApp(
        name: "Fixture",
        bundleID: "com.example.fixture",
        shortVersion: "1.0",
        buildVersion: "1",
        path: URL(fileURLWithPath: path),
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
    policy: VendorInstallPolicy = .deferWhenRunning,
    declinedElevation: Set<String> = []
) -> UpdateSettings {
    UpdateSettings(appStoreUpdateStrategy: strategy, vendorInstallPolicy: policy,
                   declinedElevationKeys: declinedElevation)
}

private func environment(
    helperEnabled: Bool = false,
    running: Set<String> = [],
    staged: [String: StagedSelfUpdate] = [:],
    elevationRequired: Set<String> = []
) -> InstallEnvironment {
    InstallEnvironment(isHelperEnabled: helperEnabled, runningAppPaths: running,
                       stagedSelfUpdates: staged, elevationRequiredPaths: elevationRequired)
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
        (
            name: "sparkle signed pkg is handled by the system installer, not the archive path",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.pkg"),
                edSignature: "sig", app: fixtureApp(sparkleEdKey: "key")),
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
            name: "sparkle archive does not route to the system installer",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.dmg"),
                edSignature: "sig", app: fixtureApp(sparkleEdKey: "key")),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "sparkle signed pkg routes to the system installer",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.pkg"),
                edSignature: "sig", app: fixtureApp(sparkleEdKey: "key")),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "sparkle unsigned pkg stays detection-only",
            result: fixtureResult(
                source: "Sparkle", downloadURL: URL(string: "https://example.com/fixture.pkg"),
                app: fixtureApp(sparkleEdKey: nil)),
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
            name: "GitHub source defers while running — those apps self-update too",
            result: fixtureResult(source: "GitHub", vendorInstallerKind: .dmg),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: true
        ),
        (
            name: "GitHub source still installs under alwaysOverwrite",
            result: fixtureResult(source: "GitHub", vendorInstallerKind: .dmg),
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

// MARK: - nudgeableStaged

/// The periodic "Relaunch to apply it" reminder fires every 5 minutes for as
/// long as a build stays staged. It used to ask only `actionableStaged`, which
/// knows nothing about ignore or skip — so an ignored app went on banner-nagging
/// forever while its row in the app showed nothing but the Ignored tag.
@Test func anIgnoredAppIsNeverNudgedAboutItsStagedBuild() {
    let remote = fixtureResult(source: "Vendor", vendorInstallerKind: .zip)
    let never: (String) -> Bool = { _ in false }

    #expect(
        UpdatePolicy.nudgeableStaged(
            remote, staged: staged("2.0"), isIgnored: false, isVersionSkipped: never) != nil,
        "a visible app with the latest staged is still worth a nudge")
    #expect(
        UpdatePolicy.nudgeableStaged(
            remote, staged: staged("2.0"), isIgnored: true, isVersionSkipped: never) == nil,
        "ignore means stop telling me about this app — including its staged build")
}

/// Skipping a version is the narrower form of the same "stop telling me": the
/// user saw exactly this version and declined it.
@Test func aSkippedVersionIsNotNudgedEither() {
    let remote = fixtureResult(source: "Vendor", vendorInstallerKind: .zip)

    #expect(
        UpdatePolicy.nudgeableStaged(
            remote, staged: staged("2.0"), isIgnored: false,
            isVersionSkipped: { $0 == "2.0" }) == nil,
        "the staged version is the one the user skipped")
    #expect(
        UpdatePolicy.nudgeableStaged(
            remote, staged: staged("2.0"), isIgnored: false,
            isVersionSkipped: { $0 == "1.9" }) != nil,
        "a different version was skipped — this one still nudges")
}

/// The staged-vs-latest rule still applies underneath: visibility is an extra
/// gate, not a replacement for it.
@Test func nudgeableStagedStillRequiresTheStagedBuildToBeTheLatest() {
    let remote = fixtureResult(source: "Vendor", vendorInstallerKind: .zip)
    #expect(
        UpdatePolicy.nudgeableStaged(
            remote, staged: staged("1.5"), isIgnored: false,
            isVersionSkipped: { _ in false }) == nil,
        "staged trailing the latest is not nudgeable, ignored or not")
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

/// The shipped default for self-updating apps, pinned as behaviour rather than as
/// a constant.
///
/// It is worth a test because nothing else would notice it changing: both the app
/// and the CLI resolve it from `UserDefaults` with a fallback, so a value that
/// drifted — or a fallback that drifted between the two — would just quietly route
/// installs differently, and both outcomes look individually reasonable in the UI.
@Suite struct VendorInstallPolicyDefaultTests {

    @Test func defaultOverwritesRatherThanDeferring() {
        #expect(UpdateSettings.vendorInstallPolicyDefault == .alwaysOverwrite)
    }

    /// The case the default exists for: a self-updating app that is running.
    /// Under the default it must install, not hand off.
    @Test func aRunningVendorAppInstallsUnderTheDefault() {
        #expect(!UpdatePolicy.defersToSelfUpdater(
            fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(policy: UpdateSettings.vendorInstallPolicyDefault),
            environment: environment(running: [fixturePath])),
            "the default must not hand a running self-updating app back to its own updater")
    }

    /// And the opt-out still works, so the setting remains a real choice.
    @Test func deferringIsStillAvailable() {
        #expect(UpdatePolicy.defersToSelfUpdater(
            fixtureResult(source: "Vendor", vendorInstallerKind: .zip),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath])))
    }
}

/// The muted "the vendor's latest is older than yours" note.
///
/// A source may put a human label in `shortVersion` rather than a comparable
/// number, so this note cannot be decided on that string alone. Xcode is the
/// case that broke: an up-to-date beta was announcing a downgrade to itself.
struct LaggingRemoteVersionTests {

    private func xcode(
        installedShort: String,
        installedBuild: String?,
        remoteShort: String?,
        remoteBuild: String?
    ) -> UpdateResult {
        let app = InstalledApp(
            name: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            shortVersion: installedShort,
            buildVersion: installedBuild,
            path: URL(fileURLWithPath: "/Applications/Xcode-beta.app"),
            isMASApp: false,
            sparkleFeedURL: nil)
        return UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: remoteShort,
                version: remoteBuild,
                downloadURL: nil,
                sourceName: "Xcode Releases"),
            status: .upToDate)
    }

    /// The reported bug, with the exact strings off the machine that showed it:
    /// installed Xcode-beta 27A5237l against the same build advertised as
    /// "27.0 beta 5 (27A5237l)". `27.0` genuinely sorts newer than `27.0 beta 5`
    /// (release beats prerelease), so the string comparison alone said "you're
    /// ahead" about a copy that was exactly current.
    @Test func sameBuildIsNeverADowngradeHoweverTheLabelReads() {
        #expect(VersionComparator.isNewer("27.0", than: "27.0 beta 5"),
                "precondition: this ordering is why the label cannot decide it")
        #expect(UpdatePolicy.laggingRemoteVersion(xcode(
            installedShort: "27.0",
            installedBuild: "27A5237l",
            remoteShort: "27.0 beta 5 (27A5237l)",
            remoteBuild: "27A5237l")) == nil)
    }

    /// A genuinely lagging feed still says so — the fix must not silence the note
    /// it exists for.
    @Test func anOlderRemoteBuildIsStillReported() {
        #expect(UpdatePolicy.laggingRemoteVersion(xcode(
            installedShort: "27.0",
            installedBuild: "27A5237l",
            remoteShort: "26.6",
            remoteBuild: "26F62")) == "26.6")
    }

    /// With no build on either side the note falls back to the version strings,
    /// which is how every Sparkle/GitHub app reaches it.
    @Test func withoutBuildsTheVersionStringsStillDecide() {
        #expect(UpdatePolicy.laggingRemoteVersion(xcode(
            installedShort: "2.0",
            installedBuild: nil,
            remoteShort: "1.9",
            remoteBuild: nil)) == "1.9")
        #expect(UpdatePolicy.laggingRemoteVersion(xcode(
            installedShort: "1.9",
            installedBuild: nil,
            remoteShort: "2.0",
            remoteBuild: nil)) == nil)
    }
}

// MARK: - The administrator-prompt tri-state

/// An install we cannot write to (an input method under `/Library/Input Methods`,
/// a root-owned `/Applications`) can only be replaced behind an administrator
/// prompt. The row's behaviour is deliberately three-valued, and each of the three
/// is pinned here because the wrong two-valued collapse is tempting in both
/// directions: demoting every such app up front denies a working one-click nobody
/// declined, and never remembering a refusal re-raises the password panel on every
/// release the user already said no to.
@Suite struct ElevatedInstallGateTests {

    /// An app whose location needs elevation, offered as a normal Sparkle EdDSA
    /// one-click. `elevationRequired` is what the host observed from the filesystem.
    private func elevatedResult(path: String = fixturePath) -> UpdateResult {
        fixtureResult(
            source: "Sparkle",
            edSignature: "sig",
            app: fixtureApp(sparkleEdKey: "key", path: path))
    }

    private func declinedKey(_ path: String = fixturePath) -> Set<String> {
        [InstallPreferenceKey.preferenceKey(path)]
    }

    // MARK: never asked

    @Test func neverAskedKeepsTheUpdateButton() {
        let result = elevatedResult()
        let environment = environment(elevationRequired: [fixturePath])
        #expect(UpdatePolicy.requiresElevatedInstall(result, environment: environment),
                "the host reported this path as needing elevation")
        #expect(!UpdatePolicy.elevationDeclined(result, settings: defaultSettings(), environment: environment),
                "needing a password is not the same as having refused one")
        #expect(UpdatePolicy.canAutoInstall(result, settings: defaultSettings(), environment: environment),
                "an app the user was never asked about must still offer Update")
    }

    // MARK: declined

    @Test func decliningTheAdministratorPromptRetiresTheOneClick() {
        let result = elevatedResult()
        let environment = environment(elevationRequired: [fixturePath])
        let settings = defaultSettings(declinedElevation: declinedKey())
        #expect(UpdatePolicy.elevationDeclined(result, settings: settings, environment: environment))
        #expect(!UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment),
                "a refused prompt must not be re-raised on the next release")
    }

    @Test func clearingTheDeclineRestoresTheOneClick() {
        let result = elevatedResult()
        let environment = environment(elevationRequired: [fixturePath])
        #expect(UpdatePolicy.canAutoInstall(result, settings: defaultSettings(declinedElevation: []),
                                            environment: environment),
                "there must be a way back: an emptied decline set re-offers Update")
    }

    // MARK: both halves are load-bearing

    @Test func aDeclineOnlyBitesWhereElevationIsActuallyNeeded() {
        let result = elevatedResult()
        // Same recorded decline, but the app now sits somewhere writable — e.g. it
        // moved from a root-owned location to `~/Applications`. A stale flag must
        // not keep suppressing a one-click that no longer needs a password, with
        // nothing in the UI to explain it.
        let writable = environment(elevationRequired: [])
        #expect(!UpdatePolicy.elevationDeclined(result, settings: defaultSettings(declinedElevation: declinedKey()),
                                                 environment: writable))
        #expect(UpdatePolicy.canAutoInstall(result, settings: defaultSettings(declinedElevation: declinedKey()),
                                            environment: writable))
    }

    // MARK: keyed per install path, not per bundle id

    @Test func decliningOneCopyDoesNotSilenceASiblingSharingItsBundleID() {
        // Both fixtures carry `com.example.fixture` on purpose: several installed
        // apps legitimately share a bundle id (the Toolbox-managed Android Studio
        // channels, Thunderbird stable/esr), and a bundle-id key would collapse
        // them so one refusal hid every copy.
        let sibling = "/Applications/Fixture Beta.app"
        let result = elevatedResult(path: sibling)
        let environment = environment(elevationRequired: [fixturePath, sibling])
        let settings = defaultSettings(declinedElevation: declinedKey())  // the OTHER copy
        #expect(!UpdatePolicy.elevationDeclined(result, settings: settings, environment: environment))
        #expect(UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment))
    }

    @Test func elevationIsMatchedOnThisExactInstall() {
        let result = elevatedResult()
        #expect(!UpdatePolicy.requiresElevatedInstall(
            result, environment: environment(elevationRequired: ["/Applications/Other.app"])),
                "another app's location says nothing about this one")
    }

    /// Entries written before preferences moved to per-path keys are stored under
    /// the bundle id. Honoured on read for the same reason ignore honours them —
    /// otherwise a refusal silently expires and the panel comes back.
    @Test func aLegacyBundleIDDeclineIsStillHonoured() {
        let result = elevatedResult()
        let legacy: Set<String> = [InstallPreferenceKey.preferenceKey("com.example.fixture")]
        #expect(UpdatePolicy.elevationDeclined(
            result, settings: defaultSettings(declinedElevation: legacy),
            environment: environment(elevationRequired: [fixturePath])))
    }

    // MARK: the gate only ever subtracts

    @Test func theGateNeverTurnsAnUninstallableAppIntoAnInstallableOne() {
        // Detection-only (no installer kind) and an unsigned-feed `.pkg`: both are
        // refused for reasons that have nothing to do with elevation, and must stay
        // refused whether or not a decline is recorded.
        let cases: [(name: String, result: UpdateResult)] = [
            (name: "detection-only vendor app",
             result: fixtureResult(source: "Vendor", vendorInstallerKind: nil)),
            (name: "unsigned Sparkle feed pointing at a pkg",
             result: fixtureResult(source: "Sparkle",
                                   downloadURL: URL(string: "https://example.com/fixture.pkg"))),
        ]
        for c in cases {
            for declined in [Set<String>(), declinedKey()] {
                let actual = UpdatePolicy.canAutoInstall(
                    c.result,
                    settings: defaultSettings(declinedElevation: declined),
                    environment: environment(elevationRequired: [fixturePath]))
                #expect(actual == false, "\(c.name): must stay uninstallable (declined: \(!declined.isEmpty))")
            }
        }
    }
}

// MARK: - Recognising a dismissed administrator prompt

/// `osascript … with administrator privileges` reports a dismissed password panel
/// as AppleScript error `-128`. Telling that apart from a real failure is what
/// makes the decline recordable instead of a red error the user caused on purpose.
@Suite struct AuthorizationDeclineDetectionTests {

    @Test func aDismissedPromptIsRecognisedAndAFailureIsNot() {
        let cases: [(name: String, stderr: String, expected: Bool)] = [
            (name: "the literal osascript cancellation",
             stderr: "0:0: execution error: User canceled. (-128)", expected: true),
            (name: "a localized cancellation still carries the code",
             stderr: "0:0: execution error: 使用者已取消。 (-128)", expected: true),
            (name: "an English cancellation without the code",
             stderr: "User canceled.", expected: true),
            (name: "a genuine failure must not be mistaken for a refusal",
             stderr: "mv: rename /Applications/Fixture.app: Operation not permitted", expected: false),
            (name: "empty stderr is not a refusal",
             stderr: "", expected: false),
        ]
        for c in cases {
            #expect(InPlaceSwap.isAuthorizationDeclined(c.stderr) == c.expected, "\(c.name)")
        }
    }
}

// MARK: - Input methods are never swapped in place

/// An input method is registered with the system by the vendor's installer, and
/// the app's own settings and device pairing hang off that registration. Swapping
/// the bundle does none of it. Withdrawn one-click, 2026-08-16: a user lost their
/// WeType settings and their device list showed the same Mac twice — a second
/// copy having registered itself as a new device.
///
/// The refusal is by LOCATION, not by bundle id: the next input method must not
/// need this incident repeated to be safe.
@Test func inputMethodsAreNeverOfferedAnInPlaceInstall() {
    for parent in ["/Library/Input Methods", NSHomeDirectory() + "/Library/Input Methods"] {
        let app = fixtureApp(path: parent + "/Fixture.app")
        // A Vendor result that would otherwise be a perfectly good one-click.
        let result = fixtureResult(source: "Vendor", vendorInstallerKind: .zip, app: app)
        #expect(!UpdatePolicy.canAutoInstall(
            result, settings: defaultSettings(), environment: environment()),
            "an input method in \(parent) must stay detection-only")
        #expect(UpdatePolicy.isInputMethod(app.path))
    }
}

/// The guard keys on the containing directory, so an ordinary app — including one
/// whose name merely mentions input — is untouched by it.
@Test func ordinaryAppsAreUnaffectedByTheInputMethodGuard() {
    let app = fixtureApp(path: "/Applications/Input Methods Helper.app")
    #expect(!UpdatePolicy.isInputMethod(app.path))
    #expect(UpdatePolicy.canAutoInstall(
        fixtureResult(source: "Vendor", vendorInstallerKind: .zip, app: app),
        settings: defaultSettings(), environment: environment()))
}
