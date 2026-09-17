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
            maxConcurrency: 12,
            // `.off` so nothing here reads the TestFlight store on the machine
            // running the tests — none of these cases is about TestFlight, and a
            // fixture that read it would put the host into the equation.
            testFlightDetection: .off, keepBackups: true, githubToken: nil, alcove: nil)
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
/// re-scan/re-check and calls this right before backup. Two things around
/// `coordinator.perform` remain verified by code reading, not a mutation-tested
/// unit test here (#404 review #2, #3) — see the PR description for what was
/// checked by hand: the `attempted` array `apply` builds to name apps still
/// running the old code afterward, and the `AuthorizationDeclinedError` catch
/// arm's CHOICE of `.declined` in the first place (`Install.swift`'s own
/// comment on that arm explains why a pure classifier wasn't worth it there).
/// What IS mutation-tested, by `#445`'s `InstallTallyTests`, is the other
/// half: once an outcome has been chosen, `Tally.record` mapping it to the
/// right counter — see `recordIncrementsExactlyTheMatchingCounter`.
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
            maxConcurrency: 12,
            // `.off` so nothing here reads the TestFlight store on the machine
            // running the tests — none of these cases is about TestFlight, and a
            // fixture that read it would put the host into the equation.
            testFlightDetection: .off, keepBackups: true, githubToken: nil, alcove: nil)
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

    /// The one `PreInstallDecision` arm nothing pinned. Its five siblings each
    /// have a case here; `.managedElsewhere` had none, so a re-mapping of it to
    /// `.proceed` — which would install a vendor artefact over a copy the App
    /// Store, Toolbox or TestFlight owns — compiled and passed the whole suite.
    ///
    /// Mutation (reverted after running): `case .managedElsewhere:` returning
    /// `.proceed(confirmed, .vendor)` in `Install.reconsider` — red here
    /// (expected a skip, got proceed), and green everywhere else.
    @Test func anAppThatBecameStoreManagedIsSkippedNotInstalled() {
        let offered = vendorOffer()
        // What a re-check answers for a copy the store has taken over between
        // the plan and this app's turn: not `.upToDate` (that is a claim about
        // versions), but a different owner for the update entirely.
        let confirmed = UpdateResult(
            app: app(), remote: nil, status: .appStoreManaged)
        let outcome = Install.reconsider(
            offered: offered, confirmed: confirmed, settings: settings(),
            environment: environment(), routes: [])
        guard case .skip(let why, let route) = outcome else {
            Issue.record("expected a skip, got \(outcome)")
            return
        }
        #expect(why.contains("managed elsewhere"))
        // No route: `reconsider` returns before `classify` runs, so there is no
        // freshly-derived route to report and the plan's is stale by then.
        #expect(route == nil)
    }

    /// #404 review #6: a re-scan that found no readable bundle (`recheckOne`
    /// returning `nil`, whether the app was uninstalled or its Info.plist
    /// failed to parse — `AppScanner.readApp` returns nil for both, and this
    /// cannot assert which) must NOT become `.cannotConfirm` — that reads as
    /// retryable, and re-running `duo install` cannot change whether a bundle
    /// exists right now. Mutation (reverted after running): in
    /// `Install.reconsider`, changed the `guard decision != .unreadable, let
    /// confirmed else { return .unreadable(...) }` at the top to
    /// `return .cannotConfirm(nil)` — this test went red (expected
    /// `.unreadable`, got `.cannotConfirm(nil)`).
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

/// #445: `Install.itemPlan` is the pure `ReconsiderOutcome` → `ItemPlan`
/// mapping the issue asked for — everything `apply`'s loop used to assemble by
/// hand (the text printed, the `--json` reason, the route, and which
/// `RowOutcome` bucket the item lands in) for one exit from the loop. Every
/// case below asserts all four `Terminal` fields, not just `outcome`: a test
/// that only checked the bucket would stay green if the reason or route
/// drifted, which is exactly the kind of disagreement #436 was filed about.
@Suite struct InstallItemPlanTests {

