import Testing
import Foundation
@testable import DuoUpdaterCore

/// The rules behind the Network Activity panel.
///
/// Here rather than in the view because `App/project.yml` has no test target, so
/// a rule written into a `body` is one nothing ever executes. Each of these is a
/// decision that is wrong in a way a screenshot would not show.
@Suite
struct NetworkActivitySummaryTests {

    private static func total(
        _ host: String, _ purpose: RequestPurpose, client: RequestClient = .app,
        requests: Int = 1, received: Int64 = 0, sent: Int64 = 0,
        notModified: Int = 0, cached: Int = 0, failures: Int = 0,
        first: Date = Date(timeIntervalSince1970: 1_000), last: Date = Date(timeIntervalSince1970: 2_000)
    ) -> RequestTotal {
        RequestTotal(
            client: client, purpose: purpose, host: host, requests: requests,
            cachedRequests: cached, notModified: notModified, failures: failures,
            bytesSent: sent, bytesReceived: received, firstSeen: first, lastSeen: last)
    }

    private static func summary(
        _ totals: [RequestTotal], recent: [RequestEvent] = [], retained: Int = 0,
        oldest: Date? = nil, storeBytes: Int64 = 0, client: RequestClient? = .app
    ) -> NetworkActivitySummary {
        NetworkActivitySummary(
            totals: RequestTotalsSnapshot(totals: totals), recent: recent,
            retainedEvents: retained, oldestEvent: oldest, storeBytes: storeBytes,
            client: client)
    }

    @Test("`duo`'s own sweep is excluded from the window's numbers")
    func cliTrafficIsNotCountedForTheApp() {
        let summary = Self.summary([
            Self.total("github.com", .versionCheck, received: 100),
            Self.total("github.com", .versionCheck, client: .cli, requests: 150, received: 9_000),
        ])
        // A `duo verify` sweep is ~150 diagnostic requests. Folding those in is
        // how the panel starts misreporting what the background updater costs.
        #expect(summary.bytesReceived == 100)
        #expect(summary.requests == 1)
        #expect(summary.hostCount == 1)
    }

    @Test("Purposes appear heaviest-by-nature first, and only when they have traffic")
    func purposeOrderIsFixedAndSparse() {
        let summary = Self.summary([
            Self.total("a.example.com", .changelog, received: 10),
            Self.total("b.example.com", .install, received: 20),
            Self.total("c.example.com", .versionCheck, received: 30),
        ])
        // Declaration order, not byte order: the panel reads top-down as a story
        // about what the updater does, and a bar that reshuffles itself between
        // refreshes is unreadable.
        #expect(summary.byPurpose.map(\.purpose) == [.install, .versionCheck, .changelog])
    }

    @Test("A sweep that was entirely 304s reports its requests without dividing by zero")
    func shareIsZeroWhenNothingWasReceived() {
        // Reachable with a real request count, not only on an empty store: every
        // feed answering 304 records hops and no bytes.
        let rows = [Self.total("a.example.com", .versionCheck, requests: 40, notModified: 40)]
        let summary = Self.summary(rows)
        #expect(summary.requests == 40)
        #expect(summary.notModified == 40)
        #expect(summary.bytesReceived == 0)
        #expect(summary.share(rows[0]) == 0)
        #expect(!summary.isEmpty, "40 requests happened; the empty state would deny them")
    }

    @Test("Host list is truncated with an honest remainder")
    func hostListTruncates() {
        let rows = (0..<20).map {
            Self.total("h\($0).example.com", .versionCheck, received: Int64(1000 - $0))
        }
        let summary = Self.summary(rows)
        #expect(summary.topHosts.count == NetworkActivitySummary.hostLimit)
        #expect(summary.remainingHosts == 20 - NetworkActivitySummary.hostLimit)
        #expect(summary.hostCount == 20, "the count is of every host, not the listed ones")
        // Heaviest first, so the truncation drops the least interesting.
        #expect(summary.topHosts.first?.host == "h0.example.com")
    }

    @Test("Fewer hosts than the limit leaves nothing behind")
    func hostListDoesNotInventARemainder() {
        let summary = Self.summary([
            Self.total("a.example.com", .versionCheck, received: 5),
            Self.total("b.example.com", .versionCheck, received: 4),
        ])
        #expect(summary.topHosts.count == 2)
        #expect(summary.remainingHosts == 0)
    }

    @Test("The retention caveat appears exactly when the totals outreach the events")
    func retentionCaveat() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let rows = [Self.total("a.example.com", .versionCheck, received: 10, first: start)]

        // Events pruned back past the start of the totals: the panel must say so,
        // or two numbers that disagree read as one of them being broken.
        #expect(Self.summary(rows, retained: 5, oldest: start.addingTimeInterval(86_400))
            .showsRetentionCaveat)
        // Nothing pruned yet.
        #expect(!Self.summary(rows, retained: 5, oldest: start).showsRetentionCaveat)
        // No events at all is not a claim about retention.
        #expect(!Self.summary(rows, retained: 0, oldest: nil).showsRetentionCaveat)
        // A brand-new store: the first event and the total it created carry the
        // same instant, give or take. Without slack the caveat flickered on for a
        // store that had pruned nothing.
        #expect(!Self.summary(rows, retained: 1, oldest: start.addingTimeInterval(0.4))
            .showsRetentionCaveat)
    }

    @Test("An empty store is empty, and says nothing else")
    func emptyStore() {
        let summary = NetworkActivitySummary.empty
        #expect(summary.isEmpty)
        #expect(summary.byPurpose.isEmpty)
        #expect(summary.topHosts.isEmpty)
        #expect(summary.since == nil)
        #expect(!summary.showsRetentionCaveat)
    }
}
