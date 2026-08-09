import Foundation

/// One cask's relevant fields.
public struct CaskEntry: Sendable {
    public let token: String
    public let version: String
    public let url: URL?
    public let autoUpdates: Bool
    /// True when the cask installs via a `pkg`/`installer` artifact rather than
    /// dragging a `.app`. These need admin rights, so we can't run them through
    /// non-interactive brew — we download the official package and open it.
    public let isPkg: Bool
}

/// Two lookup tables over the cask catalog: by `.app` filename (the primary,
/// most reliable key) and by bundle identifier (a fallback for casks that
/// install via `pkg` and so declare no `.app` artifact, e.g. AweSun).
struct CaskIndex: Sendable {
    let byAppFilename: [String: CaskEntry]
    let byBundleID: [String: CaskEntry]
}

/// Loads the full Homebrew Cask catalog from formulae.brew.sh once and indexes
/// it by the `.app` filename each cask installs (e.g. "TablePlus.app"), plus a
/// bundle-identifier fallback drawn from each cask's `uninstall: quit:` field.
///
/// The catalog is ~5 MB, so we fetch and parse it a single time and reuse the
/// index for every app in a check run.
public actor HomebrewCaskCatalog {
    public static let shared = HomebrewCaskCatalog()

    private var index: CaskIndex?
    private var indexLoadedAt: Date?
    private var loadTask: Task<CaskIndex, Error>?

    /// How long a loaded index is reused before being refetched.
    ///
    /// The index used to be memoized for the life of the process. That's fine for
    /// a CLI and wrong for a menu-bar app that runs for weeks: every Homebrew-
    /// sourced app stayed pinned to whatever the catalog said the day the app
    /// launched, reporting "up to date" forever with no error — the same silent
    /// shape as a stale HTTP cache (see ``URLRequest/versionFeedCachePolicy``),
    /// and immune to that fix because the in-memory index short-circuits the
    /// request entirely.
    ///
    /// Six hours, not minutes: the refetch is a full 5 MB whenever the catalog
    /// actually changed (which is most of the time — brew publishes constantly),
    /// so this trades a few hours of staleness for bounded background traffic.
    /// Only paid on machines that have casks installed at all; `HomebrewCaskSource`
    /// declines before touching the catalog when the Caskroom is empty.
    static let indexTTL: TimeInterval = 6 * 60 * 60

    /// Test seam: an index seeded via `init(testIndex:)` never expires, so
    /// offline tests don't reach the network partway through.
    private var indexNeverExpires = false

    private let session: URLSession
    public init(session: URLSession = .updates) {
        self.session = session
    }

    /// Test seam: seed a fixed index so source-level tests run offline instead of
    /// fetching the 5 MB live catalog.
    init(testIndex: CaskIndex) {
        self.session = .shared
        self.index = testIndex
        self.indexNeverExpires = true
    }

    /// Look up the cask that installs an app with the given bundle filename.
    public func entry(forAppFilename filename: String) async throws -> CaskEntry? {
        try await loadedIndex().byAppFilename[filename.lowercased()]
    }

    /// Fallback lookup by bundle identifier, for casks with no `.app` artifact.
    public func entry(forBundleID bundleID: String) async throws -> CaskEntry? {
        try await loadedIndex().byBundleID[bundleID.lowercased()]
    }

    private func loadedIndex() async throws -> CaskIndex {
        if let index, !isExpired { return index }
        // Coalesce concurrent callers onto a single in-flight load.
        if let loadTask { return try await loadTask.value }

        let task = Task { try await Self.fetchAndIndex(session: session) }
        loadTask = task
        do {
            let idx = try await task.value
            index = idx
            indexLoadedAt = Date()
            loadTask = nil
            return idx
        } catch {
            loadTask = nil
            // A refetch that fails keeps serving the last good index rather than
            // dropping every Homebrew row to "unknown" on one bad network moment.
            if let index { return index }
            throw error
        }
    }

    private var isExpired: Bool {
        guard !indexNeverExpires else { return false }
        guard let indexLoadedAt else { return true }
        return Date().timeIntervalSince(indexLoadedAt) >= Self.indexTTL
    }

    private static func fetchAndIndex(session: URLSession) async throws -> CaskIndex {
        let url = URL(string: "https://formulae.brew.sh/api/cask.json")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CaskError.badStatus(http.statusCode)
        }

        // artifacts is a heterogeneous array, so walk the JSON manually rather
        // than fighting Codable over its shape.
        guard let casks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CaskError.malformed
        }

        var byApp: [String: CaskEntry] = [:]
        var byBundle: [String: CaskEntry] = [:]
        for cask in casks {
            guard
                let token = cask["token"] as? String,
                let version = cask["version"] as? String,
                version != "latest"
            else { continue }

            let entry = CaskEntry(
                token: token,
                version: version,
                url: (cask["url"] as? String).flatMap { URL(string: $0) },
                autoUpdates: (cask["auto_updates"] as? Bool) ?? false,
                isPkg: hasPackageArtifact(in: cask["artifacts"])
            )

            // First writer wins; tokens are processed in catalog order.
            for appName in appFilenames(in: cask["artifacts"]) {
                let key = appName.lowercased()
                byApp[key] = byApp[key] ?? entry
            }
            for bundleID in bundleIDs(in: cask["artifacts"]) {
                let key = bundleID.lowercased()
                byBundle[key] = byBundle[key] ?? entry
            }
        }
        return CaskIndex(byAppFilename: byApp, byBundleID: byBundle)
    }

    /// Extract the `.app` filenames from a cask's `artifacts` array. Each app
    /// artifact looks like `{"app": ["Foo.app", {"target": "..."}]}`.
    private static func appFilenames(in artifacts: Any?) -> [String] {
        guard let artifacts = artifacts as? [Any] else { return [] }
        var names: [String] = []
        for artifact in artifacts {
            guard let dict = artifact as? [String: Any],
                  let apps = dict["app"] as? [Any] else { continue }
            for app in apps {
                if let name = app as? String, name.hasSuffix(".app") {
                    names.append(name)
                }
            }
        }
        return names
    }

    /// True when a cask installs via a `pkg` or `installer` artifact.
    private static func hasPackageArtifact(in artifacts: Any?) -> Bool {
        guard let artifacts = artifacts as? [Any] else { return false }
        for artifact in artifacts {
            guard let dict = artifact as? [String: Any] else { continue }
            if dict["pkg"] != nil || dict["installer"] != nil { return true }
        }
        return false
    }

    /// Extract bundle identifiers a cask declares in its `uninstall: quit:`
    /// field — the app(s) Homebrew tells to quit before removal, which is the
    /// app's own bundle id. Reliable and specific (unlike `pkgutil`/`launchctl`
    /// receipts, which also list helpers), so it's a safe fallback key.
    /// `quit` may be a single string or an array.
    private static func bundleIDs(in artifacts: Any?) -> [String] {
        guard let artifacts = artifacts as? [Any] else { return [] }
        var ids: [String] = []
        for artifact in artifacts {
            guard let dict = artifact as? [String: Any],
                  let uninstalls = dict["uninstall"] as? [Any] else { continue }
            for uninstall in uninstalls {
                guard let u = uninstall as? [String: Any] else { continue }
                if let one = u["quit"] as? String {
                    ids.append(one)
                } else if let many = u["quit"] as? [Any] {
                    ids.append(contentsOf: many.compactMap { $0 as? String })
                }
            }
        }
        return ids
    }

    enum CaskError: Error { case badStatus(Int), malformed }
}
