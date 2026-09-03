import Foundation

/// What one app row is currently asking of the user — the single answer both the
/// menu-bar popover and the workbench render.
///
/// The workbench is a magnified popover plus release notes, so the two must never
/// describe the same row differently. They used to each carry their own ladder of
/// `if`/`else if`, in different orders and with different coverage, and they had
/// already drifted apart in ways nothing could catch:
///
///  - the popover tested `awaitingQuitConfirm` FIRST and the install stage fifth;
///    the workbench tested the stage first and `awaitingQuitConfirm` third. Both
///    are true at once during an App Store install waiting for the user to quit the
///    app — so the same row showed a Relaunch prompt in one window and a progress
///    bar in the other.
///  - `justUpdated`, `ignored`, `versionSkipped`, `.error`, `.unknown` and the three
///    managed states had no workbench branch at all, so the workbench rendered
///    NOTHING for them. A row whose check had just failed looked exactly like a row
///    with nothing to do — in a window that offers an Update button for rows that
///    do have something to do, which makes "blank" read as "fine".
///
/// The ladder below is the popover's, which was the complete one. Order is
/// significant and is the whole content of this type: several of these conditions
/// are true simultaneously, and which one wins is the decision.
public enum RowActionState: Sendable, Equatable {
    /// An install needs the app quit and is asking the user to confirm. Carries the
    /// app name the prompt names.
    case awaitingQuitConfirm(String)
    /// A relaunch is in flight — the app's own updater or the store is swapping.
    case relaunching
    /// Installed by a batch that is holding relaunches until it finishes.
    case pendingBatchRestart
    /// Landed moments ago; a brief confirmation so the row does not just vanish.
    case justUpdated
    /// An install of ours is running on this row.
    case installing(InstallStage)
    /// The user hid this app from update checks. Never offers an action.
    case ignored
    /// The user skipped this specific version. Never offers an action.
    case versionSkipped
    /// The app's own updater already downloaded the latest and needs a relaunch.
    /// Carries the version it would relaunch into, so a view never has to go back
    /// to the model to write its own label.
    ///
    /// PRECONDITION on whoever fills `stagedRelaunchTarget`: only when the staged
    /// build IS the latest. A staged build that trails a newer release must fall
    /// through to Update (a direct jump), because relaunching into it would not get
    /// the user current — offering Relaunch there sends them to a stale version and
    /// calls it done. `AppListModel.actionableStaged` applies this; raw
    /// `pendingSelfUpdate` does not.
    case relaunchToApplyStaged(to: String)
    /// The bundle on disk is newer than the running process.
    case restartToApply
    /// A newer version is available and actionable. The route says how.
    case updateAvailable(UpdateRoute)
    /// A source was tried and failed. Carries its message AND whether it was the
    /// rate limit, because both surfaces label those differently and neither may
    /// re-derive it from `UpdateStatus` — doing that is how the popover drifted
    /// back into having a second opinion. Retryable, and NOT the same as having
    /// nothing to do, which is how a blank row reads.
    ///
    /// Deliberately carries no notion of how many rounds in a row this row has
    /// failed. `AppListModel` tracks that streak (`consecutiveCheckFailures`) and
    /// uses it to drop a chronically-failing row from the *aggregate* surfaces —
    /// the failed-check banner, the header count, the bulk-retry target list —
    /// once a failure looks permanent (a retired vendor feed fails identically
    /// forever). That is a call about whether the WHOLE-LIST claim "your checks
    /// are healthy" still holds; it says nothing about whether THIS row's own
    /// fact ("this check failed") is still true, which it always is until a
    /// check actually succeeds. So this state stays exactly as retryable at
    /// round 30 as at round 1 — see `AppListModel.failedCheckResults` and
    /// `CheckFailureRules` for the full reasoning (issue #264).
    case checkFailed(message: String, rateLimited: Bool)
    /// No source covers this app. Nothing was tried; nothing to retry. Carries
    /// what to name instead of an action — a view used to re-derive this from
    /// `result.app.isMASApp` / `sparkleFeedURL` (issue #260), which is how the
    /// two windows could in principle have drifted even though today they share
    /// one `sourceHint(for:)` function; the priority between the two lived in a
    /// view either way.
    case noSourceCovers(hint: SourceHint)
    /// Something else owns this app's updates.
    case managedElsewhere(Manager)
    /// Checked, current, nothing pending. Carries which channel to keep naming —
    /// a store-managed or TestFlight app must never look like something we could
    /// update ourselves just because it happens to be current, so the marker
    /// persists instead of collapsing to a bare checkmark. Used to be the
    /// popover's own `result.app.isMASApp` / `isTestFlightApp` check (issue #260);
    /// the workbench had no branch for it at all and drew `EmptyView` for all three.
    case upToDate(channel: UpToDateChannel)

