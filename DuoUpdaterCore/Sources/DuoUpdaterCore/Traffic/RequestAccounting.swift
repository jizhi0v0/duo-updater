import Foundation

/// What a request was *for*. The dimension `URLSessionTaskMetrics` cannot supply
/// and a hostname cannot stand in for.
///
/// Host is not a proxy for purpose and never will be: `github.com` answers a
/// version check, a changelog page and an installer download, and those three
/// have wildly different costs. So the purpose is stamped at the call site,
/// carried on the per-task delegate, and read back when the metrics arrive.
public enum RequestPurpose: String, Codable, Sendable, CaseIterable {
    /// A version feed, GitHub release API, Sparkle appcast, or vendor probe —
    /// anything asking "is there a newer build?".
    case versionCheck
    /// A vendor's release-notes page or feed, fetched to render a changelog.
    case changelog
    /// An image referenced by a changelog we already fetched.
    case changelogImage
    /// A bulk catalog: the Homebrew cask/formula index. Rare but large.
    case catalog
    /// An app's installer — the bytes that end up on disk. Also counted per-app
    /// by ``TrafficStore``; here so the request accounting's total is the whole
    /// picture rather than everything-except-the-big-one.
    case install
    /// DuoUpdater updating itself.
    case selfUpdate
    /// Anything not claimed above. A bucket that grows is a missing case, not a
    /// category.
    case other

    /// Display order for a breakdown: heaviest-by-nature first, so a report reads
    /// top-down even before the numbers arrive.
    public static let displayOrder: [RequestPurpose] =
        [.install, .selfUpdate, .catalog, .versionCheck, .changelog, .changelogImage, .other]
}

/// Which of our two binaries made the request.
///
/// Both write the same store — `duo` and the menu-bar app share
/// ``DuoStateDirectory`` — and a `duo verify` sweep is ~150 requests that are a
/// diagnostic, not the machine's ordinary update traffic. Tagged rather than
/// dropped: discarding them would make the accounting claim a completeness it
/// does not have, and the reader can filter.
public enum RequestClient: String, Codable, Sendable {
    case app
    case cli

    /// This process. Derived from the bundle id rather than set at launch so no
    /// entry point can forget to declare itself; anything that is not the
    /// menu-bar app (`duo`, the test bundle, the gallery tool) is `cli`.
    public static let current: RequestClient =
        Bundle.main.bundleIdentifier == "com.duoupdater.app" ? .app : .cli
}

/// Whether a byte count was measured on the wire or taken from someone's word.
public enum RequestByteSource: String, Codable, Sendable {
    /// Counted by `URLSessionTaskMetrics` — headers and body, after compression,
    /// as they actually crossed the socket.
    case measured
    /// Declared by a feed (a Sparkle appcast's `contentLength`) for a transfer
    /// made by code we do not own. Accurate to what the publisher wrote, which is
    /// not the same claim as `measured`.
    case declared
}

/// Running totals for one (client, purpose, host) triple.
///
/// Maintained in the same transaction as the event that feeds it (see
/// ``EventStore/append(_:)``), and — unlike the events — **never pruned**. The
/// two halves have different durability requirements: "what has this cost me
/// since I installed it" has to survive forever, "what exactly happened" must
/// not grow without bound. Totals are bounded by clients × purposes × hosts, so
/// keeping them forever costs a few tens of kilobytes.
///
/// The consequence has to be stated wherever both are shown: after the retention
/// window passes, the totals legitimately account for traffic whose events are
/// gone. That is not a discrepancy to be reconciled.
public struct RequestTotal: Codable, Sendable, Hashable, Identifiable {
    public let client: RequestClient
    /// Mutable only so a rollup can collapse the dimension away (``byHost``
    /// merges every purpose for one host, and the field then has no meaning).
    /// Nothing on the recording path reassigns it.
    public var purpose: RequestPurpose
    public let host: String
    /// Hops recorded, cache hits and failures included.
    public var requests: Int
    /// Hops `URLCache` answered with no network at all.
    public var cachedRequests: Int
    /// Hops that came back 304.
    public var notModified: Int
    /// Hops with no HTTP status — a transport failure or cancellation.
    public var failures: Int
    public var bytesSent: Int64
    public var bytesReceived: Int64
    public var firstSeen: Date
    public var lastSeen: Date

    public var id: String { "\(client.rawValue)|\(purpose.rawValue)|\(host)" }

    /// Hops that actually crossed the network.
    public var networkRequests: Int { requests - cachedRequests }

    public init(
        client: RequestClient, purpose: RequestPurpose, host: String,
        requests: Int = 0, cachedRequests: Int = 0, notModified: Int = 0,
        failures: Int = 0, bytesSent: Int64 = 0, bytesReceived: Int64 = 0,
        firstSeen: Date, lastSeen: Date
    ) {
        self.client = client
        self.purpose = purpose
        self.host = host
        self.requests = requests
        self.cachedRequests = cachedRequests
        self.notModified = notModified
        self.failures = failures
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    mutating func merge(_ other: RequestTotal) {
        requests += other.requests
        cachedRequests += other.cachedRequests
        notModified += other.notModified
        failures += other.failures
        bytesSent += other.bytesSent
        bytesReceived += other.bytesReceived
        firstSeen = min(firstSeen, other.firstSeen)
        lastSeen = max(lastSeen, other.lastSeen)
    }

    /// Bytes first, then request count, then host — a total order, so a snapshot
    /// is reproducible rather than however the rows came back.
    static func heavierFirst(_ a: RequestTotal, _ b: RequestTotal) -> Bool {
        if a.bytesReceived != b.bytesReceived { return a.bytesReceived > b.bytesReceived }
        if a.requests != b.requests { return a.requests > b.requests }
        return a.host.localizedCaseInsensitiveCompare(b.host) == .orderedAscending
    }
}

/// Every total, read out in one go, with the rollups a report needs.
public struct RequestTotalsSnapshot: Sendable {
    /// Every (client, purpose, host) triple ever seen, heaviest first.
    public let totals: [RequestTotal]

    public init(totals: [RequestTotal]) {
        self.totals = totals.sorted(by: RequestTotal.heavierFirst)
    }

    public static let empty = RequestTotalsSnapshot(totals: [])

    /// Totals for one client only, or all of them when `client` is nil.
    public func totals(for client: RequestClient?) -> [RequestTotal] {
        guard let client else { return totals }
        return totals.filter { $0.client == client }
    }

    /// Rolled up per purpose, in ``RequestPurpose/displayOrder``, skipping
    /// purposes with nothing recorded.
    public func byPurpose(client: RequestClient? = nil) -> [RequestTotal] {
        let rows = totals(for: client)
        return RequestPurpose.displayOrder.compactMap { purpose in
            let matching = rows.filter { $0.purpose == purpose }
            guard let first = matching.first else { return nil }
            var rolled = RequestTotal(
                client: client ?? first.client, purpose: purpose, host: "",
                firstSeen: first.firstSeen, lastSeen: first.lastSeen)
            for row in matching { rolled.merge(row) }
            return rolled
        }
    }

    /// Rolled up per host, heaviest first.
    public func byHost(client: RequestClient? = nil) -> [RequestTotal] {
        var merged: [String: RequestTotal] = [:]
        for row in totals(for: client) {
            if var existing = merged[row.host] {
                existing.merge(row)
                merged[row.host] = existing
            } else {
                var seed = row
                seed.purpose = .other   // meaningless once hosts are collapsed
                merged[row.host] = seed
            }
        }
        return merged.values.sorted(by: RequestTotal.heavierFirst)
    }
}
