import Foundation

/// Tracks whether our hand-curated detection recipes (vendor probes and GitHub
/// release rules) are still working, so a vendor quietly changing their markup
/// becomes *visible* instead of silently degrading an app to "unknown."
///
/// The signal is two timestamps per recipe: the last time it resolved a version
/// (`lastSuccess`) and the last time it fetched fine but matched nothing
/// (`lastMiss`). A recipe is considered unhealthy when its most recent outcome
/// was a miss — `lastMiss` later than `lastSuccess`, or a miss with no success at
/// all this session. This self-heals: a one-off network blip that records a miss
/// is cleared by the next successful check, so the diagnostics list only fills
/// with recipes that are *consistently* failing to parse.
///
/// State is in-memory and session-scoped: DuoUpdater is a long-running menu-bar
/// app, and "is this recipe working right now?" is exactly the question the
/// diagnostics panel answers. A process restart starts the assessment fresh.
public actor RecipeHealth {

    public static let shared = RecipeHealth()
    public init() {}

    public struct Entry: Sendable, Equatable, Identifiable {
        /// Stable per-recipe key, e.g. a bundle id or an `owner/repo` slug.
        public let id: String
        /// Human-readable source name for the diagnostics row ("Vendor", "GitHub").
        public let source: String
        public var lastSuccess: Date?
        public var lastMiss: Date?
        public var lastMissDetail: String?

        /// True when the recipe's latest outcome was a successful parse (or it has
        /// never missed). False only when the most recent thing that happened was a
        /// parse miss with nothing newer to clear it.
        public var isHealthy: Bool {
            guard let lastMiss else { return true }
            guard let lastSuccess else { return false }
            return lastSuccess >= lastMiss
        }
    }

    private var entries: [String: Entry] = [:]

    /// Record that `id` resolved a version. Clears any prior miss from the
    /// health verdict by advancing `lastSuccess` past it.
    public func recordSuccess(id: String, source: String) {
        var entry = entries[id] ?? Entry(id: id, source: source)
        entry.lastSuccess = Date()
        entries[id] = entry
    }

    /// Record that `id` fetched successfully but matched no version — the shape of
    /// a recipe whose target page changed out from under it.
    public func recordMiss(id: String, source: String, detail: String?) {
        var entry = entries[id] ?? Entry(id: id, source: source)
        entry.lastMiss = Date()
        entry.lastMissDetail = detail
        entries[id] = entry
    }

    /// Every tracked recipe, unhealthy ones first, then by id.
    public func snapshot() -> [Entry] {
        entries.values.sorted { a, b in
            if a.isHealthy != b.isHealthy { return !a.isHealthy }
            return a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
        }
    }

    /// Just the recipes whose latest outcome was a parse miss.
    public func unhealthy() -> [Entry] {
        snapshot().filter { !$0.isHealthy }
    }

    /// Test/diagnostic reset.
    public func reset() { entries.removeAll() }
}
