import Foundation

/// Everything the Network Activity panel draws, derived in one pass.
///
/// In Core rather than in the view for the reason `App/project.yml` makes
/// unavoidable: there is no test target over `App/Sources`, so a judgement made
/// in a `body` is a judgement nothing executes. Every rule here is one — which
/// purposes appear and in what order, how a share is computed when the total is
/// zero, when the retention caveat has to be shown, what counts as "quiet" — and
/// each of them is wrong in a way a screenshot would not reveal.
///
/// The view's job is `ui = f(summary)` and nothing else.
public struct NetworkActivitySummary: Sendable, Equatable {

    /// Wire bytes received across every retained total.
    public let bytesReceived: Int64
    /// Wire bytes sent.
    public let bytesSent: Int64
    /// Hops recorded, cache hits and failures included.
    public let requests: Int
    /// Distinct hosts contacted.
    public let hostCount: Int
    /// Hops answered 304 — asked, and nothing came back but headers.
    public let notModified: Int
    /// Hops `URLCache` answered with no network at all.
    public let cached: Int
    /// Hops that got no HTTP answer.
    public let failures: Int
    /// When the totals start. Nil when nothing has been recorded.
    public let since: Date?

    /// Per-purpose rollup, heaviest-by-nature first, purposes with nothing
    /// recorded omitted.
    public let byPurpose: [RequestTotal]
    /// Per-host rollup, heaviest first, already truncated to ``hostLimit``.
    public let topHosts: [RequestTotal]
    /// Hosts beyond ``topHosts``. Zero when everything is shown.
    public let remainingHosts: Int

    /// The retained events, newest last — the raw tail the panel lists.
    public let recent: [RequestEvent]
    /// How many events the store is holding in total, which is normally more than
    /// ``recent`` because the panel asks for a screenful.
    public let retainedEvents: Int
    /// Oldest retained event. Nil when none are retained.
    public let oldestEvent: Date?
    /// Bytes the store occupies on disk, write-ahead log included.
    public let storeBytes: Int64

    /// How many hosts the panel lists before it collapses the tail into a count.
    public static let hostLimit = 12

    public static let empty = NetworkActivitySummary(
        totals: .empty, recent: [], retainedEvents: 0,
        oldestEvent: nil, storeBytes: 0, client: nil)

    /// - Parameter client: which binary's traffic to report, or nil for both.
    ///   The panel passes `.app`: a `duo verify` sweep is ~150 diagnostic requests
    ///   and folding those into the window's numbers would misreport what the
    ///   background updater costs.
    public init(
        totals: RequestTotalsSnapshot,
        recent: [RequestEvent],
        retainedEvents: Int,
        oldestEvent: Date?,
        storeBytes: Int64,
        client: RequestClient?
    ) {
        let rows = totals.totals(for: client)
        bytesReceived = rows.reduce(0) { $0 + $1.bytesReceived }
        bytesSent = rows.reduce(0) { $0 + $1.bytesSent }
        requests = rows.reduce(0) { $0 + $1.requests }
        hostCount = Set(rows.map(\.host)).count
        notModified = rows.reduce(0) { $0 + $1.notModified }
        cached = rows.reduce(0) { $0 + $1.cachedRequests }
        failures = rows.reduce(0) { $0 + $1.failures }
        since = rows.map(\.firstSeen).min()

        byPurpose = totals.byPurpose(client: client)
        let hosts = totals.byHost(client: client)
        topHosts = Array(hosts.prefix(Self.hostLimit))
        remainingHosts = max(0, hosts.count - Self.hostLimit)

        self.recent = recent
        self.retainedEvents = retainedEvents
        self.oldestEvent = oldestEvent
        self.storeBytes = storeBytes
    }

    /// Nothing has ever been recorded, so the panel shows its empty state rather
    /// than a wall of zeroes.
    public var isEmpty: Bool { requests == 0 }

    /// This purpose's share of the received bytes, 0…1.
    ///
    /// Zero rather than a division by zero when nothing has been received — which
    /// is reachable with a real request count, not just on an empty store: a
    /// sweep in which every feed answered 304 from cache records hops and no
    /// bytes at all.
    public func share(_ total: RequestTotal) -> Double {
        guard bytesReceived > 0 else { return 0 }
        return Double(total.bytesReceived) / Double(bytesReceived)
    }

    /// Whether the panel must say that the totals reach further back than the
    /// events do.
    ///
    /// The two halves have different lifetimes by design — totals are kept
    /// forever, events are pruned — so after the retention window the totals
    /// legitimately account for traffic no listed event can explain. Two numbers
    /// on one screen that disagree have to say why, or the reader is left to
    /// conclude one of them is broken.
    public var showsRetentionCaveat: Bool {
        guard let since, let oldestEvent else { return false }
        // A second of slack: the first event of a run and the total it created
        // carry the same instant, and a strict comparison made the caveat flicker
        // on for a brand-new store.
        return oldestEvent.timeIntervalSince(since) > 1
    }
}