    private func vendorResult(latest: String = "1.2") -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1.0",
                buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Fixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: latest, version: nil,
                downloadURL: URL(string: "https://example.com/fixture.dmg"),
                sourceName: "Vendor", requiresManualInstaller: false,
                vendorInstallerKind: .dmg),
            status: .updateAvailable(latest: latest))
    }

    /// A result with no `remote` at all — the shape `.answerRegressed`'s
    /// `?? "?"` fallback exists for. `offered`/`confirmed` are otherwise
    /// unused by every `itemPlan` case but `.answerRegressed`; this stands in
    /// for both when a test doesn't care what they are.
    private func resultWithNoRemote() -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1.0",
                buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Fixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: nil, status: .unknown)
    }

    /// Mutation (reverted after running): changed the `.proceed` case in
    /// `Install.itemPlan` to `return .end(Terminal(outcome: .skipped, ...))`
    /// — went red (expected `.install`, got `.end`).
    @Test func proceedBecomesAnInstallCarryingTheConfirmedResultAndRoute() {
        let confirmed = vendorResult(latest: "1.2")
        let plan = Install.itemPlan(
            for: .proceed(confirmed, .vendor), offered: resultWithNoRemote(), confirmed: nil)
        guard case .install(let result, let route) = plan else {
            Issue.record("expected an install, got \(plan)")
            return
        }
        #expect(result.remote?.displayVersion == "1.2")
        #expect(route == .vendor)
    }

    /// Mutation (reverted after running): in the `.notRequested` case, changed
    /// `reason: "not requested: --route no longer includes it"` to
    /// `reason: "not requested"` — went red (reason mismatch).
    @Test func notRequestedNamesTheRouteInBothReasonAndConsole() {
        let plan = Install.itemPlan(
            for: .notRequested(.homebrew), offered: resultWithNoRemote(), confirmed: nil)
        guard case .end(let terminal) = plan else {
            Issue.record("expected an end, got \(plan)")
            return
        }
        #expect(terminal.outcome == .skipped)
        #expect(terminal.reason == "not requested: --route no longer includes it")
        #expect(terminal.route == .homebrew)
        #expect(terminal.console
            == "skipping: re-checked route is now homebrew, no longer requested")
    }

    /// Mutation (reverted after running): in the `.skip` case, changed
    /// `console: "skipping: \(why)"` to `console: why` (dropped the
    /// "skipping: " prefix that `apply` no longer adds itself) — went red
    /// (console text missing the prefix).
    @Test func skipCarriesTheGivenRouteReasonAndConsoleText() {
        let plan = Install.itemPlan(
            for: .skip("already at 1.1 on disk — nothing to install", .vendor),
            offered: resultWithNoRemote(), confirmed: nil)
        guard case .end(let terminal) = plan else {
            Issue.record("expected an end, got \(plan)")
            return
        }
        #expect(terminal.outcome == .skipped)
        #expect(terminal.reason == "already at 1.1 on disk — nothing to install")
        #expect(terminal.route == .vendor)
        #expect(terminal.console == "skipping: already at 1.1 on disk — nothing to install")
    }

    /// #404 review #5: `.unreadable` must carry `route == nil` — there is no
    /// freshly re-derived route to give. Mutation (reverted after running):
    /// changed `route: nil` to `route: .vendor` in the `.unreadable` case —
    /// went red (expected `nil`, got `.vendor`).
    @Test func unreadableHasNoRoute() {
        let why = "no readable bundle at /Applications/Fixture.app right now — it may have "
            + "been uninstalled, or its Info.plist could not be parsed"
        let plan = Install.itemPlan(for: .unreadable(why), offered: resultWithNoRemote(), confirmed: nil)
        guard case .end(let terminal) = plan else {
            Issue.record("expected an end, got \(plan)")
            return
        }
        #expect(terminal.outcome == .skipped)
        #expect(terminal.route == nil)
        #expect(terminal.reason == why)
        #expect(terminal.console == "skipping: \(why)")
    }

    /// `.cannotConfirm(nil)` must still produce the `"no source covers this
    /// app"` default reason, and carry `route == nil` (#404 review #5).
    /// Mutation (reverted after running): changed
    /// `outcome: .failed` to `outcome: .skipped` in the `.cannotConfirm` case
    /// — **this reinstates #436's exact defect** — went red (expected
    /// `.failed`, got `.skipped`).
    @Test func cannotConfirmWithNoMessageDefaultsTheReasonAndIsAFailure() {
        let plan = Install.itemPlan(for: .cannotConfirm(nil), offered: resultWithNoRemote(), confirmed: nil)
        guard case .end(let terminal) = plan else {
            Issue.record("expected an end, got \(plan)")
            return
        }
        #expect(terminal.outcome == .failed)
        #expect(terminal.reason == "no source covers this app")
        #expect(terminal.route == nil)
        #expect(terminal.console
            == "failed: the pre-install re-check could not confirm an update: no source covers this app")
    }

    @Test func cannotConfirmWithAMessageUsesItVerbatim() {
        let plan = Install.itemPlan(
            for: .cannotConfirm("connection timed out"), offered: resultWithNoRemote(), confirmed: nil)
        guard case .end(let terminal) = plan else {
            Issue.record("expected an end, got \(plan)")
            return
        }
        #expect(terminal.outcome == .failed)
        #expect(terminal.reason == "connection timed out")
        #expect(terminal.route == nil)
        #expect(terminal.console
            == "failed: the pre-install re-check could not confirm an update: connection timed out")
    }

    /// #404 review #5: `.answerRegressed` must carry `route == nil`. Mutation
    /// (reverted after running): changed `outcome: .failed` to
    /// `outcome: .skipped` in the `.answerRegressed` case — **the other half
    /// of #436's defect the issue named** — went red (expected `.failed`, got
    /// `.skipped`).
    @Test func answerRegressedNamesBothVersionsAndIsAFailure() {
        let plan = Install.itemPlan(
            for: .answerRegressed, offered: vendorResult(latest: "1.1"), confirmed: vendorResult(latest: "1.0"))
        guard case .end(let terminal) = plan else {
            Issue.record("expected an end, got \(plan)")
            return
        }
        #expect(terminal.outcome == .failed)
        #expect(terminal.reason == "answer regressed: offered 1.1, confirmed 1.0")
        #expect(terminal.route == nil)
        #expect(terminal.console
            == "failed: the update source answered 1.1, then 1.0 — nothing was installed.")
    }

    /// The version strings read `?? "?"` exactly when the `UpdateResult`s
    /// carry no `remote` — `apply` passes `item.result`/`confirmed` straight
    /// through, and either can be a result with no remote. Mutation
    /// (reverted after running): changed `offered.remote?.displayVersion ??
    /// "?"` to `?? ""` in `itemPlan`'s `.answerRegressed` case — went red
    /// (expected "offered ?, confirmed ?", got "offered , confirmed ?").
    @Test func answerRegressedFallsBackToQuestionMarksWhenVersionsAreMissing() {
        let plan = Install.itemPlan(
            for: .answerRegressed, offered: resultWithNoRemote(), confirmed: resultWithNoRemote())
        guard case .end(let terminal) = plan else {
            Issue.record("expected an end, got \(plan)")
            return
        }
        #expect(terminal.reason == "answer regressed: offered ?, confirmed ?")
    }
}

