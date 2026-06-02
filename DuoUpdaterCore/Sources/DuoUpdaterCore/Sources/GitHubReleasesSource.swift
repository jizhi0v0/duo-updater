import Foundation

/// One app's mapping to a GitHub repository whose Releases drive its version.
public struct GitHubReleaseRule: Sendable {
    /// `CFBundleIdentifier` of the installed app.
    public let bundleID: String
    /// Repo owner, e.g. "rustdesk".
    public let owner: String
    /// Repo name, e.g. "rustdesk".
    public let repo: String
    /// When true, the latest *stable* release isn't what we want (e.g. a Preview
    /// channel publishes prereleases): fetch the releases list and take the
    /// first tag the pattern matches. When false, use `/releases/latest`.
    public let usePrereleases: Bool
    /// Regex applied to a release's `tag_name`; capture group 1 is the version
    /// (e.g. strip a leading `v`, or a `.stable_00` suffix).
    public let versionPattern: String

    public init(
        bundleID: String,
        owner: String,
        repo: String,
        usePrereleases: Bool = false,
        versionPattern: String = #"v?([0-9]+(?:\.[0-9]+)+)"#
    ) {
        self.bundleID = bundleID
        self.owner = owner
        self.repo = repo
        self.usePrereleases = usePrereleases
        self.versionPattern = versionPattern
    }

    var slug: String { "\(owner)/\(repo)" }
}

/// Resolves updates for apps distributed through GitHub Releases. Kept separate
/// from `VendorProbeSource` because GitHub is one uniform mechanism (one API,
/// shared rate limit, tag-name parsing) rather than a pile of bespoke endpoints.
///
/// Detection only — like a vendor probe, the result is flagged manual-install:
/// we surface the new version and link to the releases page; we never install a
/// GitHub artifact over a differently-sourced build.
///
/// When no rule maps to an app, returns nil (not applicable). When a rule *does*
/// exist but the fetch fails (network, rate limit, bad status), it throws — so
/// the row surfaces a retryable `.error` instead of a dead "unknown" that reads
/// the same as "no source at all". A parse miss (releases fetched, none match
/// the pattern) still returns nil.
public struct GitHubReleasesSource: UpdateSource {
    public let name = "GitHub"

