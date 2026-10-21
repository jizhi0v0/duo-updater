import Foundation

/// The decisions an app row's controls make beyond WHICH `RowActionState` the
/// row is in — whether a Cancel stands beside the progress, whether a failed
/// check offers Retry, where a channel-switch hint goes, what a detection-only
/// row's button opens — answered once, here, for both windows.
///
/// `RowAction.state` took the ladder out of the views; these were the `if`s
/// left behind, each written into `PopoverRowAction` and `WorkbenchRowAction`
/// alike, and one of them had already drifted: a detection-only row whose page
/// is an app's own deep link (Chrome's `chrome://settings/help`) was handed to
/// that app by the popover and given to a plain `NSWorkspace.open` by the
/// workbench. The views now draw this and decide nothing.
///
/// The two windows still differ where that is a product decision, and the
/// difference is written here, as output, keyed on `Surface`: the popover
/// confirms a major upgrade in a panel of its own — the only place that offers
/// to back up for that one update, and where a channel-switch reminder rides
/// along — while the workbench names it with a label beside the hint and points
/// at the popover.
public struct RowActionControls: Sendable, Equatable {
    /// Which window draws the row.
    public enum Surface: Sendable, Equatable, CaseIterable {
        case popover, workbench
    }

    /// What the controls read besides the state, as plain values.
    public struct Facts: Sendable, Equatable {
        /// The running install's Cancel as the rows draw it
        /// (`AppListModel.installRows`); nil when the row's stage is no install
        /// of ours.
        public var installCancel: InstallCancelState?
        /// Until when GitHub's API budget is closed
        /// (`AppListModel.gitHubPausedUntil`).
        public var retryPausedUntil: Date?
        /// "Keep a backup so updates can be rolled back". Read by the popover's
        /// major-upgrade confirmation only.
        public var keepBackups: Bool
        /// Whether the privileged helper is approved.
        public var helperEnabled: Bool
        /// `UpdateResult.replacesChannelWithStable`.
        public var channelSwitch: ReleaseChannel?
        /// `result.remote?.pageURL` — where a detection-only row sends the user.
        public var pageURL: URL?

        public init(
            installCancel: InstallCancelState? = nil,
            retryPausedUntil: Date? = nil,
            keepBackups: Bool = true,
            helperEnabled: Bool = true,
            channelSwitch: ReleaseChannel? = nil,
            pageURL: URL? = nil
        ) {
            self.installCancel = installCancel
            self.retryPausedUntil = retryPausedUntil
            self.keepBackups = keepBackups
            self.helperEnabled = helperEnabled
            self.channelSwitch = channelSwitch
            self.pageURL = pageURL
        }

        /// The facts a row view holds: the row itself plus its own inputs.
        public init(
            result: UpdateResult,
            installCancel: InstallCancelState?,
            retryPausedUntil: Date?,
            keepBackups: Bool = true,
            helperEnabled: Bool
        ) {
            self.init(
                installCancel: installCancel, retryPausedUntil: retryPausedUntil,
                keepBackups: keepBackups, helperEnabled: helperEnabled,
                channelSwitch: result.replacesChannelWithStable,
                pageURL: result.remote?.pageURL)
        }
    }

    /// `.installing` only: the Cancel beside the progress. Nil once the cancel
    /// was accepted — "Cancelling…" replaces it (`installProgressLabel`).
    public var cancel: InstallCancelState?
    /// `.installing` only: what the progress draws.
    public var progress: InstallProgressReadout?
    /// `.checkFailed` only: whether Retry is offered. Not while GitHub's budget
    /// is closed on a rate-limited row — the gate would refuse it unsent, a
    /// click that does nothing.
    public var offersRetry = false
    /// The major-upgrade confirmation offers "Back Up & Update" — with backups
    /// off, a rollback point for this update only. The popover's alone: the
    /// workbench has no confirmation.
    public var offersBackUpOnce = false
    /// The channel-switch reminder, and where it goes.
    public var channelSwitch: ChannelSwitchHint?
    /// `.updateAvailable(.appStore(_, gate: .none))` only: which redirect.
    public var appStoreRedirect: AppStoreRedirect?
    /// `.updateAvailable(.detectionOnly)` only: what the button does.
    public var detectionOnly: DetectionOnlyAffordance?

    public init(
        cancel: InstallCancelState? = nil,
        progress: InstallProgressReadout? = nil,
        offersRetry: Bool = false,
        offersBackUpOnce: Bool = false,
        channelSwitch: ChannelSwitchHint? = nil,
        appStoreRedirect: AppStoreRedirect? = nil,
        detectionOnly: DetectionOnlyAffordance? = nil
    ) {
        self.cancel = cancel
        self.progress = progress
        self.offersRetry = offersRetry
        self.offersBackUpOnce = offersBackUpOnce
        self.channelSwitch = channelSwitch
        self.appStoreRedirect = appStoreRedirect
        self.detectionOnly = detectionOnly
    }

