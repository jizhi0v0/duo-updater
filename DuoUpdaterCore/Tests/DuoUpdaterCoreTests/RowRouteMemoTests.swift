import Testing
@testable import DuoUpdaterCore

/// The bookkeeping behind `AppListModel.memoisedRoute`: what is kept, and what
/// an invalidation from which generation drops.
struct RowRouteMemoTests {

    final class Counter: @unchecked Sendable { var calls = 0 }

    /// A kept route is read, not resolved again — the repaint this exists for.
    /// Mutation: skip the lookup in `route(for:)` → two calls, red.
    @Test func aKeptRouteIsNotResolvedAgain() {
        let memo = RowRouteMemo()
        let counter = Counter()
        let resolve: (Int) -> UpdateRoute = { _ in counter.calls += 1; return .autoInstall }

        #expect(memo.route(for: "/A.app", resolve: resolve) == .autoInstall)
        #expect(memo.route(for: "/A.app", resolve: resolve) == .autoInstall)
        #expect(counter.calls == 1)

        // Per row: another row resolves its own.
        #expect(memo.route(for: "/B.app") { _ in .majorUpgrade } == .majorUpgrade)
        #expect(memo.route(for: "/A.app", resolve: resolve) == .autoInstall)
        #expect(counter.calls == 1)
    }

    /// An input changed: the next read resolves afresh.
    /// Mutation: leave `routes` alone in `invalidate` → the stale route is
    /// read back, red.
    @Test func invalidatingTheCurrentGenerationDropsTheRoutes() {
        let memo = RowRouteMemo()
        var generation = -1
        _ = memo.route(for: "/A.app") { generation = $0; return .autoInstall }

        #expect(memo.invalidate(generation: generation))
        #expect(memo.route(for: "/A.app") { _ in .installer(stagedFileName: nil) }
                == .installer(stagedFileName: nil))
    }

    /// A notification from a generation already dropped — a second input of the
    /// same route changing, or a route resolved before the last drop — must not
    /// throw away routes resolved since. It also says so, which is what stops
    /// the caller from repainting every row for nothing.
    /// Mutation: drop the generation check in `invalidate` → red.
    @Test func aStaleInvalidationKeepsLaterRoutes() {
        let memo = RowRouteMemo()
        var first = -1
        _ = memo.route(for: "/A.app") { first = $0; return .autoInstall }
        #expect(memo.invalidate(generation: first))

        let counter = Counter()
        _ = memo.route(for: "/A.app") { _ in counter.calls += 1; return .majorUpgrade }
        #expect(!memo.invalidate(generation: first))
        #expect(memo.route(for: "/A.app") { _ in counter.calls += 1; return .autoInstall } == .majorUpgrade)
        #expect(counter.calls == 1)
    }

    /// An input that changed WHILE the route was being resolved: the answer goes
    /// back to its caller, which asked, but is not kept for the next one.
    /// Mutation: store the route without comparing generations → the second
    /// read returns `.autoInstall` unresolved, red.
    @Test func aRouteResolvedAcrossAnInvalidationIsNotKept() {
        let memo = RowRouteMemo()
        let route = memo.route(for: "/A.app") { generation in
            memo.invalidate(generation: generation)
            return .autoInstall
        }
        #expect(route == .autoInstall)

        let counter = Counter()
        #expect(memo.route(for: "/A.app") { _ in counter.calls += 1; return .majorUpgrade } == .majorUpgrade)
        #expect(counter.calls == 1)
    }
}