/// #445: `RowOutcome`'s five cases are exactly 1:1 with `apply`'s five
/// counters — `Tally` is the only place that mapping happens, replacing the
/// five separate `var`s `apply` used to increment by hand next to each exit
/// from its loop.
@Suite struct InstallTallyTests {

    /// All five counts distinct and nonzero, so a mutation that increments the
    /// wrong counter for some case is visible on that case's own field, not
    /// masked by another field happening to match. Mutation (reverted after
    /// running): swapped the `.openedInstaller`/`.declined` arms in
    /// `Tally.record` — went red (`openedInstaller` read 4, `declined` read 2).
    @Test func recordIncrementsExactlyTheMatchingCounter() {
        var tally = Install.Tally()
        tally.record(.installed)
        for _ in 0..<2 { tally.record(.openedInstaller) }
        for _ in 0..<3 { tally.record(.skipped) }
        for _ in 0..<4 { tally.record(.declined) }
        for _ in 0..<5 { tally.record(.failed) }
        #expect(tally.installed == 1)
        #expect(tally.openedInstaller == 2)
        #expect(tally.skipped == 3)
        #expect(tally.declined == 4)
        #expect(tally.failed == 5)
    }

    @Test func aFreshTallyIsAllZero() {
        let tally = Install.Tally()
        #expect(tally.installed == 0)
        #expect(tally.openedInstaller == 0)
        #expect(tally.skipped == 0)
        #expect(tally.declined == 0)
        #expect(tally.failed == 0)
    }

