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
        vendorPolicy: VendorInstallPolicy = .deferWhenRunning,
        appStoreStrategy: AppStoreUpdateStrategy = .full
    ) -> Settings {
        Settings(
            updateSettings: UpdateSettings(
                appStoreUpdateStrategy: appStoreStrategy, vendorInstallPolicy: vendorPolicy),
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
    /// standalone binary has neither. Under `.full` (this test's default
    /// settings), `canAutoInstall`'s App Store case requires
    /// `environment.isHelperEnabled` — which the CLI never sets — so this
    /// refusal comes from the EARLIER guard in `classify`, before a route is
    /// ever computed. `route` is therefore `nil`, not `.appStore`: see
    /// `theAppStoreRefusalCarriesTheRouteWhenClassifyComputedOne` below for the
    /// other refusal branch, which does have one to give.
    @Test func theAppStoreIsRefusedWithAReason() {
        let decision = Install.classify(
            result(source: "App Store",
                   appStore: AppStoreAvailability(
                    trackID: 1, availableRegion: "us", homeRegion: "us", storeName: nil)),
            settings: settings(), environment: environment())
        guard case .refuse(let why, let route) = decision else {
            Issue.record("expected a refusal, got \(decision)")
            return
        }
        #expect(why.contains("App Store"))
        #expect(route == nil)
    }

    /// #404 review #5: `Decision.refuse`'s second value is the route
    /// `classify` had already computed before deciding to refuse — used so
    /// `reconsider`/`emitSkipped` never fall back to a stale plan route that
    /// could contradict the refusal message. Under `.incremental`,
    /// `canAutoInstall`'s App Store case returns `true` unconditionally (the
    /// AX route needs no helper), so this reaches the LATER refusal — the one
    /// after `InstallCoordinator.route(for:)` has already resolved `.appStore`
    /// — and that route must come along. Mutation (reverted after running):
    /// changed `return .refuse("App Store updates need the menu-bar app",
    /// route)` to `return .refuse("App Store updates need the menu-bar app",
    /// nil)` in `Install.classify` — this test went red (expected
    /// `.appStore`, got `nil`).
    @Test func theAppStoreRefusalCarriesTheRouteWhenClassifyComputedOne() {
        let decision = Install.classify(
            result(source: "App Store",
                   appStore: AppStoreAvailability(
                    trackID: 1, availableRegion: "us", homeRegion: "us", storeName: nil)),
            settings: settings(appStoreStrategy: .incremental), environment: environment())
        guard case .refuse(let why, let route) = decision else {
            Issue.record("expected a refusal, got \(decision)")
            return
        }
        #expect(why.contains("App Store"))
        #expect(route == .appStore)
    }

    /// Detection-only apps have no artefact we vet, so there is nothing to
    /// install even though the row shows a newer version.
    @Test func detectionOnlyIsRefused() {
        let decision = Install.classify(
            result(source: "Vendor", vendorKind: nil),
            settings: settings(), environment: environment())
        guard case .refuse(let why, _) = decision else {
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
        guard case .refuse(let why, _) = decision else {
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
        guard case .refuse(let why, _) = decision else {
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

/// #404: the CLI used to hand the PLAN's stale `UpdateResult` straight to
/// `InstallCoordinator`, with no re-check between "the user approved this" and
/// "this is now being installed" — a window a confirmation prompt or an earlier
/// item's download can hold open for a long time. `Install.reconsider` is the
/// pure classification the fix hangs on; `Install.apply` (mostly untested here —
/// it's I/O around a concrete, unmockable `InstallCoordinator`) does the
/// re-scan/re-check and calls this right before backup. The `attempted`/
/// `declinedCount` bookkeeping `apply` does around `coordinator.perform` (#404
/// review #2, #3) is therefore verified by code reading, not a mutation-tested
/// unit test here — see the PR description for what was checked by hand.
///
/// Each fixture below builds an `offered` (what the plan showed) and a
/// `confirmed` (what a fresh disk read + source query answers right before
/// install) independently, the same way `apply` will hold two independently-aged
/// `UpdateResult`s for the same app.
@Suite struct InstallReconsiderTests {

    private let fixturePath = "/Applications/Fixture.app"

    private func app(shortVersion: String = "1.0") -> InstalledApp {
        InstalledApp(
            name: "Fixture", bundleID: "com.example.fixture",
            shortVersion: shortVersion, buildVersion: "1",
            path: URL(fileURLWithPath: fixturePath), isMASApp: false,
            sparkleFeedURL: nil)
    }

    private func vendorOffer(latest: String = "1.1") -> UpdateResult {
        UpdateResult(
            app: app(),
            remote: RemoteVersion(
                shortVersion: latest, version: nil,
                downloadURL: URL(string: "https://example.com/fixture.dmg"),
                sourceName: "Vendor", requiresManualInstaller: false,
                vendorInstallerKind: .dmg),
            status: .updateAvailable(latest: latest))
    }

    private func settings() -> Settings {
        Settings(
            updateSettings: UpdateSettings(
                appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning),
            ignoredKeys: [], skippedVersions: [:], customScanPaths: [],
            maxConcurrency: 12, keepBackups: true, githubToken: nil, alcove: nil)
    }

    private func environment() -> InstallEnvironment {
        InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
    }

    /// Pins `PreInstallDecision.alreadyCurrent` → `ReconsiderOutcome.skip`, not a
    /// failure. Mutation (reverted after running): changed
    /// `case .alreadyCurrent: return .skip(...)` to
    /// `return .proceed(confirmed, .vendor)` in `Install.reconsider` — this test
    /// went red (expected `.skip`, got `.proceed`), confirming it actually
    /// exercises that arm rather than passing by construction.
    @Test func diskAlreadyUpdatedIsSkippedNotInstalled() {
        let offered = vendorOffer()
        // Re-scan finds the disk already at 1.1 and the source agrees there is
        // nothing newer: `remote: nil` is an empty `VersionSide`, which
        // `PreInstallGate` treats as "never regressed" (fails closed) — so this
        // lands on `.alreadyCurrent`, not `.answerRegressed`.
        let confirmed = UpdateResult(app: app(shortVersion: "1.1"), remote: nil, status: .upToDate)
        let outcome = Install.reconsider(
            offered: offered, confirmed: confirmed, settings: settings(),
            environment: environment(), routes: [])
        guard case .skip = outcome else {
            Issue.record("expected a skip, got \(outcome)")
            return
        }
    }

    /// #404 review #1: the message states only what was observed (the disk is
    /// at some version, nothing newer to install) and never asserts WHY — the
    /// old wording ("updated to X while waiting for confirmation") named one
    /// specific cause unconditionally, which is flatly false under `--yes`
    /// (there is no confirmation prompt to wait behind at all). Mutation
    /// (reverted after running): put the old wording back — this test went
    /// red (the message claimed to have "waited for confirmation").
    @Test func alreadyCurrentWordingStatesOnlyWhatWasObserved() {
        let offered = vendorOffer()
        let confirmed = UpdateResult(app: app(shortVersion: "1.1"), remote: nil, status: .upToDate)
        let outcome = Install.reconsider(
            offered: offered, confirmed: confirmed, settings: settings(),
            environment: environment(), routes: [])
        guard case .skip(let why, _) = outcome else {
            Issue.record("expected a skip, got \(outcome)")
            return
        }
        #expect(!why.contains("waiting for confirmation"))
        #expect(why.contains("1.1"))
    }

    /// Pins `PreInstallDecision.cannotConfirm` → `ReconsiderOutcome.cannotConfirm`,
    /// counted as a failure by `apply` (retryable — the source, not the app, is
    /// what's in doubt). Mutation: changed
    /// `case .cannotConfirm(let message): return .cannotConfirm(message)` to
    /// `return .skip(message ?? "?")` — went red (expected `.cannotConfirm`, got
    /// `.skip`).
    @Test func sourceQueryFailureCannotConfirm() {
        let offered = vendorOffer()
        let confirmed = UpdateResult(app: app(), remote: nil, status: .error("connection timed out"))
        let outcome = Install.reconsider(
            offered: offered, confirmed: confirmed, settings: settings(),
            environment: environment(), routes: [])
        guard case .cannotConfirm(let message) = outcome else {
            Issue.record("expected cannotConfirm, got \(outcome)")
            return
        }
        #expect(message == "connection timed out")
    }

    /// Pins `PreInstallDecision.answerRegressed` → `ReconsiderOutcome.answerRegressed`
    /// (counted as a failure, both versions preserved for the caller to print).
    /// Mutation: changed `case .answerRegressed: return .answerRegressed` to
    /// `return .skip("regressed")` — went red (expected `.answerRegressed`, got
    /// `.skip`).
    @Test func answerWalkingBackwardsIsAFailureNotASkip() {
        let offered = vendorOffer(latest: "1.1")
        // The re-check's OWN answer is older than what it just offered, and
        // calls the app current on the strength of it — the Nowdex shape
        // `PreInstallDecision.answerRegressed`'s doc comment describes.
        let confirmed = UpdateResult(
            app: app(),
            remote: RemoteVersion(
                shortVersion: "1.0", version: nil, downloadURL: nil,
                sourceName: "Vendor", requiresManualInstaller: false),
            status: .upToDate)
        let outcome = Install.reconsider(
            offered: offered, confirmed: confirmed, settings: settings(),
            environment: environment(), routes: [])
        #expect(outcome == .answerRegressed)
    }

    /// The case #404 itself is about: while the user held the confirmation
    /// prompt (or an earlier item in the batch installed), the vendor shipped
    /// AGAIN — the re-check confirms 1.2, newer than the 1.1 that was offered.
    /// `reconsider` must install `confirmed` (1.2), never `offered` (1.1) — the
    /// whole point of re-checking is that the stale plan is not what gets
    /// installed. Mutation: changed `return .proceed(confirmed, route)` to
    /// `return .proceed(offered, route)` in the `.install` arm — went red
    /// (`result.remote?.displayVersion` was "1.1", not the expected "1.2").
    @Test func updateAppearingDuringTheWaitInstallsTheNewerConfirmedVersion() {
        let offered = vendorOffer(latest: "1.1")
        let confirmed = vendorOffer(latest: "1.2")
        let outcome = Install.reconsider(
            offered: offered, confirmed: confirmed, settings: settings(),
            environment: environment(), routes: [])
        guard case .proceed(let result, let route) = outcome else {
            Issue.record("expected a proceed, got \(outcome)")
            return
        }
        #expect(result.remote?.displayVersion == "1.2")
        #expect(route == .vendor)
    }

    /// `reconsider` must classify off `confirmed`, not `offered`: the source can
    /// have moved to a completely different distribution channel while the plan
    /// sat waiting for confirmation, and the freshly-derived route is the one
    /// that governs whether this can be installed at all. Mutation: changed
    /// `classify(confirmed, ...)` to `classify(offered, ...)` in the `.proceed`
    /// arm — went red (the Vendor `offered` classifies as installable, so the
    /// outcome became `.proceed` instead of the expected `.skip`).
    ///
    /// Also pins #404 review #5: the `route` carried by `.skip` here is `nil`
    /// (this App Store item hits the SAME early refusal as
    /// `theAppStoreIsRefusedWithAReason` above, under this suite's `.full`
    /// settings), never the plan's stale `.vendor` — the bug this review found:
    /// the `--json` line used to say `"route": "vendor"` right next to a
    /// `reason` about the App Store. Mutation (reverted after running):
    /// changed `case .refuse(let why, let route): return .skip(why, route)` to
    /// `return .skip(why, .vendor)` — this test went red (expected `nil`, got
    /// `.vendor`).
    @Test func routeMovingToAppStoreIsSkippedNotInstalled() {
        let offered = vendorOffer()
        let confirmed = UpdateResult(
            app: app(),
            remote: RemoteVersion(
                shortVersion: "1.1", version: nil, downloadURL: nil,
                sourceName: "App Store",
                appStore: AppStoreAvailability(
                    trackID: 1, availableRegion: "us", homeRegion: "us", storeName: nil),
                requiresManualInstaller: false),
            status: .updateAvailable(latest: "1.1"))
        let outcome = Install.reconsider(
            offered: offered, confirmed: confirmed, settings: settings(),
            environment: environment(), routes: [])
        guard case .skip(let why, let route) = outcome else {
            Issue.record("expected a skip, got \(outcome)")
            return
        }
        #expect(why.contains("App Store"))
        #expect(route == nil)
    }

    /// `--route` narrows on the RE-DERIVED route, not the plan's original one —
    /// the plan's `Vendor` source is still what `confirmed` reports here, so this
    /// is really pinning that the filter is applied a second time after
    /// `reconsider` classifies, not that classification moved. Mutation: removed
    /// the `guard routes.isEmpty || routes.contains(route) else { … }` in the
    /// `.install` arm (unconditional `.proceed`) — went red (expected
    /// `.notRequested`, got `.proceed`).
    @Test func routeFilterAppliesAgainAfterReconsidering() {
        let offered = vendorOffer()
        let confirmed = vendorOffer()
        let outcome = Install.reconsider(
            offered: offered, confirmed: confirmed, settings: settings(),
            environment: environment(), routes: [.homebrew])
        guard case .notRequested(let route) = outcome else {
            Issue.record("expected notRequested, got \(outcome)")
            return
        }
        #expect(route == .vendor)
    }

    /// #404 review #6: a re-scan that found no readable bundle (`recheckOne`
    /// returning `nil`, whether the app was uninstalled or its Info.plist
    /// failed to parse — `AppScanner.readApp` returns nil for both, and this
    /// cannot assert which) must NOT become `.cannotConfirm` — that reads as
    /// retryable, and re-running `duo install` cannot change whether a bundle
    /// exists right now. Mutation (reverted after running): changed
    /// `guard let confirmed else { return .unreadable(...) }` to
    /// `return .cannotConfirm(nil)` in `Install.reconsider` — this test went
    /// red (expected `.unreadable`, got `.cannotConfirm`).
    @Test func noReadableBundleIsUnreadableNotCannotConfirm() {
        let offered = vendorOffer()
        let outcome = Install.reconsider(
            offered: offered, confirmed: nil, settings: settings(),
            environment: environment(), routes: [])
        guard case .unreadable(let why) = outcome else {
            Issue.record("expected unreadable, got \(outcome)")
            return
        }
        // States only what was observed, hedged rather than asserted — not
        // which of "uninstalled" or "Info.plist failed to parse" it was.
        #expect(why.contains("may have"))
        #expect(why.contains(fixturePath))
    }

    /// #404 review #7: `recheckOne` refuses to treat a bundle that now resolves
    /// to a DIFFERENT app as a re-confirmation of the plan's app — mirroring
    /// `AppListModel.recheckMany`'s own guard ("a bundle that now resolves
    /// elsewhere reads as gone, not as a row under another id"). Built with a
    /// real symlink rather than asserted in the abstract: `AppScanner.admit`
    /// resolves symlinks before building `InstalledApp.path` (which is also
    /// `InstalledApp.id`), so a plan's path that is now a symlink pointing at a
    /// completely different bundle is exactly the shape that guard exists for.
    /// Mutation (reverted after running): removed the `app.id == result.app.id`
    /// half of the guard in `Install.recheckOne` (kept only `apps.first`) —
    /// this test went red (expected `nil`, got the OTHER app's `UpdateResult`).
    @Test func aBundleThatNowResolvesElsewhereReadsAsGoneNotAsAnotherApp() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("recheck-identity-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let otherApp = root.appendingPathComponent("SomeOtherApp.app")
        let info = otherApp.appendingPathComponent("Contents/Info.plist")
        try fm.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleDisplayName": "Some Other App",
            "CFBundleIdentifier": "com.example.other",
            "CFBundleShortVersionString": "9.9",
            "CFBundleVersion": "9",
            "CFBundleExecutable": "SomeOtherApp",
        ]
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: info)

        // The plan's path is a symlink — at plan time it may well have
        // resolved to THIS app, but by the time `recheckOne` runs it points
        // somewhere else entirely (the scenario the identity guard exists for).
        let alias = root.appendingPathComponent("Fixture.app")
        try fm.createSymbolicLink(at: alias, withDestinationURL: otherApp)

        let offered = UpdateResult(
            app: InstalledApp(
                name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1.0",
                buildVersion: "1", path: alias, isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: "1.1", version: nil,
                downloadURL: URL(string: "https://example.com/fixture.dmg"),
                sourceName: "Vendor", requiresManualInstaller: false, vendorInstallerKind: .dmg),
            status: .updateAvailable(latest: "1.1"))

        let testflight = TestFlightInventory(macRows: [], accessible: false)
        let toolbox = ToolboxInventory()
        let checker = Inventory.checker(settings(), testflight: testflight, toolbox: toolbox)
        let confirmed = await Install.recheckOne(
            offered, testflight: testflight, toolbox: toolbox, checker: checker)
        #expect(confirmed == nil,
            "a bundle resolving to a DIFFERENT app must read as gone, not as that other app")
    }
}

/// #404 review #5 and #3: the `--json` payload for an item the pre-install
/// re-check did not install, and the text-mode summary line's counts — both
/// pulled out as pure functions so their exact shape is testable without
/// capturing stdout or driving a real `InstallCoordinator`.
@Suite struct InstallApplySummaryTests {

    /// #404 review #5: when `reconsider` had no freshly re-derived route to
    /// give (the plan's route may already be stale by the time this fires),
    /// the payload OMITS the field rather than falling back to the plan's own
    /// route, which could contradict `reason`. Mutation (reverted after
    /// running): changed `if let route { payload["route"] = route.rawValue }`
    /// to unconditionally set `payload["route"] = route?.rawValue ?? "vendor"`
    /// — this test went red (expected no `route` key, found one).
    @Test func skippedPayloadOmitsRouteWhenThereIsNoneToGive() {
        let payload = Install.skippedPayload(
            name: "Fixture", route: nil, reason: "no readable bundle right now")
        #expect(payload["route"] == nil)
        #expect(payload["app"] as? String == "Fixture")
        #expect(payload["applied"] as? Bool == false)
    }

    @Test func skippedPayloadIncludesTheRouteWhenThereIsOne() {
        let payload = Install.skippedPayload(
            name: "Fixture", route: .vendor, reason: "already at 1.1 on disk — nothing to install")
        #expect(payload["route"] as? String == "vendor")
    }

    /// #404 review #3: a declined install is not a failure, but it must not
    /// vanish from the summary either. Mutation (reverted after running):
    /// dropped the `declined` clause from `Install.summaryLine` — this test
    /// went red (missing ", 1 declined" from the string).
    @Test func declinedElevationAppearsInTheSummaryLine() {
        #expect(Install.summaryLine(installed: 2, failed: 0, skipped: 0, declined: 1)
            == "2 installed, 0 failed, 1 declined.")
    }

    @Test func summaryLineOmitsZeroCounts() {
        #expect(Install.summaryLine(installed: 3, failed: 0, skipped: 0, declined: 0)
            == "3 installed, 0 failed.")
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
