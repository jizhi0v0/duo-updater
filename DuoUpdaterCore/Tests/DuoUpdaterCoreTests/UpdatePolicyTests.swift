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
    elevationRequired: Set<String> = [],
    runningIDs: Set<String> = []
) -> InstallEnvironment {
    InstallEnvironment(isHelperEnabled: helperEnabled, runningAppPaths: running,
                       stagedSelfUpdates: staged, elevationRequiredPaths: elevationRequired,
                       runningBundleIDs: runningIDs)
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
        // Electron: an electron-builder manifest, gated exactly like Vendor/GitHub
        // (see #192 — `VendorInstaller.download()` already vetted this source,
        // the policy switches just hadn't caught up).
        (
            name: "electron manifest with a resolved installer archive is auto-installable",
            result: fixtureResult(source: "Electron", vendorInstallerKind: .zip),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "electron manifest with no resolved artifact (detection-only) is not auto-installable",
            result: fixtureResult(source: "Electron", vendorInstallerKind: nil),
            settings: defaultSettings(), environment: environment(),
            expected: false
        ),
        (
            name: "electron manifest with requiresManualInstaller is not auto-installable",
            result: fixtureResult(source: "Electron", requiresManualInstaller: true, vendorInstallerKind: .zip),
            settings: defaultSettings(), environment: environment(),
            expected: false
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
            // The mas route cannot install one at all — no Mac-store entry, so
            // `mas install` errors "No apps found for ADAM ID".
            name: "iOS-on-Mac app is not auto-installable on the mas route",
            result: fixtureResult(
                source: "App Store", appStore: storeAvailability(), app: fixtureApp(isiOSAppOnMac: true)),
            settings: defaultSettings(), environment: environment(helperEnabled: true),
            expected: false
        ),
        (
            // The AX route presses the product page's own Update button, and that
            // page is the same for a wrapped iPad app as for a native Mac one
            // (probed live, macOS 26, 2026-08-29). This row is the whole point of
            // the split: without it, restoring the blanket exclusion passes.
            name: "iOS-on-Mac app IS auto-installable on the AX route",
            result: fixtureResult(
                source: "App Store", appStore: storeAvailability(), app: fixtureApp(isiOSAppOnMac: true)),
            settings: defaultSettings(strategy: .incremental), environment: environment(),
            expected: true
        ),
        (
            // …and the split must not have flipped the ordinary case with it.
            name: "native Mac App Store app is auto-installable on the AX route",
            result: fixtureResult(source: "App Store", appStore: storeAvailability()),
            settings: defaultSettings(strategy: .incremental), environment: environment(),
            expected: true
        ),
        (
            // The developer-opted-out flag guards BOTH routes, so lifting the
            // iOS-on-Mac exclusion must not let this one through.
            name: "iOS-on-Mac app Apple marks Mac-incompatible stays out on the AX route",
            result: fixtureResult(
                source: "App Store",
                appStore: storeAvailability(latestMacCompatible: false),
                app: fixtureApp(isiOSAppOnMac: true)),
            settings: defaultSettings(strategy: .incremental), environment: environment(),
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
            // electron-builder can publish a `.pkg` alongside its Squirrel `.zip` —
            // `ElectronManifestSource.kind(of:)` recognises the extension — so this
            // needs the same system-installer route as Vendor/GitHub (see #192).
            name: "electron pkg needs the system installer",
            result: fixtureResult(source: "Electron", vendorInstallerKind: .pkg),
            settings: defaultSettings(), environment: environment(),
            expected: true
        ),
        (
            name: "electron zip does not need the system installer",
            result: fixtureResult(source: "Electron", vendorInstallerKind: .zip),
            settings: defaultSettings(), environment: environment(),
            expected: false
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
        // Electron: apps built with electron-builder embed electron-updater
        // (Squirrel.Mac on macOS), so they are self-updating the same way GitHub-
        // sourced apps are treated above — see #192 for the incident that made
        // omitting a source here a user-visible bug, not a cosmetic gap.
        (
            name: "electron source defers while running — electron-updater/Squirrel.Mac self-updates too",
            result: fixtureResult(source: "Electron", vendorInstallerKind: .zip),
            settings: defaultSettings(policy: .deferWhenRunning),
            environment: environment(running: [fixturePath]),
            expected: true
        ),
        (
            name: "electron source still installs under alwaysOverwrite",
            result: fixtureResult(source: "Electron", vendorInstallerKind: .zip),
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

// MARK: - stagedBlocksInstall (Electron)

/// `stagedBlocksInstall`'s own route list lives in `StagedBlocksInstallTests.swift`
/// (out of scope for #192's lane); this pins the one row that changed there —
/// Electron moving from the unlisted default (`nil`, unprotected) to the
/// protected list alongside Vendor/GitHub/Sparkle. electron-updater/Squirrel.Mac
/// parks its own staged build exactly like Sparkle's ShipIt does, so a stale
/// staging directory here is the same collision this function exists to catch,
/// not a leftover from a mechanism we don't swap ourselves.
@Test func electronStagedBuildBlocksInstall() {
    let result = fixtureResult(source: "Electron", vendorInstallerKind: .zip)
    let blocking = UpdatePolicy.stagedBlocksInstall(
        result, staged: staged("9.9.9"))
    #expect(blocking != nil)
}

@Test func electronWithNoStagedBuildIsNotBlocked() {
    let result = fixtureResult(source: "Electron", vendorInstallerKind: .zip)
    #expect(UpdatePolicy.stagedBlocksInstall(result, staged: nil) == nil)
}

// MARK: - isRecognizedInstallSource

/// Backs `duo install`'s refusal text (#193): a source the policy has a case
/// for, versus one that always falls to `default: false` in
/// `canAutoInstall`/`requiresInstaller` and so has no install path even in
/// principle.
///
/// Derived from `SourceStack.make(githubToken:)` — the actual production
/// registry — rather than a hand-written name list, per the rule against
/// lists that drift (CLAUDE.md: "用例要从 registry 推导、覆盖全部 channel").
/// A hand-written list caught nothing when Electron itself was added to the
/// stack without a matching decision in `UpdatePolicy`, which is exactly the
/// bug #192/#193 were about; this shape makes the next one fail loudly
/// instead. Every name the stack can produce must be EITHER recognized by
/// `isRecognizedInstallSource` OR listed in `deliberatelyUnwired` with a
/// reason — no third option, no silent gap.
///
/// `Toolbox` and `TestFlight` never appear in `SourceStack`: `UpdateChecker`
/// answers them before the stack runs at all (store/Toolbox management is
/// detected up front, not through an `UpdateSource`). They're supplied here
/// by hand for exactly that reason, not discovered — and are as much a part
/// of "every source `duo install` can see a result from" as anything the
/// stack assembles.
@Test func isRecognizedInstallSourceCoversEveryProductionSourceOrExplainsWhyNot() {
    let sourcesOutsideTheStack = ["Toolbox", "TestFlight"]

    let deliberatelyUnwired: [String: String] = [
        // XcodeReleasesSource never resolves an installable artifact — Apple
        // gates every Xcode download behind an Apple ID and its own installer
        // UI, so this source is always detection-only by construction.
        "Xcode Releases": "always detection-only — no installable artifact exists to vet",
        // JetBrains Toolbox owns the install; there is no bundle of ours to swap.
        "Toolbox": "Toolbox manages the app itself",
        // Apple's TestFlight app owns the install.
        "TestFlight": "TestFlight manages the app itself",
    ]

    let stackNames = Set(SourceStack.make(githubToken: nil).map(\.name))
    let allProductionNames = stackNames.union(sourcesOutsideTheStack)
    #expect(!allProductionNames.isEmpty)  // guards against an empty stack passing vacuously

    for name in allProductionNames {
        if UpdatePolicy.isRecognizedInstallSource(name) {
            #expect(deliberatelyUnwired[name] == nil,
                "\(name) is claimed by isRecognizedInstallSource AND listed as deliberately unwired — pick one")
        } else {
            #expect(deliberatelyUnwired[name] != nil,
                "\(name) is a real production source with no UpdatePolicy decision recorded — either give it a case in canAutoInstall/requiresInstaller, or add it to deliberatelyUnwired here with a reason")
        }
    }

    // And the converse: nothing claims to be recognized that production can't
    // actually produce, and nil is never mistaken for a real source.
    #expect(!UpdatePolicy.isRecognizedInstallSource(nil))
    #expect(!UpdatePolicy.isRecognizedInstallSource("SomeFutureSource"))
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

/// The "Relaunch to apply it" nudge used to ask only `actionableStaged`, which
/// knows nothing about ignore or skip — so an ignored app went on banner-nagging
/// (then, every 5 minutes) while its row in the app showed nothing but the
/// Ignored tag. It is also what keeps such a row out of the menu-bar badge, which
/// counts the same verdict through `AppListModel.needsAction`.
@Test func anIgnoredAppIsNeverNudgedAboutItsStagedBuild() {
    let remote = fixtureResult(source: "Vendor", vendorInstallerKind: .zip)
    let never: (VersionSide) -> Bool = { _ in false }

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
            isVersionSkipped: { $0.marketing == "2.0" }) == nil,
        "the staged version is the one the user skipped")
    #expect(
        UpdatePolicy.nudgeableStaged(
            remote, staged: staged("2.0"), isIgnored: false,
            isVersionSkipped: { $0.marketing == "1.9" }) != nil,
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

/// The Amp case, observed 2026-08-28. Amp shipped ten builds all called "1.0";
/// Duo offered **Relaunch** for staged build 129 while the feed's latest was 130,
/// so the user relaunched and was still a build behind — exactly what this gate's
/// own doc comment says it exists to prevent ("relaunching to it would still
/// leave the user a download behind").
///
/// The cause was a namespace mismatch five lines wide: the installed comparison
/// above used `staged.buildVersion ?? staged.version`, and this one used
/// `staged.version` against `remote.displayVersion` — both "1.0", so `isNewer`
/// was false and the trailing build passed the gate.
@Test func actionableStagedComparesBuildsWhenTheMarketingVersionIsFrozen() {
    func ampApp(build: String) -> InstalledApp {
        InstalledApp(
            name: "Amp", bundleID: "com.ampcode.amp.macos",
            shortVersion: "1.0", buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/Amp.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: true)
    }
    func ampRemote(latestBuild: String, installedBuild: String) -> UpdateResult {
        UpdateResult(
            app: ampApp(build: installedBuild),
            remote: RemoteVersion(
                shortVersion: "1.0", version: latestBuild,
                downloadURL: URL(string: "https://example.com/amp.dmg"),
                sourceName: "Sparkle"),
            status: .updateAvailable(latest: "1.0"))
    }
    func ampStaged(_ build: String) -> StagedSelfUpdate {
        StagedSelfUpdate(version: "1.0", buildVersion: build,
                         stagedBundlePath: URL(fileURLWithPath: "/tmp/Amp.app"))
    }

    // Staged 129 while the feed offers 130: a Relaunch here lands a build that is
    // already behind, so the row must fall through to Update instead.
    #expect(UpdatePolicy.actionableStaged(
        ampRemote(latestBuild: "130", installedBuild: "128"),
        staged: ampStaged("129")) == nil,
        "staged 129 trails latest 130 — must not offer Relaunch")

    // Staged IS the latest: Relaunch is exactly right, zero extra download.
    #expect(UpdatePolicy.actionableStaged(
        ampRemote(latestBuild: "130", installedBuild: "129"),
        staged: ampStaged("130")) != nil,
        "staged 130 == latest 130 — Relaunch is correct")

    // And the downgrade guard still holds on builds alone.
    #expect(UpdatePolicy.actionableStaged(
        ampRemote(latestBuild: "130", installedBuild: "130"),
        staged: ampStaged("129")) == nil,
        "staged 129 below installed 130 would be a downgrade")

    // The moment the swap lands, installed == staged and this goes nil — the row
    // has nothing left to offer. Pinned because `AppListModel`'s banner sweep was
    // built on the opposite assumption: it withdrew "Relaunch to apply it" only for
    // ids that *left* the actionable set between two passes, and every caller
    // re-reads disk before that set is taken. So on the one pass where a relaunch
    // had just succeeded, the id was already absent from both the before and the
    // after, the difference was empty, and Amp's "downloaded 1.0 (131) on its own"
    // banner stayed in Notification Center under the "Now running 1.0."
    // confirmation. The sweep now asks who should have a banner standing, not who
    // left; if this expectation ever flips, that sweep starts withdrawing banners
    // for rows that still need them.
    #expect(UpdatePolicy.actionableStaged(
        ampRemote(latestBuild: "131", installedBuild: "131"),
        staged: ampStaged("131")) == nil,
        "the staged build is on disk — applied, so no Relaunch is outstanding")
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

