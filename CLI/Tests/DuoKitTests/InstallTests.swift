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

    /// #192: `VendorInstaller.download()` already vetted "Electron" (electron-
    /// builder manifests) — the policy switches and `route(for:)` just hadn't
    /// caught up, so this one-clicked to nothing. Same shape as
    /// `aVendorArchiveInstalls`, proving the wiring now agrees end to end.
    @Test func anElectronArchiveInstalls() {
        let decision = Install.classify(
            result(source: "Electron"), settings: settings(), environment: environment())
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

    /// Same as `detectionOnlyIsRefused`, for Electron: recognized source
    /// (has its own case in `canAutoInstall`/`requiresInstaller`), just no
    /// artifact resolved this time.
    @Test func electronDetectionOnlyIsRefusedWithTheArtefactWording() {
        let decision = Install.classify(
            result(source: "Electron", vendorKind: nil),
            settings: settings(), environment: environment())
        guard case .refuse(let why) = decision else {
            Issue.record("expected a refusal, got \(decision)")
            return
        }
        #expect(why.contains("no installable artefact"))
    }

    /// #193 (follow-up): a source `UpdatePolicy` has no case for at all — Xcode
    /// Releases never resolves an artifact, by design (`downloadURL: nil`, its
    /// download 302s to an Apple-ID login page) — must get the SAME wording as
    /// Electron above, not a distinct "no install route wired up yet" message.
    ///
    /// #193 originally introduced exactly that distinct message, reasoning it
    /// should read differently from "no artifact this time". It was reverted
    /// (see `Install.swift`'s comment) once measured against production: every
    /// source that reaches this branch — Xcode Releases, Toolbox, TestFlight —
    /// is permanently artefact-less by design, so "not wired up yet" was false
    /// for all of them; it just relocated #193's original complaint (a message
    /// asserting something untrue) to the other bucket. This test pins the
    /// collapse so the split doesn't quietly come back.
    @Test func aSourceThePolicyHasNoCaseForGetsTheSameGenericWording() {
        let decision = Install.classify(
            result(source: "Xcode Releases", vendorKind: nil),
            settings: settings(), environment: environment())
        guard case .refuse(let why) = decision else {
            Issue.record("expected a refusal, got \(decision)")
            return
        }
        #expect(why.contains("no installable artefact"))
        #expect(!why.contains("wired up"))
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

    /// Same rule for Electron (#192): electron-builder apps embed their own
    /// updater (electron-updater / Squirrel.Mac), so a running one must defer
    /// exactly like a running Vendor app does above.
    @Test func aRunningElectronSelfUpdaterIsDeferredUnlessOverridden() {
        let running = environment(running: true)
        guard case .refuse = Install.classify(
            result(source: "Electron"), settings: settings(), environment: running)
        else {
            Issue.record("a running electron app should defer under deferWhenRunning")
            return
        }
        guard case .install = Install.classify(
            result(source: "Electron"),
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

    /// #192: Electron is no longer an unknown source — `route(for:)` must send
    /// it to `.vendor`, same as Vendor/GitHub, not fall through to `.sparkle`
    /// (which would hand an electron-builder zip to `SparkleInstaller`, which
    /// throws `.notSparkleUpdate` for any non-Sparkle source).
    @Test func anElectronSourceRoutesToVendor() {
        let electron = UpdateResult(
            app: InstalledApp(
                name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1.0",
                buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Fixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: "2.0", version: nil,
                downloadURL: URL(string: "https://example.com/fixture.zip"),
                sourceName: "Electron", requiresManualInstaller: false,
                vendorInstallerKind: .zip),
            status: .updateAvailable(latest: "2.0"))
        #expect(InstallCoordinator.route(for: electron, requiresInstaller: false) == .vendor)
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

@Suite(.serialized) struct VisibilityWriteTests {

    /// A scratch domain so these never touch the real preferences.
    private func scratchDefaults() -> UserDefaults {
        let suite = "com.duoupdater.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func app(_ path: String = "/Applications/Fixture.app") -> InstalledApp {
        InstalledApp(
            name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1.0",
            buildVersion: "1", path: URL(fileURLWithPath: path), isMASApp: false,
            sparkleFeedURL: nil)
    }

    private func result(hasUpdate: Bool) -> UpdateResult {
        UpdateResult(
            app: app(),
            remote: RemoteVersion(
                shortVersion: "2.0", version: nil, downloadURL: nil,
                sourceName: "Vendor", requiresManualInstaller: false),
            status: hasUpdate ? .updateAvailable(latest: "2.0") : .upToDate)
    }

    @Test func ignoringWritesTheSharedKeyAndIsIdempotent() {
        let defaults = scratchDefaults()
        guard case .success = Visibility.apply(.ignore, to: result(hasUpdate: true), in: defaults) else {
            Issue.record("first ignore should succeed"); return
        }
        #expect(defaults.stringArray(forKey: UpdateSettings.ignoredKeysKey)
            == [InstallPreferenceKey.key(for: app())])
        guard case .failure = Visibility.apply(.ignore, to: result(hasUpdate: true), in: defaults) else {
            Issue.record("ignoring twice should report it was already ignored"); return
        }
    }

    /// An app that is already current still reports a remote version. Keying the
    /// skip on that recorded a skip for the version the user is happily running,
    /// which would then hide the next real update's row.
    @Test func skippingNeedsAnActualUpdate() {
        let defaults = scratchDefaults()
        guard case .failure(let why) = Visibility.apply(
            .skip, to: result(hasUpdate: false), in: defaults) else {
            Issue.record("skipping an up-to-date app should be refused"); return
        }
        #expect(why.contains("no update offered"))
        #expect(defaults.dictionary(forKey: UpdateSettings.skippedVersionsKey) == nil)
    }

    @Test func skippingRecordsTheOfferedVersion() {
        let defaults = scratchDefaults()
        guard case .success = Visibility.apply(.skip, to: result(hasUpdate: true), in: defaults) else {
            Issue.record("skip should succeed when an update is offered"); return
        }
        let stored = defaults.dictionary(forKey: UpdateSettings.skippedVersionsKey) as? [String: String]
        #expect(stored?[InstallPreferenceKey.key(for: app())] == "2.0")
    }

    /// Migration can leave both the current path key and the legacy bundle-id key.
    /// Un-ignoring must clear both, or the app still matches the one left behind.
    @Test func unignoringClearsCurrentAndLegacyKeysTogether() {
        let defaults = scratchDefaults()
        let current = InstallPreferenceKey.key(for: app())
        let legacy = InstallPreferenceKey.legacyKey(for: app())
        defaults.set([current, legacy], forKey: UpdateSettings.ignoredKeysKey)
        guard case .success = Visibility.apply(.unignore, to: result(hasUpdate: true), in: defaults) else {
            Issue.record("unignore should clear both entry forms"); return
        }
        #expect(defaults.stringArray(forKey: UpdateSettings.ignoredKeysKey)?.isEmpty == true)
    }

    /// The state the legacy handling exists for: an app ignored before the move to
    /// path keys has only the bundle-id entry on disk. Kept alongside the both-keys
    /// test above, which cannot fail for this case — there the current key always
    /// supplies the removal, so it would still pass if the legacy branch were lost.
    @Test func unignoringClearsALegacyOnlyEntry() {
        let defaults = scratchDefaults()
        let legacy = InstallPreferenceKey.legacyKey(for: app())
        defaults.set([legacy], forKey: UpdateSettings.ignoredKeysKey)
        guard case .success = Visibility.apply(.unignore, to: result(hasUpdate: true), in: defaults) else {
            Issue.record("unignore should clear a legacy-only entry"); return
        }
        #expect(defaults.stringArray(forKey: UpdateSettings.ignoredKeysKey)?.isEmpty == true)
    }

    /// Same migration state for a skipped version: only the legacy key is present.
    @Test func unskippingClearsALegacyOnlyEntry() {
        let defaults = scratchDefaults()
        let legacy = InstallPreferenceKey.legacyKey(for: app())
        defaults.set([legacy: "2.0"], forKey: UpdateSettings.skippedVersionsKey)
        guard case .success = Visibility.apply(.unskip, to: result(hasUpdate: true), in: defaults) else {
            Issue.record("unskip should clear a legacy-only entry"); return
        }
        let stored = defaults.dictionary(forKey: UpdateSettings.skippedVersionsKey)
            as? [String: String]
        #expect(stored?.isEmpty == true)
    }

    @Test func unskippingClearsCurrentAndLegacyKeysTogether() {
        let defaults = scratchDefaults()
        let current = InstallPreferenceKey.key(for: app())
        let legacy = InstallPreferenceKey.legacyKey(for: app())
        defaults.set(
            [current: "2.0", legacy: "2.0"],
            forKey: UpdateSettings.skippedVersionsKey)
        guard case .success = Visibility.apply(.unskip, to: result(hasUpdate: true), in: defaults) else {
            Issue.record("unskip should clear both entry forms"); return
        }
        let stored = defaults.dictionary(forKey: UpdateSettings.skippedVersionsKey)
            as? [String: String]
        #expect(stored?.isEmpty == true)
    }
}