    /// A GitHub fetch that failed in a way worth retrying (vs. simply not
    /// applying). 403/429 are almost always the unauthenticated 60/hour limit.
    enum GitHubError: LocalizedError {
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .badStatus(403), .badStatus(429):
                return "GitHub rate limit reached — retry shortly"
            case .badStatus(let code):
                return "GitHub returned HTTP \(code)"
            }
        }
    }

    private let rules: [String: GitHubReleaseRule]
    private let session: URLSession
    private let token: String?

    public init(
        rules: [GitHubReleaseRule] = GitHubReleaseRegistry.rules,
        token: String? = nil,
        session: URLSession = .shared
    ) {
        self.rules = Dictionary(
            rules.map { ($0.bundleID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.token = token
        self.session = session
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // Toolbox-managed apps update through Toolbox — never offer a GitHub
        // artifact over a Toolbox install (no cross-channel mixing).
        guard !app.isToolboxManaged else { return nil }
        guard let bundleID = app.bundleID, let rule = rules[bundleID] else {
            return nil  // no rule for this app — not applicable
        }
        // A rule exists: let a fetch failure throw, so the checker turns it into
        // a retryable `.error` row rather than swallowing it into a nil that's
        // indistinguishable from "no source for this app".
        return try await resolve(rule)
    }

    private func resolve(_ rule: GitHubReleaseRule) async throws -> RemoteVersion? {
        let endpoint = rule.usePrereleases
            ? "https://api.github.com/repos/\(rule.slug)/releases?per_page=20"
            : "https://api.github.com/repos/\(rule.slug)/releases/latest"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        // Authenticated requests get 5000/hour instead of 60/hour per IP.
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        Log.source.debug("GitHub GET \(endpoint, privacy: .public) (auth=\(self.token != nil, privacy: .public))")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else {
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
            Log.source.error("GitHub \(rule.slug, privacy: .public): HTTP \(http.statusCode, privacy: .public) (ratelimit-remaining=\(remaining, privacy: .public))")
            throw GitHubError.badStatus(http.statusCode)
        }

        // Walk releases in document order (GitHub returns newest first) and take
        // the first whose tag the pattern matches — for prerelease channels this
        // skips interleaved stable releases.
        let releases = Self.releases(from: data, list: rule.usePrereleases)
        for release in releases {
            if let version = VendorProbeRecipe.extractVersion(from: release.tag, pattern: rule.versionPattern) {
                let page = release.htmlURL ?? URL(string: "https://github.com/\(rule.slug)/releases")
                let body = release.body.flatMap { $0.isEmpty ? nil : $0 }
                let structured = body.flatMap {
                    GitHubMarkdownParser.parse(body: $0, version: version, date: release.publishedAt)
                }
                return RemoteVersion(
                    shortVersion: version,
                    version: nil,
                    downloadURL: URL(string: "https://github.com/\(rule.slug)/releases"),
                    sourceName: name,
                    requiresManualInstaller: true,
                    releaseNotesHTML: structured == nil ? body : nil,
                    structuredChangelog: structured,
                    changelogURL: page
                )
            }
        }
        Log.source.error("GitHub \(rule.slug, privacy: .public): \(releases.count, privacy: .public) releases fetched, none matched /\(rule.versionPattern, privacy: .public)/")
        return nil
    }

    /// A GitHub release reduced to the fields we use: tag, notes body, page URL, date.
    private struct Release {
        let tag: String
        let body: String?
        let htmlURL: URL?
        let publishedAt: String?
    }

    /// Extract releases from either a single release object or a list.
    private static func releases(from data: Data, list: Bool) -> [Release] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let objects: [[String: Any]]
        if list {
            objects = json as? [[String: Any]] ?? []
        } else {
            objects = (json as? [String: Any]).map { [$0] } ?? []
        }
        return objects.compactMap { obj in
            guard let tag = obj["tag_name"] as? String else { return nil }
            return Release(
                tag: tag,
                body: obj["body"] as? String,
                htmlURL: (obj["html_url"] as? String).flatMap { URL(string: $0) },
                publishedAt: obj["published_at"] as? String
            )
        }
    }
}

/// The verified bundleID → GitHub repo table. Every entry was confirmed against
/// the live Releases API to yield the app's current version.
public enum GitHubReleaseRegistry {
    public static let rules: [GitHubReleaseRule] = [
        // Zed Preview — the Preview channel ships as prereleases (`vX.Y.Z-pre`).
        GitHubReleaseRule(
            bundleID: "dev.zed.Zed-Preview",
            owner: "zed-industries", repo: "zed",
            usePrereleases: true,
            versionPattern: #"v([0-9]+\.[0-9]+\.[0-9]+)-pre"#),

        // Pearcleaner — tags have no `v` prefix.
        GitHubReleaseRule(
            bundleID: "com.alienator88.Pearcleaner",
            owner: "alienator88", repo: "Pearcleaner"),

        // RustDesk — tags have no `v` prefix.
        GitHubReleaseRule(
            bundleID: "com.carriez.rustdesk",
            owner: "rustdesk", repo: "rustdesk"),

        // Alcove — dedicated releases repo, no `v` prefix.
        GitHubReleaseRule(
            bundleID: "com.henrikruscon.Alcove",
            owner: "henrikruscon", repo: "alcove-releases"),

        // Macs Fan Control — tags carry a `v` prefix (stripped by the pattern).
        GitHubReleaseRule(
            bundleID: "com.crystalidea.macsfancontrol",
            owner: "crystalidea", repo: "macs-fan-control"),
    ]
}