    /// The controls `surface` draws for a row in `state`.
    ///
    /// Exhaustive over the states on purpose: a new state has to say here
    /// whether it carries any of these, rather than quietly carrying none.
    public static func resolve(
        _ state: RowActionState, facts: Facts, surface: Surface
    ) -> RowActionControls {
        var controls = RowActionControls()
        switch state {
        case .installing(let stage):
            // Accepted: "Cancelling…" stands in for both the Cancel and the bar.
            // A cancelled download stops, so its bar would only freeze.
            let cancelling = facts.installCancel == .cancelling
            if !cancelling { controls.cancel = facts.installCancel }
            if case .downloading(let fraction) = stage, !cancelling {
                controls.progress = .fraction(fraction)
            } else {
                controls.progress = .spinner
            }

        case .checkFailed(_, let rateLimited):
            controls.offersRetry = !(rateLimited && facts.retryPausedUntil != nil)

        case .updateAvailable(let route):
            switch route {
            case .autoInstall, .installer:
                controls.channelSwitch = facts.channelSwitch.map {
                    ChannelSwitchHint(channel: $0, placement: .besideControl)
                }
            case .majorUpgrade:
                // A major upgrade can also be a channel switch (a nightly at
                // 0.4.5, the standard cask at 1.0.0); the reminder must not
                // vanish because the version also crossed a major (#1501).
                switch surface {
                case .popover:
                    controls.offersBackUpOnce = !facts.keepBackups
                    controls.channelSwitch = facts.channelSwitch.map {
                        ChannelSwitchHint(channel: $0, placement: .inConfirmation)
                    }
                case .workbench:
                    controls.channelSwitch = facts.channelSwitch.map {
                        ChannelSwitchHint(channel: $0, placement: .besideControl)
                    }
                }
            case .appStore(let managedHere, let gate):
                guard gate == .none else { break }
                // Approving the helper is the one lever the user has, so the
                // redirect names it when that is what's missing. A wrapped
                // iPhone/iPad app is a redirect on any helper: mas has no
                // Mac-store entry for it.
                controls.appStoreRedirect = managedHere ? .iPhoneApp
                    : facts.helperEnabled ? .openStore : .helperOff
            case .detectionOnly:
                controls.detectionOnly = DetectionOnlyAffordance.resolve(pageURL: facts.pageURL)
            case .toolbox, .testFlight, .selfUpdater, .appleSignIn:
                break
            }

        case .awaitingQuitConfirm, .relaunching, .pendingBatchRestart, .justUpdated,
             .interruptedInstall, .ignored, .versionSkipped, .relaunchToApplyStaged,
             .restartToApply, .noSourceCovers, .notForThisMacOS, .orphanedStoreCopy,
             .subscriptionHold, .managedElsewhere, .upToDate:
            break
        }
        return controls
    }
}

/// What a running install's progress draws.
public enum InstallProgressReadout: Sendable, Equatable {
    /// A download's fraction — a bar or a ring, as wide as the row allows.
    case fraction(Double)
    /// A spinner beside the stage's word, or "Cancelling…" once a cancel was
    /// accepted (`installProgressLabel`).
    case spinner
}

/// A reminder that the update puts the stable cask over a nightly or beta copy
/// (`UpdateResult.replacesChannelWithStable`). It sits beside the row's usual
/// control, never instead of it: brew's own `brew upgrade` makes the same switch.
public struct ChannelSwitchHint: Sendable, Equatable {
    public enum Placement: Sendable, Equatable {
        /// Before the row's control — an amber mark in the popover, a
        /// "Switches to stable" label in the workbench — opening the panel.
        case besideControl
        /// Above the popover's major-upgrade confirmation, which is where that
        /// route's install is offered.
        case inConfirmation
    }

    public var channel: ReleaseChannel
    public var placement: Placement

    public init(channel: ReleaseChannel, placement: Placement) {
        self.channel = channel
        self.placement = placement
    }
}

/// How an App Store row with nothing gating its listing hands off to the store.
public enum AppStoreRedirect: Sendable, Equatable {
    /// A wrapped iPhone/iPad app on the mas route: "App Store", to its product
    /// page, where an available update shows an Update button.
    case iPhoneApp
    /// "Update" in the store, with the helper not approved: says that approving
    /// it makes App Store updates one click.
    case helperOff
    /// "Update" in the store.
    case openStore
}