    /// `Install.summaryLine(_ tally:)` is the overload `apply` actually calls
    /// (#445) — it must forward every field to the right positional argument
    /// of the five-argument form, which the existing
    /// `summaryLineAccountsForAllFiveBucketsWhenEachIsNonzero` test pins.
    /// Five distinct, nonzero counts so a transposed forward is visible.
    /// Mutation (reverted after running): in the `Tally` overload, changed
    /// `declined: tally.declined` to `declined: tally.skipped` — went red
    /// (expected "4 declined", the string said "3 declined").
    @Test func summaryLineFromTallyForwardsEveryFieldToItsOwnArgument() {
        var tally = Install.Tally()
        tally.record(.installed)
        for _ in 0..<2 { tally.record(.openedInstaller) }
        for _ in 0..<3 { tally.record(.skipped) }
        for _ in 0..<4 { tally.record(.declined) }
        for _ in 0..<5 { tally.record(.failed) }
        #expect(Install.summaryLine(tally)
            == "1 installed, 5 failed, 3 skipped, 4 declined, 2 opened in the installer.")
    }

    /// #445, #435: the `applied` → `RowOutcome` decision, single-sourced so
    /// `installedPayload`'s `--json` category and `apply`'s counter can never
    /// disagree. Mutation (reverted after running): changed
    /// `applied ? .installed : .openedInstaller` to
    /// `applied ? .openedInstaller : .installed` — both tests below went red
    /// (each expected the opposite of what it got).
    @Test func rowOutcomeForAppliedIsInstalledWhenTrue() {
        #expect(Install.rowOutcome(forApplied: true) == .installed)
    }

    @Test func rowOutcomeForAppliedIsOpenedInstallerWhenFalse() {
        #expect(Install.rowOutcome(forApplied: false) == .openedInstaller)
    }
}