    public enum Manager: Sendable, Equatable {
        case appStore, toolbox, testFlight
    }

    /// Which channel a current row keeps naming instead of drawing a bare
    /// checkmark. `.none` is the ordinary case: nothing else claims this app, so
    /// a plain checkmark is accurate.
    public enum UpToDateChannel: Sendable, Equatable {
        case none, appStore, testFlight
    }

    /// Whether this state offers to install an update. The two surfaces MUST agree
    /// on this exactly — one window offering an Update button while the other does
    /// not, for the same row at the same moment, is the failure this type exists to
    /// make impossible.
    public var offersUpdate: Bool {
        if case .updateAvailable(let route) = self { return route.isInstallable }
        return false
    }

    /// Whether the row is reporting something the user should notice rather than
    /// simply having nothing to do. A surface may render these differently, but
    /// none of them may render as blank.
    public var needsExplanation: Bool {
        switch self {
        case .checkFailed, .noSourceCovers, .ignored, .versionSkipped:
            return true
        case .updateAvailable(let route):
            return !route.isInstallable
        case .awaitingQuitConfirm, .relaunching, .pendingBatchRestart, .justUpdated,
             .installing, .relaunchToApplyStaged, .restartToApply, .managedElsewhere,
             .upToDate:
            return false
        }
    }
}

/// What a `.noSourceCovers` row names instead of an action. Used to be a view
/// function (`sourceHint(for: UpdateResult)`) reading `result.app.isMASApp` /
/// `sparkleFeedURL` directly — sharing the function kept the two windows from
/// disagreeing, but the opinion was still formed in the view layer (issue #260).
public enum SourceHint: Sendable, Equatable {
    /// Nothing we know of covers this app.
    case none
    /// Installed from the Mac App Store — we just have no read on its update
    /// status from here.
    case appStore
    /// Ships a Sparkle feed we don't have a recipe for yet.
    case sparkle
}

/// How an available update is applied — the branch taken once a row is known to
/// have an actionable update.
public enum UpdateRoute: Sendable, Equatable {
    /// JetBrains Toolbox owns the install; the action is "open Toolbox".
    case toolbox
    /// TestFlight installs it; the action is "open TestFlight".
    case testFlight
    /// A running self-updating app under the "defer while running" policy.
    case selfUpdater
    /// Crosses a major-version boundary: gated behind an explicit confirmation
    /// because it may need a new licence.
    case majorUpgrade
    /// We download and swap it ourselves.
    case autoInstall
    /// A vendor package handed to macOS's installer. Carries the file name when the
    /// package is already downloaded and only needs re-opening — `nil` means it has
    /// still to be fetched. Carried here rather than looked up by the view, so the
    /// rendering is a pure function of the state (which is what lets the gallery
    /// render every case without a model).
    case installer(stagedFileName: String?)
    /// Redirect to the App Store. `managedHere` is the wrapped iPhone/iPad case,
    /// where the store — not us — owns the download, and the button says so.
    /// `gate` says whether the listing is region-locked or Mac-incompatible, so a
    /// view never has to re-derive that from `AppStoreAvailability` itself — it
    /// used to (issue #260), which is how the workbench ended up collapsing both
    /// gates into one Label: the branch it switched on was `result.remote?.appStore`,
    /// not something the route carried.
    case appStore(managedHere: Bool, gate: AppStoreGate)
    /// Detected but not installable from here — no artifact, no route.
    case detectionOnly