/// A staged component is not always the last one. An app nested inside another
/// app's bundle — Surge ships `Surge.app/Contents/Applications/Surge Dashboard.app`
/// — reports a path whose staged component sits in the middle, and normalising
/// only the leaf left the whole string pointing at the moved-aside bundle. Nothing
/// could then tell the process belonged to Surge, so the quit-wait declared
/// success while it was still up and the swap stranded it on the old binary.
@Test func runtimeBundlePathNormalizesAStagedComponentAnywhereInThePath() {
    func path(_ raw: String) -> String { UpdatePolicy.runtimeBundlePath(URL(fileURLWithPath: raw)) }
    #expect(path("/Applications/.duoupdater-staged-Surge.app/Contents/Applications/Surge Dashboard.app")
            == "/Applications/Surge.app/Contents/Applications/Surge Dashboard.app")
    #expect(path("/Applications/Surge.app.duoupdater-old/Contents/Applications/Surge Dashboard.app")
            == "/Applications/Surge.app/Contents/Applications/Surge Dashboard.app")
    // Both ends at once, and a path with nothing to rewrite still comes back whole.
    #expect(path("/Applications/.duoupdater-staged-Surge.app/Contents/Applications/Dash.app.duoupdater-new")
            == "/Applications/Surge.app/Contents/Applications/Dash.app")
    #expect(path("/Applications/Surge.app/Contents/Applications/Surge Dashboard.app")
            == "/Applications/Surge.app/Contents/Applications/Surge Dashboard.app")
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

    /// LibreOffice: its download index lists three-segment folders while the
    /// installed bundle reports four, so padding the missing component with zero
    /// read the installed copy as ahead and the row announced a downgrade to the
    /// release it already had.
    @Test func aSourcePublishingFewerComponentsIsNotBehind() {
        #expect(VersionComparator.isNewer("26.8.0.3", than: "26.8.0"),
                "precondition: padding is why the plain comparison says 'ahead'")
        #expect(UpdatePolicy.laggingRemoteVersion(xcode(
            installedShort: "26.8.0.3",
            installedBuild: nil,
            remoteShort: "26.8.0",
            remoteBuild: nil)) == nil)
    }

    /// The prefix rule is a prefix rule, not a "fewer components" rule: a real
    /// rollback still reports, and a shorter string that is not a truncation of the
    /// installed one is not treated as the same release.
    @Test func aShorterRemoteThatIsNotATruncationStillReports() {
        #expect(UpdatePolicy.laggingRemoteVersion(xcode(
            installedShort: "4.8.8",
            installedBuild: nil,
            remoteShort: "3.7.1",
            remoteBuild: nil)) == "3.7.1")
        #expect(UpdatePolicy.laggingRemoteVersion(xcode(
            installedShort: "26.80.1",
            installedBuild: nil,
            remoteShort: "26.8",
            remoteBuild: nil)) == "26.8")
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
        let env = environment(elevationRequired: [fixturePath])
        #expect(UpdatePolicy.requiresElevatedInstall(result, environment: env),
                "the host reported this path as needing elevation")
        #expect(!UpdatePolicy.elevationDeclined(result, settings: defaultSettings(), environment: env),
                "needing a password is not the same as having refused one")
        #expect(UpdatePolicy.canAutoInstall(result, settings: defaultSettings(), environment: env),
                "an app the user was never asked about must still offer Update")
    }

    // MARK: declined

    @Test func decliningTheAdministratorPromptRetiresTheOneClick() {
        let result = elevatedResult()
        let env = environment(elevationRequired: [fixturePath])
        let settings = defaultSettings(declinedElevation: declinedKey())
        #expect(UpdatePolicy.elevationDeclined(result, settings: settings, environment: env))
        #expect(!UpdatePolicy.canAutoInstall(result, settings: settings, environment: env),
                "a refused prompt must not be re-raised on the next release")
    }

    @Test func clearingTheDeclineRestoresTheOneClick() {
        let result = elevatedResult()
        let env = environment(elevationRequired: [fixturePath])
        #expect(UpdatePolicy.canAutoInstall(result, settings: defaultSettings(declinedElevation: []),
                                            environment: env),
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
        let env = environment(elevationRequired: [fixturePath, sibling])
        let settings = defaultSettings(declinedElevation: declinedKey())  // the OTHER copy
        #expect(!UpdatePolicy.elevationDeclined(result, settings: settings, environment: env))
        #expect(UpdatePolicy.canAutoInstall(result, settings: settings, environment: env))
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
            // Real osascript output is LF-terminated — measured, 45 bytes for the
            // English line. The fixture is a *localized* cancel on purpose: with an
            // English one, deleting the trim still passes, because the old English
            // substring clause rescued it. This case is what makes the trim
            // load-bearing in the table as well as in production.
            (name: "osascript ends the line with a newline, which must not defeat the anchor",
             stderr: "0:17: execution error: Von Benutzer:in abgebrochen. (-128)\n", expected: true),
            // The English text is not a signal. It is absent on en-GB ("User
            // cancelled."), and present in failures that are nobody's decision —
            // see the `User Canceled.app` case below.
            (name: "an English cancellation without the code is not one",
             stderr: "User canceled.", expected: false),
            (name: "a genuine failure must not be mistaken for a refusal",
             stderr: "mv: rename /Applications/Fixture.app: Operation not permitted", expected: false),
            (name: "empty stderr is not a refusal",
             stderr: "", expected: false),
            // The code is the *trailing* parenthesised token and nothing else. Every
            // other place `-128` can appear is a different fact: part of a longer
            // code, part of a path or file name the failing command echoed, or —
            // per TN2065 — the shell's own stderr, which osascript adopts as the
            // message while the exit status becomes the number.
            (name: "-128 inside a path in a real error (the issue's own counter-example)",
             stderr: "6:43: execution error: /Applications/Foo-128.app not found (-10006)", expected: false),
            (name: "-128 as the prefix of a longer code",
             stderr: "osascript: error -12805 while staging", expected: false),
            (name: "a bare longer code",
             stderr: "-1280", expected: false),
            (name: "a version-like file name",
             stderr: "App-128.dmg", expected: false),
            (name: "a real failure under a path that names the English phrase",
             stderr: "0:42: execution error: mv: rename /Users/x/User Canceled.app: Operation not permitted (1)",
             expected: false),
            (name: "a shell failure whose stderr names a -128 path; the status is the code",
             stderr: "0:42: execution error: mv: rename /Applications/Foo-128.app: Operation not permitted (1)", expected: false),
            (name: "a shell that printed (-128) itself still failed with its own status",
             stderr: "0:42: execution error: rsync: (-128) (3)", expected: false),
        ]
        for c in cases {
            #expect(InPlaceSwap.isAuthorizationDeclined(c.stderr) == c.expected, "\(c.name)")
        }
    }
}

