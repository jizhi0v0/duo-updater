import Foundation

/// Load state for a recipe-backed changelog, driven by the model (not a view) so
/// it survives the user switching apps mid-fetch.
///
/// In Core so the states a prewarm settles on are executed by a test; the model
/// that holds them (`AppListModel`) is compiled by no test target.
public enum ChangelogLoadState {
    case loading
    case loaded(Changelog)
    /// A load that ran and got nothing. The workbench renders it as the web-page
    /// fallback and does not ask for a reload.
    case failed
    /// A prewarm that had nothing on disk and did not fetch, because the path
    /// was not one prefetching may use (Low Data Mode, an expensive network —
    /// `NetworkPathState.allowsDiscretionaryTraffic`, #898). Not a failure: the
    /// workbench renders it as a spinner that asks for the load on appear, so
    /// opening the pane — which the user asked for — loads the notes.
    case deferred

    /// The states a scheduled refresh is allowed to drop, so its prewarm runs
    /// again — see `RefreshIntent.dropsChangelogEntry(failed:)`, which is passed
    /// this. A deferred entry is owed that run as much as a failed one: nothing
    /// else fills it until the pane is opened.
    public var owesPrewarm: Bool {
        switch self {
        case .failed, .deferred: true
        case .loading, .loaded: false
        }
    }

    /// What a prewarm that has nothing to paint settles on.
    ///
    /// A prewarm that fetched and got nothing is `.failed`. One that was not
    /// allowed to fetch is `.deferred`, never `.failed`: `.failed` is the web
    /// fallback with no reload, so the pane would never load the notes while
    /// the path stays constrained — and the web page it loads instead costs more
    /// than the fetch that was put off. Nor is the key left unset: a key the
    /// prewarm claimed as `.loading` and then clears leaves a pane already on
    /// that spinner with no load and no fresh `onAppear` to ask for one.
    public static func unpainted(mayFetch: Bool) -> ChangelogLoadState {
        mayFetch ? .failed : .deferred
    }
}