    /// Routes where pressing the control starts an install we perform.
    public var isInstallable: Bool {
        switch self {
        case .autoInstall, .installer:
            return true
        case .toolbox, .testFlight, .selfUpdater, .majorUpgrade, .appStore, .detectionOnly:
            return false
        }
    }
}

/// Whether an App Store listing an `.appStore` route points at can actually be
/// installed from here. `.none` outranks nothing — a view checks it before
/// deciding between a one-click button and an explanatory badge.
public enum AppStoreGate: Sendable, Equatable {
    /// Nothing blocks it — a one-click install or redirect, per `managedHere`.
    case none
    /// Not listed in the signed-in account's storefront (`AppStoreAvailability.isRegionMismatch`).
    case region
    /// The latest build no longer runs on this Mac (`AppStoreAvailability.isLatestMacIncompatible`).
    case macIncompatible
}

extension AppStoreGate {
    /// Same precedence the popover's explanation used when both were somehow
    /// true for one listing: a build that no longer runs on this Mac at all is
    /// worth flagging over a region lock. `nil` (no App Store listing at all)
    /// resolves to `.none` — the caller only reaches this when there IS a
    /// listing (`RouteInputs.hasAppStoreAvailability`), so that branch is
    /// defensive rather than reachable.
    public static func resolve(_ info: AppStoreAvailability?) -> AppStoreGate {
        guard let info else { return .none }
        if info.isLatestMacIncompatible { return .macIncompatible }
        if info.isRegionMismatch { return .region }
        return .none
    }
}

/// Everything `UpdateRoute.resolve(_:)` reads about one row, gathered by the
/// caller so the decision itself stays pure and testable.
///
/// Moved out of `AppListModel.rowRoute(for:)` (issue #261): `App/project.yml`
/// carries no test target for `App/Sources`, so this was the one rung of the two
/// row-state ladders that had genuinely been re-derived rather than moved when
/// `RowActionState` made that trip, and it was executed by nothing — only
/// hand-compared against the view it replaced. `RowActionFacts.route` stays the
/// `@autoclosure` deferral point (`routeIsDeferred` pins that); this struct is
/// built inside it, on the caller's side, once per row that actually reaches
/// `.updateAvailable`.
public struct RouteInputs {
    /// `remote?.sourceName == "Toolbox" || app.isToolboxManaged` — JetBrains
    /// Toolbox owns the install outright.
    public var isToolboxManaged: Bool
    /// `remote?.sourceName == "TestFlight"`.
    public var isTestFlight: Bool
    /// `UpdatePolicy.defersToSelfUpdater(...)` — a running self-updating app under
    /// the "defer while running" policy.
    public var defersToSelfUpdater: Bool
    /// `UpdateResult.isMajorUpgrade`.
    public var isMajorUpgrade: Bool
    /// `UpdatePolicy.canAutoInstall(...)`.
    public var canAutoInstall: Bool
    /// `UpdatePolicy.requiresInstaller(...)`.
    public var requiresInstaller: Bool
    /// The staged package's file name, when one is already on disk for this row.
    /// Only meaningful — and only worth the caller stat'ing disk for — when
    /// `requiresInstaller` is true.
    public var stagedFileName: String?
    /// `remote?.appStore != nil`.
    public var hasAppStoreAvailability: Bool
    /// `app.isiOSAppOnMac && <App Store strategy is "full download">`.
    public var appStoreManagedHere: Bool
    /// `AppStoreGate.resolve(remote?.appStore)` — only meaningful when
    /// `hasAppStoreAvailability` is true, same as `appStoreManagedHere`.
    public var appStoreGate: AppStoreGate

