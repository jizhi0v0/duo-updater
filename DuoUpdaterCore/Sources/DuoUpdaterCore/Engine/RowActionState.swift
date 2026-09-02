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
    case checkFailed(message: String, rateLimited: Bool)
    /// No source covers this app. Nothing was tried; nothing to retry.
    case noSourceCovers
    /// Something else owns this app's updates.
    case managedElsewhere(Manager)
    /// Checked, current, nothing pending.
    case upToDate

    public enum Manager: Sendable, Equatable {
        case appStore, toolbox, testFlight
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
    /// Carried in the route so a view never has to consult a setting to draw itself.
    case appStore(managedHere: Bool)
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

/// Everything the ladder reads about one row, gathered by the caller so the
/// decision itself stays pure and testable.
public struct RowActionFacts: Sendable {
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
    public var route: UpdateRoute

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
        route: UpdateRoute = .autoInstall
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
        case .updateAvailable: return .updateAvailable(facts.route)
        case .error(let message):
            return .checkFailed(message: message, rateLimited: facts.status.isRateLimitError)
        case .unknown: return .noSourceCovers
        case .appStoreManaged: return .managedElsewhere(.appStore)
        case .toolboxManaged: return .managedElsewhere(.toolbox)
        case .testFlightManaged: return .managedElsewhere(.testFlight)
        case .upToDate: return .upToDate
        }
    }
}