// MARK: - Which installs need an administrator

/// `needsElevatedReplace` decides whether a swap goes through the password panel
/// or through `replaceItemAt`. Getting it wrong in the permissive direction is not
/// a prompt the user is spared: the unprivileged path then fails with
/// `NSFileWriteNoPermissionError`, which `isAppManagementDenial` reads as a TCC
/// denial — so the user is sent to grant App Management for an obstacle that is
/// POSIX ownership and that App Management cannot lift.
///
/// Both fixtures are built with real permission bits rather than mocked, because
/// the predicate's whole job is to report what the filesystem will allow.
@Suite struct ElevatedReplaceDetectionTests {

    /// A `.app` in `parent`, with `mode` applied to the bundle directory itself.
    private func fixture(in parent: URL, mode: Int, named name: String) throws -> URL {
        let app = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: app.path)
        return app
    }

    @Test func aBundleWeCannotWriteNeedsAdminEvenInAWritableParent() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoElevationTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        // 0o555 must be lifted before the tree can be removed, exactly the property
        // under test — so the cleanup restores it first.
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: parent.appendingPathComponent("Locked.app").path)
            try? FileManager.default.removeItem(at: parent)
        }

        // The App Store layout: `root:wheel` 755 bundle inside a `root:admin` 775
        // `/Applications`. The user can rename the bundle but cannot empty it, and
        // the swap ends by deleting the bundle it replaced.
        let locked = try fixture(in: parent, mode: 0o555, named: "Locked.app")
        #expect(InPlaceSwap.needsElevatedReplace(target: locked),
                "a bundle we cannot write into must go through the administrator prompt")
        #expect(InPlaceSwap.elevationRequiredPaths(for: [locked]).contains(locked.path),
                "and the UI must be told the same thing the swap will do")

        // An ordinary user-writable app in the same writable parent still takes the
        // unprivileged path: this must not have become "always ask".
        let ours = try fixture(in: parent, mode: 0o755, named: "Ours.app")
        #expect(!InPlaceSwap.needsElevatedReplace(target: ours))
        #expect(InPlaceSwap.elevationRequiredPaths(for: [ours]).isEmpty)
    }
}

