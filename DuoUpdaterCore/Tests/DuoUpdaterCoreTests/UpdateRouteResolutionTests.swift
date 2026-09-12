import Testing
@testable import DuoUpdaterCore

/// `UpdateRoute.resolve(_:)` — the ladder that decides how an available update
/// would be applied. Moved out of `AppListModel.rowRoute(for:)` (issue #261)
/// because `App/project.yml` has no test target, so this rung of the ladder had
/// been re-derived (not moved) when `RowActionState` made that trip and was
/// executed by nothing — only hand-compared against the view it replaced. Order
/// is significant and is the whole content of these tests, the same way it is for
/// `RowActionStateTests`.
@Suite("UpdateRoute.resolve")
struct UpdateRouteResolutionTests {

    /// A row that falls all the way through to `.detectionOnly` — every flag
    /// false, nothing staged. Tests build on this and flip one thing at a time.
    static func inputs(
        isToolboxManaged: Bool = false,
        isTestFlight: Bool = false,
        defersToSelfUpdater: Bool = false,
        isMajorUpgrade: Bool = false,
        canAutoInstall: Bool = false,
        requiresInstaller: Bool = false,
        stagedFileName: String? = nil,
        hasAppStoreAvailability: Bool = false,
        appStoreManagedHere: Bool = false,
        appStoreGate: AppStoreGate = .none
    ) -> RouteInputs {
        RouteInputs(
            isToolboxManaged: isToolboxManaged,
            isTestFlight: isTestFlight,
            defersToSelfUpdater: defersToSelfUpdater,
            isMajorUpgrade: isMajorUpgrade,
            canAutoInstall: canAutoInstall,
            requiresInstaller: requiresInstaller,
            stagedFileName: stagedFileName,
            hasAppStoreAvailability: hasAppStoreAvailability,
            appStoreManagedHere: appStoreManagedHere,
            appStoreGate: appStoreGate)
    }

    // MARK: - Every rung reachable on its own

