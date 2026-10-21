import Foundation

/// Each row's `UpdateRoute`, kept until something it was resolved from changes.
///
/// A route is read on every repaint of a row with an update on offer — on a
/// download tick, every row in the list repaints — and resolving one rebuilds an
/// install environment several times and, for a pkg row with a package on disk,
/// stats it. Nothing about the route changes on a tick, so this keeps the answer
/// and the caller drops it when an input does.
///
/// The caller decides what "an input changed" means; this only keeps the
/// bookkeeping straight, which is where a memo goes wrong quietly. Every route is
/// stored under the generation it was resolved in, and `invalidate(generation:)`
/// drops the lot only if that generation is still current — so a late or
/// repeated invalidation from an earlier generation cannot throw away routes
/// resolved after it, and a route whose inputs changed WHILE it was being
/// resolved is returned to its caller but never kept.
///
/// Locked, because the caller's change notification is not promised to arrive
/// on the main actor (`withObservationTracking` calls `onChange` on whichever
/// thread made the change).
public final class RowRouteMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: UpdateRoute] = [:]
    private var generation = 0

    public init() {}

    /// The route kept for `id`, or `resolve`'s answer, kept for next time.
    /// `resolve` is called outside the lock with the generation its answer
    /// belongs to — what its own change notification passes back to
    /// `invalidate(generation:)`.
    public func route(for id: String, resolve: (_ generation: Int) -> UpdateRoute) -> UpdateRoute {
        let (kept, current) = lock.withLock { (routes[id], generation) }
        if let kept { return kept }
        let route = resolve(current)
        lock.withLock {
            if generation == current { routes[id] = route }
        }
        return route
    }

    /// Drop every kept route, if `generation` is still the current one. Returns
    /// whether it was — the caller repaints the rows only then.
    @discardableResult
    public func invalidate(generation stale: Int) -> Bool {
        lock.withLock {
            guard stale == generation else { return false }
            generation &+= 1
            routes.removeAll(keepingCapacity: true)
            return true
        }
    }
}