// MARK: - Input methods are updated by rotating Contents, or not at all

/// An input method is registered with the system by PATH — the outer `.app`
/// directory is the identity, which is why both vendors' own updaters keep it and
/// rotate `Contents` inside it. So the one-click is allowed exactly on the routes
/// that can be applied that way: an app-bundle archive, reaching
/// `InPlaceSwap.rotateContents`.
///
/// Restored 2026-08-28 after the 0.3.25 withdrawal; the gate is now shaped by what
/// the install DOES rather than by where the app lives.
@Test func inputMethodsMayBeOneClickedWhenTheDownloadIsAnAppBundle() {
    for parent in ["/Library/Input Methods", NSHomeDirectory() + "/Library/Input Methods"] {
        let app = fixtureApp(path: parent + "/Fixture.app")
        #expect(UpdatePolicy.isInputMethod(app.path))
        #expect(UpdatePolicy.canAutoInstall(
            fixtureResult(source: "Vendor", vendorInstallerKind: .zip, app: app),
            settings: defaultSettings(), environment: environment()),
            "an archive install in \(parent) is a Contents rotation, which is allowed")
    }
}

/// The other half, and the half that keeps the rule honest: every route that
/// would replace the OUTER bundle instead of rotating what is inside it stays
/// refused for an input method, no matter how well-formed it otherwise is.
///
/// A `.pkg` is the one to watch — `canAutoInstall`'s Vendor branch accepts any
/// non-nil installer kind, so without the rotation gate a vendor pkg would have
/// been offered as a one-click swap of a registered input source.
@Test func inputMethodsRefuseEveryRouteThatReplacesTheWholeBundle() {
    let app = fixtureApp(path: "/Library/Input Methods/Fixture.app")
    let refused: [(String, UpdateResult)] = [
        ("a vendor pkg", fixtureResult(source: "Vendor", vendorInstallerKind: .pkg, app: app)),
        // Given the cask token it would otherwise need, so the refusal below is
        // the input-method rule and not a missing field.
        ("a Homebrew cask", fixtureResult(source: "Homebrew", sourceIdentifier: "fixture", app: app)),
        ("a detection-only vendor recipe", fixtureResult(source: "Vendor", app: app)),
        // Electron is deliberately NOT in `isContentsRotatable`'s switch (#192):
        // unlike Vendor, we have no vetted registry over what an arbitrary
        // electron-builder manifest ships, so an Electron-packaged input method
        // stays closed even with a well-formed zip archive — the safe default,
        // not an oversight.
        ("an electron zip", fixtureResult(source: "Electron", vendorInstallerKind: .zip, app: app)),
    ]
    for (what, result) in refused {
        #expect(!UpdatePolicy.canAutoInstall(
            result, settings: defaultSettings(), environment: environment()),
            "\(what) replaces the registered bundle, so it must not be offered")
    }
}

