import Foundation

/// The order rows appear in, and how a frozen order holds.
///
/// Split out of `AppListModel` because a sort is the kind of code that cannot
/// fail loudly: reorder two clauses and everything still compiles, still
/// renders, and the list is simply wrong in a way no assertion about any single
/// row can see. The repo already gives `DownloadReadout`'s declaration order its
/// own gate for exactly this reason.
public enum RowOrder {

    /// - Parameters:
    ///   - list: the rows to order.
    ///   - needsRestart: ids whose update is on disk and waiting on a relaunch.
    ///   - stagedSelfUpdates: raw staged self-updates by id. Filtered through
    ///     `UpdatePolicy.actionableStaged` here, once per row rather than once
    ///     per comparison — the version this replaced called it from inside the
    ///     comparator, so it ran O(n log n) times per sort.
    ///   - armedSelfInstallers: ids with an installer parked on the quit whose
    ///     staged build is unreadable. Ranked with the staged tier on the same
    ///     condition `RowAction.state` offers them Relaunch — an update on offer —
    ///     so a Relaunch row sits where every other Relaunch row does.
    ///   - pinnedOrder: the frozen slot of each row that existed when the order
    ///     was frozen. Empty when the order is live.
    public static func sorted(
        _ list: [UpdateResult],
        needsRestart: Set<String>,
        stagedSelfUpdates: [String: StagedSelfUpdate],
        armedSelfInstallers: Set<String>,
        pinnedOrder: [String: Int]
    ) -> [UpdateResult] {
        let relaunchable = Set(list.compactMap { row in
            UpdatePolicy.actionableStaged(row, staged: stagedSelfUpdates[row.id]) != nil
                || (armedSelfInstallers.contains(row.id) && row.hasUpdate)
                ? row.id : nil
        })

        func rank(_ r: UpdateResult) -> Int {
            if needsRestart.contains(r.id) { return 0 }
            // A staged build that IS the latest is one relaunch from live, just
            // like needs-restart — top tier. One that trails the latest ranks as
            // a normal pending update (it will show Update).
            if relaunchable.contains(r.id) { return 0 }
            if r.hasUpdate { return 1 }
            return 2
        }

        return list.sorted { a, b in
            // Frozen: pinned rows hold their recorded slot, and anything that
            // showed up since the freeze goes AFTER them — inserting into the
            // middle would push the pinned rows down, which is the thing being
            // prevented.
            if !pinnedOrder.isEmpty {
                switch (pinnedOrder[a.id], pinnedOrder[b.id]) {
                case let (pa?, pb?): return pa < pb
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): break  // both new — fall through to the normal order
                }
            }
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.app.name.localizedCaseInsensitiveCompare(b.app.name) == .orderedAscending
        }
    }
}

/// When the next background check should run.
///
/// Arithmetic rather than a policy object because that is all it is — but it is
/// arithmetic whose wrong version is silent: too long, and a relaunch sits up to
/// six hours showing nothing; too short, and rapid dev relaunches hammer every
/// vendor endpoint.
public enum CheckSchedule {

    /// The first check after launch uses this instead of the full interval.
    ///
    /// `lastCheck` is persisted across relaunches so we don't re-check on every
    /// launch, but a fresh process starts with an empty in-memory list — without
    /// a floor, a relaunch that inherited a recent `lastCheck` would sleep a
    /// whole interval showing nothing. Five minutes refreshes promptly after
    /// launch while still throttling rapid relaunches.
    public static let launchFloor: TimeInterval = 5 * 60

    /// - Returns: seconds to wait before the next check. Zero means run now.
    public static func nextWait(
        now: Date,
        lastCheck: Date?,
        interval: TimeInterval,
        isFirstCheck: Bool,
        hasResults: Bool
    ) -> TimeInterval {
        // A cold launch with nothing in memory yet shows the empty zero-badge
        // icon until something populates the list. Check immediately rather than
        // waiting out the floor, so the menu bar reflects real state right after
        // a launch without a click.
        //
        // ⚠️ `isFirstCheck &&` is load-bearing, and the two halves guard
        // different things. Zero here means "run now", NOT "looping here is
        // safe": when the caller then DEFERS the tick (offline, or a refresh
        // already running) it leaves `isFirstCheck` and `lastCheck` untouched,
        // so the next call answers zero again. Without the `isFirstCheck` half
        // any later tick that found an empty list — a scan that matched nothing,
        // everything filtered out — would do the same forever. The only thing
        // between that and an unthrottled run of network checks is the caller's
        // own back-off (`AppListModel`'s 60s sleep on the deferred branch), and
        // it lives in another package with nothing pointing at it from here.
        if isFirstCheck && !hasResults { return 0 }
        let effectiveInterval = isFirstCheck ? min(interval, launchFloor) : interval
        // Sleep only until the next check is DUE relative to the last one — zero
        // when already overdue.
        let due = (lastCheck ?? .distantPast).addingTimeInterval(effectiveInterval)
        return max(0, due.timeIntervalSince(now))
    }
}

/// What the system says about the current network path, as the three facts the
/// background work is decided on. `NetworkMonitor` fills it from `NWPath`; tests
/// build it by hand, since an `NWPath` cannot be made and Low Data Mode is a
/// system setting.
public struct NetworkPathState: Sendable, Equatable {
    /// `NWPath.status == .satisfied`.
    public var isSatisfied: Bool
    /// `NWPath.isConstrained`: the path uses an interface in Low Data Mode.
    public var isConstrained: Bool
    /// `NWPath.isExpensive`: the path uses an interface the system considers
    /// expensive, such as cellular or a Personal Hotspot.
    public var isExpensive: Bool

    public init(isSatisfied: Bool, isConstrained: Bool, isExpensive: Bool) {
        self.isSatisfied = isSatisfied
        self.isConstrained = isConstrained
        self.isExpensive = isExpensive
    }

    /// What is assumed before the first path update lands (`NWPathMonitor`
    /// reports the initial state asynchronously): usable, so a check can run.
    public static let assumedUsable = NetworkPathState(
        isSatisfied: true, isConstrained: false, isExpensive: false)

    /// Whether work the user did not ask for — the scheduled check, prefetching
    /// release notes and their images — may use this path.
    ///
    /// Apple's guidance for constrained paths (`URLRequest
    /// .allowsConstrainedNetworkAccess`) is to limit them to user-initiated tasks
    /// and put off discretionary ones until an unconstrained interface is
    /// available. An expensive path (a hotspot) is treated the same way.
    /// Explicit user actions — the Check button, Retry, installs — do not ask this.
    public var allowsDiscretionaryTraffic: Bool {
        deferralReason == nil
    }

    /// Why discretionary work is put off on this path, for the log; nil when it
    /// is not.
    public var deferralReason: String? {
        if !isSatisfied { return "offline" }
        if isConstrained { return "Low Data Mode" }
        if isExpensive { return "expensive network" }
        return nil
    }
}

extension CheckSchedule {
    /// Why a scheduled tick is deferred instead of run; nil means run it.
    ///
    /// A deferred tick leaves `lastCheck` untouched, so the check stays overdue
    /// and runs at the first tick after the reason clears (the caller retries on
    /// a short back-off). The path comes first: while it is unusable for
    /// background traffic, "busy" is not the reason the check is not running.
    public static func tickDeferral(path: NetworkPathState, canRefresh: Bool) -> String? {
        if let reason = path.deferralReason { return reason }
        return canRefresh ? nil : "busy"
    }
}
