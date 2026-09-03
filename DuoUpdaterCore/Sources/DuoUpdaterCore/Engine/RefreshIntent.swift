import Foundation

/// Why a full refresh (disk scan + network check) is running — and therefore
/// what it is allowed to touch besides the app list.
///
/// One refresh body serves two very different callers, and the difference is
/// not only whether the user is looking. A user-present refresh is a request:
/// *check again, and show me what is current* — so it may take the one read
/// that can raise a TCC prompt, and it starts the release notes over so what
/// the user opens next is re-read. The scheduler's tick is housekeeping the
/// user did not ask for and may not even notice: it must never prompt, and it
/// must not take away what is on screen — the notes the user is reading in
/// the workbench are not made stale by a check that found nothing new for
/// them. (When the check does find a new version, the notes are keyed by
/// version, so that app's pane moves to the new version's key on its own.)
///
/// **Why this lives in Core.** `AppListModel` has no test target, and the
/// distinction used to be carried by a `Bool` named for one of its
/// consequences (`allowTestFlight`), which is how the other consequence — the
/// wholesale changelog reset — came to run on every hourly tick under a
/// comment scoping it to a manual refresh.
public enum RefreshIntent: Sendable, Equatable {
    /// The user is here: the refresh button, a first menu/window open, or a
    /// re-check after they granted a permission.
    case userPresent
    /// The scheduler's silent tick, including the one a cold launch fires.
    case scheduled

    /// Whether this refresh may read the TestFlight container — the one read
    /// that triggers macOS's "access data from other apps" prompt. A silent
    /// check must never surface that unprompted.
    public var readsTestFlight: Bool {
        switch self {
        case .userPresent: true
        case .scheduled: false
        }
    }

    /// Whether this refresh starts the release notes over: expire the
    /// network-level changelog cache, drop every loaded/loading entry, and
    /// forget which entries the network has confirmed this session, so the
    /// prewarm that follows and the next open re-read them.
    public var restartsChangelogs: Bool {
        switch self {
        case .userPresent: true
        case .scheduled: false
        }
    }

    /// Whether a changelog entry is dropped before this refresh re-prewarms.
    ///
    /// A user-present refresh drops all of them (`restartsChangelogs`). A
    /// scheduled one keeps `.loaded` and `.loading` — that is the whole point
    /// — but still drops `.failed`: the prewarm skips keys that already have a
    /// state, and the workbench renders `.failed` as the web-page fallback
    /// without asking for a reload, so the wholesale reset was the only thing
    /// that ever retried a prewarm that lost the network. Dropping just those
    /// keeps that retry on the hourly cadence without touching what is on
    /// screen.
    public func dropsChangelogEntry(failed: Bool) -> Bool {
        switch self {
        case .userPresent: true
        case .scheduled: failed
        }
    }

    /// Whether a caller with this intent that coalesced onto an in-flight
    /// refresh still owes a pass of its own once that one finishes.
    ///
    /// Only one refresh runs at a time; a second caller awaits the first. A
    /// user-present caller landing on a scheduled tick would otherwise return
    /// with neither of its consequences delivered — no TestFlight read, and
    /// notes left exactly as they were — so it runs one full user-present pass
    /// afterwards. That pass starts with `.userPresent`, so it cannot land in
    /// this branch again against itself. Every other pairing is satisfied by
    /// the pass already running.
    public func owesFollowUp(afterCoalescingOnto inFlight: RefreshIntent) -> Bool {
        self == .userPresent && inFlight == .scheduled
    }
}