    public init(
        isToolboxManaged: Bool,
        isTestFlight: Bool,
        defersToSelfUpdater: Bool,
        isMajorUpgrade: Bool,
        canAutoInstall: Bool,
        requiresInstaller: Bool,
        stagedFileName: String?,
        hasAppStoreAvailability: Bool,
        appStoreManagedHere: Bool,
        appStoreGate: AppStoreGate
    ) {
        self.isToolboxManaged = isToolboxManaged
        self.isTestFlight = isTestFlight
        self.defersToSelfUpdater = defersToSelfUpdater
        self.isMajorUpgrade = isMajorUpgrade
        self.canAutoInstall = canAutoInstall
        self.requiresInstaller = requiresInstaller
        self.stagedFileName = stagedFileName
        self.hasAppStoreAvailability = hasAppStoreAvailability
        self.appStoreManagedHere = appStoreManagedHere
        self.appStoreGate = appStoreGate
    }
}

extension UpdateRoute {
    /// How an available update would be applied — the ladder that used to live in
    /// `AppListModel.rowRoute(for:)`, moved verbatim. Order is significant and is
    /// the whole content of this function, the same way it is for
    /// `RowAction.state(for:)` above.
    ///
    /// Toolbox and TestFlight own their installs outright — the action is "open
    /// them", never an in-place swap — so they are checked first. The
    /// `.majorUpgrade` gate stays attached to the rung it guards, not hoisted
    /// out, and reads exactly `isMajorUpgrade && (canAutoInstall ||
    /// requiresInstaller)`: a major upgrade with neither an auto-install nor an
    /// installer path falls through instead, same as before.
    ///
    /// `.toolbox` / `.testFlight` / `.selfUpdater` deliberately outrank
    /// `.majorUpgrade` — a major upgrade on one of those routes still shows the
    /// redirect, not the licence-boundary warning. That is harmless: the redirect
    /// installs nothing here, so there is nothing for the warning to gate.
    /// Believed unreachable today (JetBrains ships calendar versions, and
    /// `UpdateResult.isMajorUpgrade` excludes those), but nothing stated the
    /// invariant before this, so it is pinned here regardless.
    public static func resolve(_ inputs: RouteInputs) -> UpdateRoute {
        if inputs.isToolboxManaged { return .toolbox }
        if inputs.isTestFlight { return .testFlight }
        if inputs.defersToSelfUpdater { return .selfUpdater }
        if inputs.isMajorUpgrade && (inputs.canAutoInstall || inputs.requiresInstaller) {
            return .majorUpgrade
        }
        if inputs.canAutoInstall { return .autoInstall }
        if inputs.requiresInstaller {
            return .installer(stagedFileName: inputs.stagedFileName)
        }
        if inputs.hasAppStoreAvailability {
            return .appStore(managedHere: inputs.appStoreManagedHere, gate: inputs.appStoreGate)
        }
        return .detectionOnly
    }
}

/// Everything the ladder reads about one row, gathered by the caller so the
/// decision itself stays pure and testable.
/// The per-row state a UI layer keeps outside `UpdateResult`, keyed by row id.
///
/// Exists so that filling `RowActionFacts` — deciding which table answers which
/// fact, and under which key — is testable. That wiring used to sit in
/// `AppListModel`, where nothing executes it, and it is the kind of code that
/// fails by looking right: a fact fed from the neighbouring table, or looked up
/// under `bundleID` where the tables are keyed by install path, compiles and
/// renders a plausible row.
public struct RowStateTables: Sendable {
    public var installing: [String: InstallStage]
    public var needsRestart: Set<String>
    public var pendingBatchRestart: [String: String]
    public var pendingSelfUpdate: [String: StagedSelfUpdate]
    public var relaunching: Set<String>
    public var awaitingQuitConfirm: [String: String]
    public var justUpdated: Set<String>

    public init(
        installing: [String: InstallStage] = [:],
        needsRestart: Set<String> = [],
        pendingBatchRestart: [String: String] = [:],
        pendingSelfUpdate: [String: StagedSelfUpdate] = [:],
        relaunching: Set<String> = [],
        awaitingQuitConfirm: [String: String] = [:],
        justUpdated: Set<String> = []
    ) {
        self.installing = installing
        self.needsRestart = needsRestart
        self.pendingBatchRestart = pendingBatchRestart
        self.pendingSelfUpdate = pendingSelfUpdate
        self.relaunching = relaunching
        self.awaitingQuitConfirm = awaitingQuitConfirm
        self.justUpdated = justUpdated
    }

