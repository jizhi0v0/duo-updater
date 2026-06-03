import Foundation

/// In-memory TTL cache for vendor changelog pages.
///
/// Re-opening an app's detail window within a session hits the cache instead of
/// making a fresh network round-trip (or two, for recipes with an
/// `indexLinkPattern` that first fetch an index to find the latest-release URL).
/// Entries expire after ``ttl`` seconds so the window always reflects recent
/// releases rather than a session-long snapshot.
///
/// Keyed on the recipe's canonical `source` URL so each recipe owns exactly one
/// cache slot, regardless of the per-run resolved detail URL (index redirects
/// don't inflate the key space). The cache stores parsed ``Changelog`` values —
/// not raw HTML — so it carries no ambiguity about what `nil` means.
///
/// Concurrent callers requesting the same URL while a fetch is in-flight are
/// coalesced onto a single `Task` (the same pattern ``HomebrewCaskCatalog`` uses
/// for its 5 MB catalog download), so each recipe is fetched at most once per
/// TTL window regardless of how many detail windows race.
///
/// Thread-safe via Swift's actor isolation. ``ChangelogService`` is the only
/// writer; the UI is the only reader.
public actor ChangelogCache {

    /// Shared instance — used by ``ChangelogService`` for all recipe loads and
    /// cleared by ``AppListModel`` on each manual refresh.
    public static let shared = ChangelogCache()

    private struct Entry {
        let changelog: Changelog
        let fetchedAt: Date
    }

    /// How long a cache entry lives before it is considered stale and the next
    /// ``load(for:fetch:)`` call re-fetches the page. Default is 15 minutes —
    /// changelog pages almost never update more frequently, and the detail window
    /// is opened many more times per session than the app is refreshed.
    public let ttl: TimeInterval

    private var store: [URL: Entry] = [:]

    /// In-flight fetch tasks, keyed by source URL. Concurrent callers that miss
    /// the cache for the same URL attach to the existing task instead of
    /// launching a redundant network request.
    private var inflight: [URL: Task<Changelog?, Never>] = [:]

    public init(ttl: TimeInterval = 15 * 60) {
        self.ttl = ttl
    }

    // MARK: - Public interface

    /// Fetch-through helper: return a cached entry if fresh, otherwise execute
    /// `fetch` exactly once per concurrent miss group and cache the result.
    ///
    /// If two callers miss simultaneously the second one joins the first's
    /// in-flight `Task` and both receive the same result — no double-fetch.
    public func load(
        for url: URL,
        fetch: @Sendable @escaping () async -> Changelog?
    ) async -> Changelog? {
        // 1. Cache hit.
        if let cached = get(for: url) { return cached }

        // 2. In-flight coalescing: a concurrent miss is already fetching this
        //    URL — attach to its task instead of launching another request.
        if let task = inflight[url] { return await task.value }

        // 3. Cache miss with no in-flight: start a new fetch task, register it
        //    immediately so any concurrent callers find it in step 2 above.
        let task = Task<Changelog?, Never> { await fetch() }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        if let result { set(result, for: url) }
        return result
    }

    /// Drop all cached entries and cancel any in-flight fetches. Called on a
    /// manual refresh so the user gets up-to-date release notes after explicitly
    /// asking for a fresh check.
    public func invalidateAll() {
        for task in inflight.values { task.cancel() }
        inflight.removeAll()
        store.removeAll()
    }

    // MARK: - Low-level access (also used by tests)

    /// Return the cached ``Changelog`` for `url` if still fresh; nil otherwise.
    /// A stale entry is evicted immediately so memory is freed without waiting
    /// for a full ``invalidateAll()``.
    public func get(for url: URL) -> Changelog? {
        guard let entry = store[url] else { return nil }
        guard Date().timeIntervalSince(entry.fetchedAt) < ttl else {
            store[url] = nil
            return nil
        }
        return entry.changelog
    }

    /// Store a freshly-fetched changelog under its recipe source URL.
    public func set(_ changelog: Changelog, for url: URL) {
        store[url] = Entry(changelog: changelog, fetchedAt: Date())
    }
}