    @Test("every rung fires when it is the only thing true")
    func eachRungAlone() {
        #expect(UpdateRoute.resolve(Self.inputs(isToolboxManaged: true)) == .toolbox)
        #expect(UpdateRoute.resolve(Self.inputs(isTestFlight: true)) == .testFlight)
        #expect(UpdateRoute.resolve(Self.inputs(defersToSelfUpdater: true)) == .selfUpdater)
        #expect(UpdateRoute.resolve(Self.inputs(isMajorUpgrade: true, canAutoInstall: true)) == .majorUpgrade)
        #expect(UpdateRoute.resolve(Self.inputs(canAutoInstall: true)) == .autoInstall)
        #expect(UpdateRoute.resolve(Self.inputs(requiresInstaller: true, stagedFileName: "App.pkg"))
                == .installer(stagedFileName: "App.pkg"))
        #expect(UpdateRoute.resolve(Self.inputs(hasAppStoreAvailability: true, appStoreManagedHere: true))
                == .appStore(managedHere: true, gate: .none))
        #expect(UpdateRoute.resolve(Self.inputs()) == .detectionOnly)
    }

    // MARK: - Precedence, pairwise against every rung below — a mutation guard for
    // rung order, the way `RowActionStateTests.inFlightPrecedence` is for the
    // sibling ladder. Each `#expect` fails if the winning rung is moved below the
    // one it is being compared against.

    @Test("toolbox outranks everything below it")
    func toolboxBeatsEverything() {
        #expect(UpdateRoute.resolve(Self.inputs(isToolboxManaged: true, isTestFlight: true)) == .toolbox)
        #expect(UpdateRoute.resolve(Self.inputs(isToolboxManaged: true, defersToSelfUpdater: true)) == .toolbox)
        #expect(UpdateRoute.resolve(Self.inputs(
            isToolboxManaged: true, isMajorUpgrade: true, canAutoInstall: true)) == .toolbox)
        #expect(UpdateRoute.resolve(Self.inputs(isToolboxManaged: true, canAutoInstall: true)) == .toolbox)
        #expect(UpdateRoute.resolve(Self.inputs(
            isToolboxManaged: true, requiresInstaller: true, stagedFileName: "x.pkg")) == .toolbox)
        #expect(UpdateRoute.resolve(Self.inputs(isToolboxManaged: true, hasAppStoreAvailability: true)) == .toolbox)
    }

    @Test("testFlight outranks everything below it")
    func testFlightBeatsEverything() {
        #expect(UpdateRoute.resolve(Self.inputs(isTestFlight: true, defersToSelfUpdater: true)) == .testFlight)
        #expect(UpdateRoute.resolve(Self.inputs(
            isTestFlight: true, isMajorUpgrade: true, canAutoInstall: true)) == .testFlight)
        #expect(UpdateRoute.resolve(Self.inputs(isTestFlight: true, canAutoInstall: true)) == .testFlight)
        #expect(UpdateRoute.resolve(Self.inputs(isTestFlight: true, hasAppStoreAvailability: true)) == .testFlight)
    }

    /// The invariant issue #261 asks to pin, together with the two tests above:
    /// `.toolbox` / `.testFlight` / `.selfUpdater` outrank `.majorUpgrade`, so a
    /// major upgrade on one of those routes shows the redirect, not the
    /// licence-boundary warning. Harmless — the redirect installs nothing here, so
    /// there is nothing for the warning to gate — but nothing stated it before
    /// this.
    @Test("selfUpdater outranks majorUpgrade")
    func selfUpdaterBeatsMajorUpgrade() {
        #expect(UpdateRoute.resolve(Self.inputs(
            defersToSelfUpdater: true, isMajorUpgrade: true, canAutoInstall: true)) == .selfUpdater)
        #expect(UpdateRoute.resolve(Self.inputs(
            defersToSelfUpdater: true, isMajorUpgrade: true, requiresInstaller: true)) == .selfUpdater)
    }

    @Test("majorUpgrade outranks autoInstall and installer")
    func majorUpgradeBeatsInstallRoutes() {
        #expect(UpdateRoute.resolve(Self.inputs(isMajorUpgrade: true, canAutoInstall: true)) == .majorUpgrade)
        #expect(UpdateRoute.resolve(Self.inputs(isMajorUpgrade: true, requiresInstaller: true)) == .majorUpgrade)
        #expect(UpdateRoute.resolve(Self.inputs(
            isMajorUpgrade: true, canAutoInstall: true, requiresInstaller: true)) == .majorUpgrade)
    }

    @Test("autoInstall outranks installer and appStore")
    func autoInstallBeatsBelow() {
        #expect(UpdateRoute.resolve(Self.inputs(canAutoInstall: true, requiresInstaller: true)) == .autoInstall)
        #expect(UpdateRoute.resolve(Self.inputs(canAutoInstall: true, hasAppStoreAvailability: true)) == .autoInstall)
    }

    @Test("installer outranks appStore")
    func installerBeatsAppStore() {
        #expect(UpdateRoute.resolve(Self.inputs(requiresInstaller: true, hasAppStoreAvailability: true))
                == .installer(stagedFileName: nil))
    }

    @Test("appStore outranks the detectionOnly default")
    func appStoreBeatsDetectionOnly() {
        #expect(UpdateRoute.resolve(Self.inputs(hasAppStoreAvailability: true)) == .appStore(managedHere: false, gate: .none))
    }

    // MARK: - The majorUpgrade gate: `isMajorUpgrade && (canAutoInstall ||
    // requiresInstaller)`

    @Test("majorUpgrade requires an install path — neither present falls through")
    func majorUpgradeGateRequiresAnInstallPath() {
        #expect(UpdateRoute.resolve(Self.inputs(isMajorUpgrade: true)) == .detectionOnly)
        #expect(UpdateRoute.resolve(Self.inputs(isMajorUpgrade: true, hasAppStoreAvailability: true))
                == .appStore(managedHere: false, gate: .none))
    }

    @Test("the gate is an OR: either half alone is enough")
    func majorUpgradeGateIsOr() {
        #expect(UpdateRoute.resolve(Self.inputs(
            isMajorUpgrade: true, canAutoInstall: true, requiresInstaller: false)) == .majorUpgrade)
        #expect(UpdateRoute.resolve(Self.inputs(
            isMajorUpgrade: true, canAutoInstall: false, requiresInstaller: true)) == .majorUpgrade)
    }

    // MARK: - Payload carried through unmodified

    @Test("installer carries the staged file name through")
    func installerCarriesStagedFileName() {
        #expect(UpdateRoute.resolve(Self.inputs(requiresInstaller: true, stagedFileName: "Foo-2.0.pkg"))
                == .installer(stagedFileName: "Foo-2.0.pkg"))
        #expect(UpdateRoute.resolve(Self.inputs(requiresInstaller: true, stagedFileName: nil))
                == .installer(stagedFileName: nil))
    }

    @Test("appStore carries managedHere through")
    func appStoreCarriesManagedHere() {
        #expect(UpdateRoute.resolve(Self.inputs(hasAppStoreAvailability: true, appStoreManagedHere: true))
                == .appStore(managedHere: true, gate: .none))
        #expect(UpdateRoute.resolve(Self.inputs(hasAppStoreAvailability: true, appStoreManagedHere: false))
                == .appStore(managedHere: false, gate: .none))
    }

    /// Mutation guard for issue #260's `gate`: if `resolve(_:)` stopped reading
    /// `inputs.appStoreGate` (hardcoding `.none`, say, the way the route used to
    /// carry no gate at all), this is the test that would go red — every other
    /// `.appStore` assertion above passes `appStoreGate: .none` by default and
    /// would not notice.
    @Test("appStore carries the gate through", arguments: [
        AppStoreGate.none, .region, .macIncompatible, .needsNewerMacOS(minimum: "15.6"),
    ])
    func appStoreCarriesGate(_ gate: AppStoreGate) {
        #expect(UpdateRoute.resolve(Self.inputs(hasAppStoreAvailability: true, appStoreGate: gate))
                == .appStore(managedHere: false, gate: gate))
    }
}

