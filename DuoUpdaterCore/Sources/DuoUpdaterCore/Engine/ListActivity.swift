import Foundation

/// What is currently in flight across the WHOLE app list, and which whole-list
/// actions that permits.
///
/// The three call sites this replaces — "can we refresh", "should Update All be
/// offered", "may `installAll` start" — were each spelled out longhand at their own
/// call site, in three different orders, over the same four flags. They were already
/// meant to be one predicate; keeping them as three copies is what let them drift.
///
/// The drift that motivated this (#253): a refresh does NOT hold `isScanning` or
/// `isChecking` for its whole duration. It sets `isScanning` for the scan leg,
/// clears it, then sets `isChecking` for the network leg — and in between it can
/// suspend. On a user-present refresh there are two such gaps:
///
///   1. before the scan, at `await ChangelogCache.invalidateAll()`, and
///   2. between the legs, at the TestFlight read (`await`, up to a 2s timeout).
///
/// Both suspend, so SwiftUI renders, and at that moment every one of the four flags
/// is false. "Update All" — hidden for the whole rest of the refresh — flashed back
/// into the header for up to two seconds and then vanished again, and the Refresh
/// button un-greyed alongside it. Worse than the flicker: the button was live, so a
/// click landed a batch install on top of a refresh that was still rewriting rows.
///
/// `isRefreshing` is the flag that IS true for the whole of a refresh, so it is the
/// one that closes the gap. It is deliberately part of `isIdle` rather than bolted
/// onto the button alone: the gap is in the flags, not in the button, and every
/// consumer of those flags was standing in it.
public struct ListActivity: Sendable, Equatable {
    /// True for the whole of a refresh, both legs and the suspensions between them.
    public var isRefreshing: Bool
    /// The local on-disk scan leg of a refresh.
    public var isScanning: Bool
    /// The network check leg of a refresh, or a standalone re-check of failed rows.
    public var isChecking: Bool
    /// A batch "Update All" is running.
    public var isInstallingAll: Bool
    /// At least one row has an install of its own in flight.
    public var hasRowInstalls: Bool

    /// Takes the row-install COUNT, not a pre-negated `hasRowInstalls` flag.
    ///
    /// The caller holds these as `installing: [String: InstallStage]`, so the
    /// natural spelling at the call site was `hasRowInstalls: !installing.isEmpty`
    /// — a negation on the App side, where there is no test target to hold it. A
    /// slip to `installing.isEmpty` inverts the entire gate (every whole-list
    /// action dead while idle, live while installing) and nothing would have caught
    /// it. Passing the count keeps the one polarity decision in Core, under test.
    public init(
        isRefreshing: Bool = false,
        isScanning: Bool = false,
        isChecking: Bool = false,
        isInstallingAll: Bool = false,
        rowInstallCount: Int = 0
    ) {
        self.isRefreshing = isRefreshing
        self.isScanning = isScanning
        self.isChecking = isChecking
        self.isInstallingAll = isInstallingAll
        self.hasRowInstalls = rowInstallCount > 0
    }

    /// Nothing that rewrites or mutates the list is in flight.
    ///
    /// Every whole-list action shares this one condition. They differ only in what
    /// they additionally require (Update All also wants more than one target), never
    /// in which flags mean "busy" — so they read this rather than re-listing them.
    public var isIdle: Bool {
        !isRefreshing && !isScanning && !isChecking && !isInstallingAll && !hasRowInstalls
    }

    /// A full networked refresh rewrites every row, so it stays out of the way while
    /// installs are mutating rows and replacing bundles — and while another refresh
    /// is already running, which is what `isRefreshing` adds over the older spelling.
    public var canRefresh: Bool { isIdle }

    /// Whether `installAll` may start. Same condition as `canRefresh`: a batch
    /// install and a refresh each assume they own the list.
    public var canInstallAll: Bool { isIdle }

    /// A scan/check round is in flight — a refresh (either leg, and the gaps
    /// between them) or a standalone re-check of failed rows.
    ///
    /// Deliberately NOT `!isIdle`: an install in flight also makes the list busy,
    /// but it is not a round, and the header's Refresh control must not turn into a
    /// progress spinner because a download is running. This is what the spinner and
    /// the "Checking N apps…" status line share, so the two cannot disagree — before
    /// #253 the spinner read the two leg flags and the status line read
    /// `isRefreshing`, so mid-gap the spinner reverted to the refresh arrow while the
    /// text beside it still said a check was running.
    public var isRoundInFlight: Bool { isRefreshing || isScanning || isChecking }

    /// Whether to OFFER the batch button, given how many apps it would act on.
    ///
    /// More than one, not at least one: with a single target the row's own "Update"
    /// button is already right there, and a batch button beside it is a second
    /// control for exactly the same action.
    /// `@autoclosure` is load-bearing, not decoration — DO NOT unwrap it to a plain
    /// `Int`. Callers pass `installAllTargets().count`, which filters every row
    /// through the per-row policy predicates (`canAutoInstall`, `requiresInstaller`,
    /// `defersToSelfUpdater`…). As a plain parameter that argument is evaluated
    /// BEFORE the call, so the whole sweep would run on every read even while a
    /// batch install is in flight — and `MenuContentView` reads this on every
    /// render, which during a download is every progress callback. The `&&` this
    /// replaced short-circuited on `!isInstallingAll` and never reached the sweep;
    /// the autoclosure is what preserves that.
    public func canOfferUpdateAll(targetCount: @autoclosure () -> Int) -> Bool {
        canInstallAll && targetCount() > 1
    }
}
