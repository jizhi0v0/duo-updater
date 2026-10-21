import Foundation

/// What Biome's installer would install, the digest each build was published
/// with, and Biome's release notes.
///
/// **Latest.** The installer asks `biomejs.dev/api/versions/latest.txt` (plain
/// text, `2.6.2` on 2026-10-21, revalidating by ETag) and installs that, so the
/// same answer is the channel. It is not GitHub's `releases/latest`: the
/// repository also publishes `@biomejs/js-api@…` (and, before 2.0,
/// `cli/v…-nightly…` and `js-api/v…`) in the same list, and its prereleases
/// (`@biomejs/biome@2.0.0-beta.6`) as well. Only a tag `@biomejs/biome@X.Y.Z`
/// is the CLI, and only one not marked prerelease is offered.
///
/// **Published digest.** Biome publishes no checksum file. Its releases carry
/// GitHub's own `digest` for each asset (`sha256:<hex>`; 66 of the 67 stable CLI
/// releases in the newest 100 have one on both darwin binaries, all but
/// 2.0.1), and the asset is the raw binary, so the digest is the binary's
/// sha256: `be66b76d…` for 2.6.2's `biome-darwin-arm64` matched the download on
/// 2026-10-21. **The user accepted that `digest` as Biome's published hash on
/// 2026-10-21**, as zoxide's was (`ZoxideRelease`): Biome's decision alone, not
/// a rule for any other tool.
///
/// **Notes.** Each CLI release body is changesets markdown: `## <version>`, then
/// `### Major Changes` / `### Minor Changes` / `### Patch Changes`, a `-` bullet
/// per change (its pull request, commit and author first). Then, in 63 of the
/// newest 67 CLI releases, GitHub's generated `## What's Changed` — every merged
/// pull request, chores and refactors included, the same changes again at
/// commit level (2.5.15: 191 items with it, 60 without) — and
/// `## New Contributors`. The changesets are the changelog: `What's Changed` is
/// skipped by name, the contributors and the full-changelog link by the
/// parser's own keywords. A release with one changesets section (most patch
/// releases) then shows its items without that heading, the parser's rule for
/// a body with a single category heading. A body runs to 116 KB (2.6.2), so a
/// page of 30 releases is ~1.3 MB.
public struct BiomeRelease: Sendable {

    public static let repository = "biomejs/biome"
    /// What the installer reads.
    public static let latestURL = URL(string: "https://biomejs.dev/api/versions/latest.txt")!
    /// Every release's digests, to name the build a file is (`learnPublished`).
    /// 100 reach back to 2.0.0-beta (March 2025): ~3.3 MB, asked at most once
    /// per new Biome release.
    public static let publishedURL = URL(string: "https://api.github.com/repos/biomejs/biome/releases?per_page=100")!
    /// The notes: one release a week or so, so 30 reach back about seven months.
    public static let notesURL = URL(string: "https://api.github.com/repos/biomejs/biome/releases?per_page=30")!

    static let tagPrefix = "@biomejs/biome@"

    /// `@biomejs/biome@2.6.2`, its `@` and `/` escaped for the path.
    static func tagURL(version: String) -> URL {
        URL(string: "https://api.github.com/repos/biomejs/biome/releases/tags/%40biomejs%2Fbiome%40\(version)")!
    }

    static func assetName(target: String) -> String { "biome-\(target)" }

    static func assetURL(version: String, target: String) -> URL {
        URL(string: "https://github.com/biomejs/biome/releases/download/@biomejs/biome@\(version)/\(assetName(target: target))")!
    }

