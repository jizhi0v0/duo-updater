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
        /// Stable per-recipe key — the recipe's own id (`vendor:<bundle id>:<channel>`,
        /// `github:<owner>/<repo>:<channel>`, `changelog:…`), or a bare bundle id
        /// for a source whose recipes are one-per-app (the Electron manifest read).
        ///
        /// Per RECIPE and not per app, because an app can carry several: Zed and
        /// Zed Preview are two GitHub rules over one repo, Android Studio's Stable
        /// and Canary are two vendor recipes under one bundle id. Keyed by the
        /// thing they share, whichever ran last decided the verdict for both and a
        /// broken channel recipe read healthy on its sibling's success.
        ///
        /// **Not unique on its own.** The same bundle id can be tracked under
        /// more than one `source` at once — e.g. Notion carries both a
        /// hand-written `VendorProbeSource` recipe and (once `ElectronManifestSource`
        /// resolves it too) a generic Electron manifest read, and the two are
        /// independent recipes that can be healthy or broken independently. Use
        /// `key` where a value that is actually unique across every tracked entry
        /// is required (e.g. `ForEach`'s `id:` in the diagnostics view) — `id` by
        /// itself is a display key, not a storage key. See `RecipeHealth`'s own
        /// storage below, which keys on `(id, source)` for exactly this reason:
        /// keying on `id` alone let a later Electron success silently clear a
        /// standing Vendor miss for "the same id", masking a genuinely broken
        /// vendor recipe from the diagnostics panel entirely (caught in review of
        /// #201).
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

        /// A value that IS unique across every tracked entry, unlike `id` (see
        /// above). Uses a control character as the separator rather than
        /// something printable like `/` or `:` — both appear inside `id` itself
        /// (bundle ids, `owner/repo` slugs), so a printable separator could
        /// theoretically let two distinct `(id, source)` pairs collide on the
        /// same rendered string. Not `Codable`/persisted anywhere, so the exact
        /// encoding has no compatibility surface to preserve.
        public var key: String { "\(source)\u{0}\(id)" }

        /// The label a diagnostics row shows for this entry, given a bundle id →
        /// app name map.
        ///
        /// A recipe id carries its bundle id as one `:`-separated component rather
        /// than being one, so the plain lookup the panel used to do misses every id
        /// but the bare-bundle-id ones. Resolving the component and keeping the raw
        /// id alongside it is what lets a reader tell "Zed" from "Zed Preview" when
        /// both are listed — dropping the id would merge them on screen exactly
        /// where keying by the shared part merged them in storage.
        ///
        /// In Core rather than in the view because the view file has no test target
        /// over it; this is pure string work with a test next to it.
        public func displayName(resolving names: [String: String]) -> String {
            if let exact = names[id] { return exact }
            for part in id.split(separator: ":") where !part.isEmpty {
                if let name = names[String(part)] { return "\(name) · \(id)" }
            }
            return id
        }
    }

    /// Recipes are keyed by `(id, source)` together, not by `id` alone — see the
    /// note on `Entry.id`.
    private struct StorageKey: Hashable {
        let id: String
        let source: String
    }

    private var entries: [StorageKey: Entry] = [:]

    /// Record that `id` resolved a version. Clears any prior miss from the
    /// health verdict by advancing `lastSuccess` past it.
    public func recordSuccess(id: String, source: String) {
        let key = StorageKey(id: id, source: source)
        var entry = entries[key] ?? Entry(id: id, source: source)
        entry.lastSuccess = Date()
        entries[key] = entry
    }

    /// Record that `id` fetched successfully but matched no version — the shape of
    /// a recipe whose target page changed out from under it.
    public func recordMiss(id: String, source: String, detail: String?) {
        let key = StorageKey(id: id, source: source)
        var entry = entries[key] ?? Entry(id: id, source: source)
        entry.lastMiss = Date()
        entry.lastMissDetail = detail
        entries[key] = entry
    }

    /// Every tracked recipe, unhealthy ones first, then by id — with `source` as
    /// a tie-breaker so two entries sharing an `id` (see `Entry.id`) still sort
    /// deterministically against each other rather than by dictionary order.
    public func snapshot() -> [Entry] {
        entries.values.sorted { a, b in
            if a.isHealthy != b.isHealthy { return !a.isHealthy }
            let byID = a.id.localizedCaseInsensitiveCompare(b.id)
            if byID != .orderedSame { return byID == .orderedAscending }
            return a.source.localizedCaseInsensitiveCompare(b.source) == .orderedAscending
        }
    }

    /// Just the recipes whose latest outcome was a parse miss.
    public func unhealthy() -> [Entry] {
        snapshot().filter { !$0.isHealthy }
    }

    /// Test/diagnostic reset.
    public func reset() { entries.removeAll() }
}