    /// The same tables with **no defaults** — what a UI layer must use.
    ///
    /// Every parameter above has a default because the tests populate one table
    /// at a time on purpose, which is exactly the shape CLAUDE.md records for
    /// `RowActions`: nine closures with empty defaults meant a forgotten one
    /// compiled and shipped a dead button. Here there is one production caller,
    /// so adding an eighth table and forgetting to wire it would compile, render
    /// a plausible row, and be caught by nothing — not the gallery (which never
    /// goes through `assemble`), not `RowActionStateTests` (which builds facts
    /// directly), not the assembly suite (which populates partially by design).
    ///
    /// Calling this from the UI makes that omission a compile error at the one
    /// place it matters, the way `RowActions.live` does.
    public static func live(
        installing: [String: InstallStage],
        needsRestart: Set<String>,
        pendingBatchRestart: [String: String],
        pendingSelfUpdate: [String: StagedSelfUpdate],
        relaunching: Set<String>,
        awaitingQuitConfirm: [String: String],
        justUpdated: Set<String>
    ) -> RowStateTables {
        RowStateTables(
            installing: installing, needsRestart: needsRestart,
            pendingBatchRestart: pendingBatchRestart,
            pendingSelfUpdate: pendingSelfUpdate, relaunching: relaunching,
            awaitingQuitConfirm: awaitingQuitConfirm, justUpdated: justUpdated)
    }
}

public struct RowActionFacts {
    public var status: UpdateStatus
    public var awaitingQuitConfirm: String?
    public var isRelaunching: Bool
    public var hasPendingBatchRestart: Bool
    public var justUpdated: Bool
    public var installStage: InstallStage?
    public var isIgnored: Bool
    public var isVersionSkipped: Bool
    public var stagedRelaunchTarget: String?
    public var needsRestart: Bool
    /// `app.isMASApp` — read by the `.unknown` and `.upToDate` rungs to name the
    /// App Store as the source hint / kept channel, the same priority a view
    /// used to apply itself (issue #260).
    public var isMASApp: Bool
    /// `app.isTestFlightApp` — read by the `.upToDate` rung only; `.unknown`'s
    /// hint has no TestFlight case (see `SourceHint`).
    public var isTestFlightApp: Bool
    /// `app.sparkleFeedURL != nil` — read by the `.unknown` rung, second after
    /// `isMASApp`.
    public var hasSparkleFeed: Bool
    /// Deferred on purpose. Only the `.updateAvailable` rung reads it, and the
    /// caller's route resolution is the expensive part of assembling these facts —
    /// it rebuilds an install environment several times and can stat the disk. As a
    /// plain argument it ran for EVERY row on every repaint, including rows that
    /// leave the ladder at the quit prompt or the install stage and never look at
    /// it. Same trap as `ListActivity.canOfferUpdateAll`, which is why this is an
    /// `@autoclosure` too rather than a value.
    public var route: () -> UpdateRoute

    public init(
        status: UpdateStatus,
        awaitingQuitConfirm: String? = nil,
        isRelaunching: Bool = false,
        hasPendingBatchRestart: Bool = false,
        justUpdated: Bool = false,
        installStage: InstallStage? = nil,
        isIgnored: Bool = false,
        isVersionSkipped: Bool = false,
        stagedRelaunchTarget: String? = nil,
        needsRestart: Bool = false,
        isMASApp: Bool = false,
        isTestFlightApp: Bool = false,
        hasSparkleFeed: Bool = false,
        route: @autoclosure @escaping () -> UpdateRoute = .autoInstall
    ) {
        self.status = status
        self.awaitingQuitConfirm = awaitingQuitConfirm
        self.isRelaunching = isRelaunching
        self.hasPendingBatchRestart = hasPendingBatchRestart
        self.justUpdated = justUpdated
        self.installStage = installStage
        self.isIgnored = isIgnored
        self.isVersionSkipped = isVersionSkipped
        self.stagedRelaunchTarget = stagedRelaunchTarget
        self.needsRestart = needsRestart
        self.isMASApp = isMASApp
        self.isTestFlightApp = isTestFlightApp
        self.hasSparkleFeed = hasSparkleFeed
        self.route = route
    }