    static let targets: Set<String> = ["darwin-arm64", "darwin-x64"]

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        /// GitHub's API rate limit (`GitHubReleasesSource.isRateLimited`).
        case rateLimited(Int)
        case unreadable
        /// `latest.txt` named something that is not a stable `X.Y.Z`.
        case notStable(String)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .rateLimited(let status):
                return GitHubReleasesSource.GitHubError.rateLimited(status).errorDescription ?? "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .notStable(let named): return "it names \(named), not a stable release"
            }
        }
    }

    /// One CLI release: its version and the `digest` GitHub reports for each
    /// macOS binary that has one, by target.
    public struct Published: Sendable, Equatable {
        public let version: String
        public let binaryDigests: [String: String]
    }

    /// The body, the status and the answer's `X-RateLimit-Remaining`.
    typealias Fetch = @Sendable (URL, Bool) async throws -> (Data, Int, String?)

    let fetch: Fetch
    let digests: BiomePublishedDigests

    public init(session: URLSession = .updates) {
        self.init(digests: .shared, fetch: { url, force in
            var request = URLRequest(url: url)
            request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
            request.timeoutInterval = url == BiomeRelease.publishedURL ? 30 : 15
            if ChangelogService.isGitHubAPI(url) {
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                if let token = await ChangelogService.gitHubToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            }
            let purpose: RequestPurpose = url == BiomeRelease.notesURL ? .changelog : .versionCheck
            let (data, response) = try await session.countedData(for: request, purpose: purpose)
            let http = response as? HTTPURLResponse
            return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(digests: BiomePublishedDigests, fetch: @escaping Fetch) {
        self.digests = digests
        self.fetch = fetch
    }

    /// What `latest.txt` names, as the installer reads it.
    public func latestVersion() async throws -> String {
        let (data, status, _) = try await fetch(Self.latestURL, false)
        guard status == 200 else { throw Failure.http(status) }
        let text = String(decoding: data.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, data.count <= 64 else { throw Failure.unreadable }
        guard Self.isVersion(text) else { throw Failure.notStable(String(text.prefix(32))) }
        return text
    }

    /// The published sha256 of `version`'s binary for `target`: remembered, else
    /// read from its release (and remembered). Nil when the release names none.
    func digest(version: String, target: String) async throws -> String? {
        guard Self.isVersion(version), Self.targets.contains(target) else { return nil }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return known
        }
        let data = try await api(Self.tagURL(version: version))
        guard let published = Self.parseRelease(data), published.version == version else { throw Failure.unreadable }
        await offCooperativePool { digests.remember([published]) }
        return published.binaryDigests[target]
    }

    /// Reads every CLI release's digests from the newest 100 into the store —
    /// once per `latest`: a store that already read them while `latest` was
    /// newest has nothing more to learn there, so a file that matched none
    /// (a local build) does not cost 3 MB on every check.
    func learnPublished(through latest: String) async throws {
        let digests = self.digests
        if await offCooperativePool({ digests.listedThrough() }) == latest { return }
        let data = try await api(Self.publishedURL)
        guard let releases = Self.parseReleases(data) else { throw Failure.unreadable }
        await offCooperativePool { digests.remember(releases, listedThrough: latest) }
    }

    private func api(_ url: URL) async throws -> Data {
        let (data, status, remaining) = try await fetch(url, false)
        guard status == 200 else {
            throw GitHubReleasesSource.isRateLimited(status, rateLimitRemaining: remaining)
                ? Failure.rateLimited(status) : Failure.http(status)
        }
        return data
    }

    /// One release of the API: the CLI's, stable, with a valid version.
    static func parseRelease(_ data: Data) -> Published? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return published(json)
    }

    /// A page of the list: its CLI releases, every other package's dropped.
    static func parseReleases(_ data: Data) -> [Published]? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return list.compactMap(published)
    }

    private static func published(_ json: [String: Any]) -> Published? {
        guard let tag = json["tag_name"] as? String, tag.hasPrefix(tagPrefix),
              json["prerelease"] as? Bool != true, json["draft"] as? Bool != true
        else { return nil }
        let version = String(tag.dropFirst(tagPrefix.count))
        guard isVersion(version) else { return nil }
        var digests: [String: String] = [:]
        for asset in (json["assets"] as? [[String: Any]]) ?? [] {
            guard let name = asset["name"] as? String,
                  let digest = GitHubReleasesSource.sha256Digest(asset["digest"])
            else { continue }
            for target in targets where name == assetName(target: target) {
                digests[target] = digest
            }
        }
        return Published(version: version, binaryDigests: digests)
    }

    /// `2.6.2`: three numbers, nothing else — what a stable CLI release is, and
    /// what keeps a version safe in a URL path and on the installer's command line.
    static func isVersion(_ s: String) -> Bool {
        s.count <= 20 && s.range(of: #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#, options: .regularExpression) != nil
    }

    /// The newest page of releases, one entry per CLI release with notes, newest first.
    public func notes(force: Bool) async throws -> Changelog {
        let (data, status, remaining) = try await fetch(Self.notesURL, force)
        guard status == 200 else {
            throw CLIToolReleaseNotesError.status(status, rateLimitRemaining: remaining, url: Self.notesURL)
        }
        let parsed = await offCooperativePool { Self.parseNotes(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }

    /// GitHub's generated pull request list, after the changesets.
    static let skipSections = ["What's Changed", "What’s Changed"]

    /// Through `GitHubMarkdownParser`, as every GitHub Releases changelog is,
    /// with only the CLI's tags (`tagPattern`) and, as always there, only the
    /// releases not marked prerelease.
    static func parseNotes(_ json: String) -> Changelog? {
        StructuredChangelogDecoder.decode(
            json, format: .gitHubReleases, channel: nil, maxEntries: nil, skipSections: skipSections,
            tagPattern: #"^@biomejs/biome@(\d+\.\d+\.\d+)$"#)
    }
}

/// The published sha256 of each Biome build, by version and target, as GitHub's
/// `digest` names it (`BiomeRelease`) — looked up both ways: a version's digest
/// for the check after an update, and a file's version from its hash for the
/// scan. Also each scanned file's hash, by path and `stat` identity, so a ~74 MB
/// file is hashed again only once it changed.
/// In `com.duoupdater.app/biome-published-digests.json`.
public final class BiomePublishedDigests: @unchecked Sendable {

    public static let shared = BiomePublishedDigests()

    struct Hashed: Codable, Equatable {
        let identity: UvVerifiedFiles.FileIdentity
        let sha256: String
    }

    struct Store: Codable {
        /// `"<version> <target>"` → sha256.
        var digests: [String: String] = [:]
        /// The `latest` the whole list was last read under (`learnPublished`).
        var listedThrough: String?
        /// A file's path → its hash as of its identity.
        var hashed: [String: Hashed] = [:]
    }

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? DuoStateDirectory.testProcessScratchRoot
                .appendingPathComponent("duo-biome-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("biome-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("biome-published-digests.json"))
    }

    static func key(version: String, target: String) -> String { "\(version) \(target)" }

    /// Blocking.
    func digest(version: String, target: String) -> String? {
        lock.withLock { load().digests[Self.key(version: version, target: target)] }
    }

    /// The version whose published `target` build has this sha256; nil when none
    /// or, never seen, more than one. Blocking.
    func version(sha256: String, target: String) -> String? {
        let sha256 = sha256.lowercased()
        let suffix = " \(target)"
        let matches = lock.withLock { load().digests }
            .filter { $0.key.hasSuffix(suffix) && CLIToolTrust.matches(sha256, published: $0.value) }
            .map { String($0.key.dropLast(suffix.count)) }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Blocking.
    func listedThrough() -> String? {
        lock.withLock { load().listedThrough }
    }

    /// Blocking.
    func remember(_ releases: [BiomeRelease.Published], listedThrough: String? = nil) {
        update { store in
            for release in releases {
                for (target, digest) in release.binaryDigests {
                    store.digests[Self.key(version: release.version, target: target)] = digest
                }
            }
            if let listedThrough { store.listedThrough = listedThrough }
        }
    }

    /// The file's sha256, from the remembered one while its identity holds, else
    /// `hash` (and remembered). Blocking.
    func sha256(of path: String, hash: (URL) -> String?) -> String? {
        let identity = UvVerifiedFiles.fileIdentity(path)
        if let identity, let known = lock.withLock({ load().hashed[path] }), known.identity == identity {
            return known.sha256
        }
        guard let sha256 = hash(URL(fileURLWithPath: path)) else { return nil }
        // Remembered only when the file did not change while it was read.
        if let identity, UvVerifiedFiles.fileIdentity(path) == identity {
            update { $0.hashed[path] = Hashed(identity: identity, sha256: sha256) }
        }
        return sha256
    }

    private func update(_ change: (inout Store) -> Void) {
        lock.withLock {
            var store = load()
            change(&store)
            guard let data = try? JSONEncoder().encode(store) else { return }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Under the lock.
    private func load() -> Store {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(Store.self, from: data)
        else { return Store() }
        return store
    }
}