/// #404 review #5 and #3, plus #435/#436: the `--json` payloads for both an
/// actual install (`installedPayload`) and an item the pre-install re-check
/// did not install (`skippedPayload`), and the text-mode summary line's
/// counts — all pulled out as pure functions so their exact shape is testable
/// without capturing stdout or driving a real `InstallCoordinator`.
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
            name: "Fixture", route: nil, reason: "no readable bundle right now",
            outcome: .skipped)
        #expect(payload["route"] == nil)
        #expect(payload["app"] as? String == "Fixture")
        #expect(payload["applied"] as? Bool == false)
    }

    @Test func skippedPayloadIncludesTheRouteWhenThereIsOne() {
        let payload = Install.skippedPayload(
            name: "Fixture", route: .vendor, reason: "already at 1.1 on disk — nothing to install",
            outcome: .skipped)
        #expect(payload["route"] as? String == "vendor")
    }

    /// #436: before this, `emitSkipped` wrote the identical
    /// `{applied: false, reason: …}` shape for a real failure and an ordinary
    /// skip — a `--json` consumer had no way to separate them except by
    /// pattern-matching the English prose in `reason`, and rewording a
    /// message would silently reclassify a row. The two payloads below are
    /// built from the SAME `reason` text on purpose, to isolate the one
    /// thing that is supposed to tell them apart. Mutation (reverted after
    /// running): changed `skippedPayload` to ignore its `outcome` parameter
    /// and always write `"skipped"` — this test went red (the failure
    /// payload's `outcome` read `"skipped"` instead of `"failed"`, so the
    /// two payloads matched again).
    @Test func skippedPayloadDistinguishesFailureFromSkipByOutcomeNotReasonProse() {
        let sameReason = "already at 1.1 on disk — nothing to install"
        let skip = Install.skippedPayload(
            name: "Fixture", route: nil, reason: sameReason, outcome: .skipped)
        let failure = Install.skippedPayload(
            name: "Fixture", route: nil, reason: sameReason, outcome: .failed)
        #expect(skip["outcome"] as? String == "skipped")
        #expect(failure["outcome"] as? String == "failed")
        #expect(skip["reason"] as? String == failure["reason"] as? String)
    }

    @Test func skippedPayloadCarriesTheDeclinedOutcome() {
        let payload = Install.skippedPayload(
            name: "Fixture", route: .installer, reason: "administrator access was declined",
            outcome: .declined)
        #expect(payload["outcome"] as? String == "declined")
    }

    /// #435: `installedPayload` is what `emit` writes for an item
    /// `InstallCoordinator.perform` returned from without throwing. The
    /// `.installer` route returns `applied == false` (bytes fetched and
    /// verified, a system installer window open, nothing replaced yet) — the
    /// category must read `openedInstaller`, not `installed`. Mutation
    /// (reverted after running): changed the ternary in `installedPayload`
    /// from `outcome.applied ? .installed : .openedInstaller` to
    /// unconditionally `.installed` — this test went red (expected
    /// `"openedInstaller"`, found `"installed"`).
    @Test func installedPayloadReadsOpenedInstallerWhenNotApplied() {
        let outcome = InstallCoordinator.Outcome(
            bytesDownloaded: 12_000_000, finalHost: "example.com",
            stagedPackageURL: URL(fileURLWithPath: "/tmp/Fixture.pkg"), applied: false)
        let payload = Install.installedPayload(name: "Fixture", route: .installer, outcome: outcome)
        #expect(payload["outcome"] as? String == "openedInstaller")
        #expect(payload["applied"] as? Bool == false)
        #expect(payload["stagedPackage"] as? String == "/tmp/Fixture.pkg")
    }

    @Test func installedPayloadReadsInstalledWhenApplied() {
        let outcome = InstallCoordinator.Outcome(
            bytesDownloaded: 12_000_000, finalHost: "example.com",
            stagedPackageURL: nil, applied: true)
        let payload = Install.installedPayload(name: "Fixture", route: .vendor, outcome: outcome)
        #expect(payload["outcome"] as? String == "installed")
        #expect(payload["applied"] as? Bool == true)
    }

    /// #404 review #3: a declined install is not a failure, but it must not
    /// vanish from the summary either. Mutation (reverted after running):
    /// dropped the `declined` clause from `Install.summaryLine` — this test
    /// went red (missing ", 1 declined" from the string).
    @Test func declinedElevationAppearsInTheSummaryLine() {
        #expect(Install.summaryLine(
            installed: 2, failed: 0, skipped: 0, declined: 1, openedInstaller: 0)
            == "2 installed, 0 failed, 1 declined.")
    }

    @Test func summaryLineOmitsZeroCounts() {
        #expect(Install.summaryLine(
            installed: 3, failed: 0, skipped: 0, declined: 0, openedInstaller: 0)
            == "3 installed, 0 failed.")
    }

    /// #435: an `.installer` route must not be counted as "installed" — false
    /// at the exact moment the line prints, since nothing is on disk yet —
    /// and must not be silently folded into "skipped" either, since real work
    /// (a verified download) already happened. Mutation (reverted after
    /// running): dropped the `openedInstaller` clause from `summaryLine`
    /// entirely — this test went red (missing ", 1 opened in the installer").
    @Test func summaryLineNamesOpenedInstallerSeparatelyFromInstalledAndSkipped() {
        #expect(Install.summaryLine(
            installed: 0, failed: 0, skipped: 0, declined: 0, openedInstaller: 1)
            == "0 installed, 0 failed, 1 opened in the installer.")
    }

    /// The "every item in the plan is accounted for" invariant (#404 review
    /// #3) now spans five buckets, not four (#435). All five distinct and
    /// nonzero, so a mutation that dropped or mis-ordered any one clause is
    /// visible in the pinned string. Mutation (reverted after running):
    /// reordered the `declined` and `openedInstaller` clauses in
    /// `summaryLine` — this test went red (wrong order in the joined string).
    @Test func summaryLineAccountsForAllFiveBucketsWhenEachIsNonzero() {
        #expect(Install.summaryLine(
            installed: 1, failed: 2, skipped: 3, declined: 4, openedInstaller: 5)
            == "1 installed, 2 failed, 3 skipped, 4 declined, 5 opened in the installer.")
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