/// `AppStoreGate.resolve(_:)` — the precedence a view used to apply itself
/// (`appStoreTrailing`'s `if info.isLatestMacIncompatible … else if
/// info.isRegionMismatch …`), moved here so both windows read the same answer
/// off the route instead of each re-deriving it from `AppStoreAvailability`.
@Suite("AppStoreGate.resolve")
struct AppStoreGateResolutionTests {
    @Test("no listing at all resolves to none")
    func noListing() {
        #expect(AppStoreGate.resolve(nil) == .none)
    }

    @Test("an ordinary listing resolves to none")
    func ordinaryListing() {
        let info = AppStoreAvailability(trackID: 1, availableRegion: "us", homeRegion: "us", storeName: nil)
        #expect(AppStoreGate.resolve(info) == .none)
    }

    @Test("a region mismatch resolves to region")
    func regionMismatch() {
        let info = AppStoreAvailability(trackID: 1, availableRegion: "cn", homeRegion: "us", storeName: nil)
        #expect(AppStoreGate.resolve(info) == .region)
    }

    @Test("a Mac-incompatible latest build resolves to macIncompatible")
    func macIncompatible() {
        let info = AppStoreAvailability(
            trackID: 1, availableRegion: "us", homeRegion: "us", latestMacCompatible: false, storeName: nil)
        #expect(AppStoreGate.resolve(info) == .macIncompatible)
    }

    /// The precedence itself: when a listing is somehow both region-mismatched
    /// AND Mac-incompatible, `.macIncompatible` wins — same as the popover's old
    /// `if isLatestMacIncompatible … else if isRegionMismatch …` order. Deleting
    /// this ordering (checking `isRegionMismatch` first) makes this go red and
    /// nothing else in the suite would catch it, since every other case here
    /// only sets one flag at a time.
    @Test("macIncompatible outranks region when both are true")
    func macIncompatibleOutranksRegion() {
        let info = AppStoreAvailability(
            trackID: 1, availableRegion: "cn", homeRegion: "us", latestMacCompatible: false, storeName: nil)
        #expect(AppStoreGate.resolve(info) == .macIncompatible)
    }

    // MARK: - #546: needsNewerMacOS

    /// A stated floor above this "Mac"'s OS resolves to `.needsNewerMacOS`,
    /// carrying the floor for the explanation panel to quote. `osVersion` is
    /// passed explicitly rather than read from `ProcessInfo` — this repo's
    /// rule that a test must never ask the host what it's running (see
    /// CLAUDE.md) — so this pins the verdict independent of whatever OS this
    /// happens to run on.
    @Test("a floor above this Mac's OS resolves to needsNewerMacOS")
    func floorAboveHostResolvesToNeedsNewerMacOS() {
        let info = AppStoreAvailability(
            trackID: 1, availableRegion: "us", homeRegion: "us",
            latestMinimumMacOS: "26.0", storeName: nil)
        #expect(AppStoreGate.resolve(info, osVersion: "15.6.0") == .needsNewerMacOS(minimum: "26.0"))
    }