/// The gate has to hold in `requiresInstaller` too, and not because that is a
/// second opinion on the same question — because it is the way AROUND it. Every
/// caller offers a row on `canAutoInstall || requiresInstaller`, so a rule that
/// lives only in the first is satisfied by the second returning true.
///
/// Nothing in today's registry reaches it: both input-method recipes are `.zip`.
/// A vendor switching artifact, or a one-word `kind:` edit, is all it would take
/// to turn a Contents rotation into a root-run vendor package over a registered
/// input source — with no code change, and no gate firing.
@Test func anInputMethodIsNeverHandedToTheSystemInstaller() {
    let app = fixtureApp(path: "/Library/Input Methods/Fixture.app")
    let pkg = fixtureResult(source: "Vendor", vendorInstallerKind: .pkg, app: app)
    #expect(!UpdatePolicy.requiresInstaller(pkg, environment: environment()))
    // The same result anywhere else is still a normal package install, so the
    // refusal is the input-method rule rather than something about `.pkg`.
    #expect(UpdatePolicy.requiresInstaller(
        fixtureResult(source: "Vendor", vendorInstallerKind: .pkg,
                      app: fixtureApp(path: "/Applications/Fixture.app")),
        environment: environment()))
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


// MARK: - Running detection

/// A wrapped iPhone/iPad app runs out of a per-launch shadow container, so its
/// process reports a `bundleURL` that can never equal the installed bundle —
/// measured on macOS 26 (2026-08-29): Aqara Home reported
/// `/private/var/folders/…/X/<uuid>/d/Wrapper/AqaraHome.app` while installed at
/// `/Applications/Aqara Home.app`. Path matching therefore answers "not running"
/// for a live wrapped app, which silently disarms the reopen after the store
/// quits it (`AppStoreQuitPolicy.armsReopen` keys on exactly this) and hides the
/// "App Store can't replace it while it's open" note.
@Test func aWrappedAppIsRecognisedAsRunningByIdentifier() {
    let app = fixtureApp(isiOSAppOnMac: true)
    let result = UpdateResult(app: app, remote: nil, status: .unknown)

    // What the host can actually observe for a running wrapped app: the shadow
    // path (which matches nothing) plus the identifier (which does).
    let shadow: Set<String> = ["/private/var/folders/x/y/d/Wrapper/Inner.app"]
    #expect(UpdatePolicy.isRunning(
        result, environment: environment(running: shadow, runningIDs: ["com.example.fixture"])))

    // Same observation without the identifier set is the pre-fix behaviour, and
    // it is wrong — kept as a row so the fix cannot be quietly reverted.
    #expect(!UpdatePolicy.isRunning(result, environment: environment(running: shadow)))
}

/// Path stays the discriminator for every other app: two copies in different
/// places are different installs, and only the one being replaced reads as
/// running. Sharing an identifier must not make the other copy count.
@Test func aNormalAppIsStillMatchedByPathNotIdentifier() {
    let result = UpdateResult(app: fixtureApp(), remote: nil, status: .unknown)

    #expect(UpdatePolicy.isRunning(result, environment: environment(running: [fixturePath])))
    #expect(!UpdatePolicy.isRunning(
        result,
        environment: environment(
            running: ["/Users/someone/Applications/Fixture.app"],
            runningIDs: ["com.example.fixture"])))
}
