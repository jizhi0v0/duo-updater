import Foundation
import Testing
@testable import DuoUpdaterCore

/// The states a changelog prewarm settles on when it has nothing to paint
/// (#898). `.failed` renders as the web fallback with no reload; a prewarm that
/// only skipped its fetch because of the network path must not land there, or
/// opening the pane never loads the notes while the path stays constrained.
struct ChangelogLoadStateTests {

    /// Mutation: `unpainted` answering `.failed` whatever `mayFetch` is.
    @Test func aPrewarmThatWasNotAllowedToFetchIsDeferredNotFailed() {
        let state = ChangelogLoadState.unpainted(mayFetch: false)
        guard case .deferred = state else {
            Issue.record("expected .deferred, got \(state)")
            return
        }
    }

    /// The existing behaviour for a fetch that ran and got nothing.
    /// Mutation: `unpainted` answering `.deferred` whatever `mayFetch` is.
    @Test func aPrewarmThatFetchedAndGotNothingIsFailed() {
        let state = ChangelogLoadState.unpainted(mayFetch: true)
        guard case .failed = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
    }

    /// A scheduled refresh drops deferred and failed entries so their prewarm
    /// runs again once the path allows it, and keeps what is loading or on
    /// screen. Mutation: drop `.deferred` from `owesPrewarm`.
    @Test func aScheduledRefreshRetriesDeferredAndFailedEntriesOnly() {
        let loaded = ChangelogLoadState.loaded(Changelog(entries: []))
        let dropped: [(String, ChangelogLoadState)] = [
            ("deferred", .deferred), ("failed", .failed), ("loading", .loading), ("loaded", loaded),
        ]
        let names = Set(dropped.filter {
            RefreshIntent.scheduled.dropsChangelogEntry(failed: $0.1.owesPrewarm)
        }.map(\.0))
        #expect(names == ["deferred", "failed"])
    }
}