    /// A floor this Mac already meets resolves to `.none` — the gate must not
    /// fire just because the field is populated, only when the comparison
    /// actually fails. Also pins that the comparison is inclusive (`canRun`'s
    /// `!= .orderedAscending`): a host exactly AT the floor is not blocked.
    @Test("a floor this Mac already meets does not gate")
    func floorAtOrBelowHostDoesNotGate() {
        let exact = AppStoreAvailability(
            trackID: 1, availableRegion: "us", homeRegion: "us",
            latestMinimumMacOS: "15.6", storeName: nil)
        #expect(AppStoreGate.resolve(exact, osVersion: "15.6.0") == .none)

        let older = AppStoreAvailability(
            trackID: 1, availableRegion: "us", homeRegion: "us",
            latestMinimumMacOS: "12.0", storeName: nil)
        #expect(AppStoreGate.resolve(older, osVersion: "15.6.0") == .none)
    }

    /// `.macIncompatible` outranks `.needsNewerMacOS` — the more general verdict
    /// ("no Mac runs this any more") wins over the more specific one ("not one
    /// this old"). Mutation guard for the priority order in `resolve`: swapping
    /// these two checks would flip this to `.needsNewerMacOS(minimum: "26.0")`.
    @Test("macIncompatible outranks needsNewerMacOS when both are true")
    func macIncompatibleOutranksNeedsNewerMacOS() {
        let info = AppStoreAvailability(
            trackID: 1, availableRegion: "us", homeRegion: "us",
            latestMacCompatible: false, latestMinimumMacOS: "26.0", storeName: nil)
        #expect(AppStoreGate.resolve(info, osVersion: "15.6.0") == .macIncompatible)
    }

    /// `.needsNewerMacOS` outranks `.region` — an app that is both region-locked
    /// and past its OS floor names the OS reason, not the region one. Mutation
    /// guard: checking `isRegionMismatch` before the floor comparison would
    /// flip this to `.region`.
    @Test("needsNewerMacOS outranks region when both are true")
    func needsNewerMacOSOutranksRegion() {
        let info = AppStoreAvailability(
            trackID: 1, availableRegion: "cn", homeRegion: "us",
            latestMinimumMacOS: "26.0", storeName: nil)
        #expect(AppStoreGate.resolve(info, osVersion: "15.6.0") == .needsNewerMacOS(minimum: "26.0"))
    }

    /// A whole sentence, rather than the bare number `extractMacCompatibility`
    /// is supposed to reduce it to, must not gate — pins that `resolve` hands
    /// `canRun` the extracted numeric string, not prose.
    ///
    /// ⚠️ The mechanism this actually exercises is NOT `canRun`'s "no digits at
    /// all" bypass (`declared.rangeOfCharacter(from: .decimalDigits) != nil`) —
    /// "Requires macOS 26.0 or later." has digits, so that guard does not fire
    /// here. What fails it open is `VersionComparator`'s tokenizer: the
    /// sentence's FIRST token is "Requires" (text), "15.6.0"'s first token is
    /// numeric, and a numeric token always ranks above a text one — see
    /// `canRun`'s own doc comment ("any value whose FIRST token is
    /// non-numeric… also compares as satisfied regardless of the number that
    /// follows it"). Both paths are real fail-open behavior in `canRun`, but
    /// only one of them is what THIS input exercises — a value with truly no
    /// digits at all (`"unavailable"`, say) would hit the other one instead.
    /// `canRun`'s own behavior is tested where `canRun` itself lives; this only
    /// pins that `resolve` doesn't short-circuit around it for an unreadable
    /// value.
    @Test("an unreadable floor fails open")
    func unreadableFloorFailsOpen() {
        let info = AppStoreAvailability(
            trackID: 1, availableRegion: "us", homeRegion: "us",
            latestMinimumMacOS: "Requires macOS 26.0 or later.", storeName: nil)
        #expect(AppStoreGate.resolve(info, osVersion: "15.6.0") == .none)
    }
}