    public var hasUpdate: Bool {
        if case .updateAvailable = status { return true }
        return false
    }
}

public enum RowAction {
    /// The one ladder. Order is the decision — see the type's documentation.
    public static func state(for facts: RowActionFacts) -> RowActionState {
        if let appName = facts.awaitingQuitConfirm { return .awaitingQuitConfirm(appName) }
        if facts.isRelaunching { return .relaunching }
        if facts.hasPendingBatchRestart { return .pendingBatchRestart }
        if facts.justUpdated { return .justUpdated }
        if let stage = facts.installStage { return .installing(stage) }
        if facts.isIgnored { return .ignored }
        if facts.hasUpdate && facts.isVersionSkipped { return .versionSkipped }
        if let target = facts.stagedRelaunchTarget { return .relaunchToApplyStaged(to: target) }
        // Restart is derived from disk-vs-running version, not the remote check, so
        // it is answered here rather than inside the status switch: that keeps the
        // button steady across a refresh's transient `.unknown`, instead of briefly
        // flashing a source hint until the check lands.
        if facts.needsRestart && !facts.hasUpdate { return .restartToApply }

        switch facts.status {
        case .updateAvailable: return .updateAvailable(facts.route())
        case .error(let message):
            return .checkFailed(message: message, rateLimited: facts.status.isRateLimitError)
        case .unknown:
            // Same priority a view used to apply itself in `sourceHint(for:)`:
            // App Store first, Sparkle second, else nothing to name.
            if facts.isMASApp { return .noSourceCovers(hint: .appStore) }
            if facts.hasSparkleFeed { return .noSourceCovers(hint: .sparkle) }
            return .noSourceCovers(hint: .none)
        case .appStoreManaged: return .managedElsewhere(.appStore)
        case .toolboxManaged: return .managedElsewhere(.toolbox)
        case .testFlightManaged: return .managedElsewhere(.testFlight)
        case .upToDate:
            // Same priority the popover's `.upToDate` branch used to apply
            // itself: a store-managed app keeps the App Store marker even when
            // it also happens to run through TestFlight-style distribution.
            if facts.isMASApp { return .upToDate(channel: .appStore) }
            if facts.isTestFlightApp { return .upToDate(channel: .testFlight) }
            return .upToDate(channel: .none)
        }
    }
}

extension RowActionFacts {
    /// Fill the facts for one row from the tables a UI layer holds.
    ///
    /// Every table is looked up under `result.id`, which is the install PATH —
    /// two copies of one app share a bundle id and must not share a row's
    /// install stage or relaunch flag.
    ///
    /// `route` stays an `@autoclosure` all the way through: only the
    /// `.updateAvailable` rung reads it, and computing it is the expensive part
    /// of assembling facts (it rebuilds an `InstallEnvironment`, and stats the
    /// disk for pkg rows). This function must not call it — `routeIsDeferred`
    /// counts the calls.
    public static func assemble(
        for result: UpdateResult,
        tables: RowStateTables,
        isIgnored: Bool,
        isVersionSkipped: Bool,
        route: @escaping @autoclosure () -> UpdateRoute
    ) -> RowActionFacts {
        let staged = UpdatePolicy.actionableStaged(
            result, staged: tables.pendingSelfUpdate[result.id])
        return RowActionFacts(
            status: result.status,
            awaitingQuitConfirm: tables.awaitingQuitConfirm[result.id],
            isRelaunching: tables.relaunching.contains(result.id),
            hasPendingBatchRestart: tables.pendingBatchRestart[result.id] != nil,
            justUpdated: tables.justUpdated.contains(result.id),
            installStage: tables.installing[result.id],
            isIgnored: isIgnored,
            isVersionSkipped: isVersionSkipped,
            stagedRelaunchTarget: staged.map { result.stagedRelaunchLine($0).to },
            needsRestart: tables.needsRestart.contains(result.id),
            isMASApp: result.app.isMASApp,
            isTestFlightApp: result.app.isTestFlightApp,
            hasSparkleFeed: result.app.sparkleFeedURL != nil,
            route: route())
    }
}
