import CryptoKit
import Foundation

/// Metadata for a personal subscription. This type cannot produce an install route.
public enum PersonalGitHubSource {
    public struct Failure: LocalizedError, Sendable {
        public let errorDescription: String?
        public enum Disposition: Sendable {
            case retry, anonymousLimit, repositoryAccess, releasePage, blocked, reviewSource

            public var needsGitHubSettings: Bool { self == .anonymousLimit || self == .repositoryAccess }
        }
        public let disposition: Disposition
        /// The repository or release-list request received a non-rate-limit 403 or 404.
        public let confirmsRepositoryDenial: Bool
        public init(_ message: String, _ disposition: Disposition = .retry, confirmsRepositoryDenial: Bool = false) {
            self.confirmsRepositoryDenial = confirmsRepositoryDenial
            errorDescription = message
            self.disposition = disposition
        }
    }

    public struct Repository: Codable, Sendable, Equatable {
        public struct Owner: Codable, Sendable, Equatable { public let id: Int64 }
        public let id: Int64
        public let full_name: String
        public let owner: Owner
    }

    public struct Asset: Codable, Identifiable, Sendable, Equatable {
        public let id: Int64
        public let name: String
        public let size: Int64
        public let digest: String?
        public let updated_at: String

        public func matches(filename literal: String?) -> Bool {
            guard let literal, !literal.isEmpty else { return true }
            return name.range(of: literal, options: [.caseInsensitive, .literal]) != nil
        }

        public var matchesMac: Bool {
            let file = name.lowercased()
            guard [".zip", ".pkg", ".dmg"].contains(where: file.hasSuffix) else { return false }
            let tokens = Set(file.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let otherPlatforms: Set<String> = ["linux", "ubuntu", "debian", "windows", "win", "win32", "win64", "android", "ios", "symbols", "dsym"]
            guard tokens.isDisjoint(with: otherPlatforms) else { return false }
            if !tokens.isDisjoint(with: ["universal", "universal2", "arm64", "aarch64"]) { return true }
            return tokens.isDisjoint(with: ["x86", "x64", "amd64", "intel", "i386", "armv7"])
        }

        public var supportsLocalCheck: Bool {
            matchesMac && name.lowercased().hasSuffix(".zip") && (1...268_435_456).contains(size)
                && digest?.lowercased().wholeMatch(of: /sha256:[0-9a-f]{64}/) != nil
        }

    }

    public struct Release: Codable, Identifiable, Sendable, Equatable {
        public let id: Int64
        public let tag_name: String
        public let prerelease: Bool
        public let draft: Bool
        public let body: String?
        public let assets: [Asset]
        public var published_at: String? = nil

        public enum TagIssue { case unrecognized, previewFlagOnStableTag, stableFlagOnPreviewTag }

        public var tagIssue: TagIssue? {
            guard let version = Version(tag_name) else { return .unrecognized }
            if version.stage == 4 && prerelease { return .previewFlagOnStableTag }
            if version.stage != 4 && !prerelease { return .stableFlagOnPreviewTag }
            return nil
        }
    }

    public enum Track: String, Codable, CaseIterable, Sendable { case stable = "Stable", preview = "Preview", nightly = "Nightly" }

    public struct Version: Comparable, Sendable {
        public let base: String
        let stage: Int
        let ordinal: String

        public init?(_ raw: String) {
            let text = raw.lowercased()
            guard let match = text.wholeMatch(of: /^v?([0-9]+(?:\.[0-9]+){0,3})(?:[-.]?(nightly|alpha|beta|rc)[.-]?([0-9]+))?$/) else { return nil }
            base = String(match.1)
            stage = ["nightly", "alpha", "beta", "rc"].firstIndex(of: String(match.2 ?? "")) ?? 4
            ordinal = String(match.3 ?? "0")
        }

        public static func == (a: Self, b: Self) -> Bool {
            VersionComparator.compare(a.base, b.base) == .orderedSame && a.stage == b.stage &&
            VersionComparator.compare(a.ordinal, b.ordinal) == .orderedSame
        }

        public static func < (a: Self, b: Self) -> Bool {
            let base = VersionComparator.compare(a.base, b.base)
            if base != .orderedSame { return base == .orderedAscending }
            if a.stage != b.stage { return a.stage < b.stage }
            return VersionComparator.compare(a.ordinal, b.ordinal) == .orderedAscending
        }
    }

    public struct Snapshot: Sendable {
        public let repository: Repository
        private let fetchedReleases: [Release]
        public let restrictedCredentialGeneration: Int?
        private let rejectionRevision: Int
        public var isAccessibleWithCurrentCredentials: Bool {
            guard let generation = restrictedCredentialGeneration else { return true }
            return GitHubCredentials.current.mayReadRestrictedSource(generation: generation, revision: rejectionRevision)
        }
        public var releases: [Release] { isAccessibleWithCurrentCredentials ? fetchedReleases : [] }
        public let checked: Date
        public let truncated: Bool

        init(repository: Repository, releases: [Release], checked: Date, truncated: Bool,
             restrictedCredentialGeneration: Int? = nil, rejectionRevision: Int = GitHubCredentials.current.restrictedSourceRevision) {
            self.repository = repository
            self.fetchedReleases = releases.filter { !$0.draft }
            self.checked = checked
            self.truncated = truncated
            self.restrictedCredentialGeneration = restrictedCredentialGeneration
            self.rejectionRevision = rejectionRevision
        }

        public func changelog(track: Track, installed: String?, includeStable: Bool) -> Changelog {
            let selected = matches(track: track, installed: installed, includeStable: includeStable)
            return Changelog(entries: selected.map { release in
                let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
                let markdown = body.flatMap { $0.isEmpty ? nil : $0 }
                return Changelog.Entry(
                    version: release.tag_name, date: release.published_at,
                    items: markdown.map { [$0] } ?? [], markdown: markdown)
            })
        }

        public func matches(track: Track, installed: String?, includeStable: Bool) -> [Release] {
            let local = installed.flatMap(Version.init)
            let candidates = releases.compactMap { release -> (release: Release, version: Version)? in
                guard !release.draft, let version = Version(release.tag_name) else { return nil }
                if version.stage == 4 {
                    guard !release.prerelease else { return nil }
                    if track != .stable {
                        guard includeStable, let local, local.stage != 4,
                              VersionComparator.compare(local.base, version.base) == .orderedSame else { return nil }
                    }
                } else if track != (version.stage == 0 ? .nightly : .preview) {
                    return nil
                }
                return (release, version)
            }
            return candidates.sorted { $0.version > $1.version }.map(\.release)
        }
    }

    public static func slug(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("://") {
            guard let url = URLComponents(string: value), url.scheme?.lowercased() == "https",
                  ["github.com", "www.github.com"].contains(url.host?.lowercased()),
                  url.user == nil, url.password == nil, url.port == nil else { return nil }
            // A pasted release page identifies the repository. Its path, query and
            // fragment never become an API request.
            let path = url.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard path.count >= 3, path[0].isEmpty, !path.contains(".."), !path.contains(".") else { return nil }
            value = String(path[1]) + "/" + String(path[2])
        }
        if value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        guard value.wholeMatch(of: /[A-Za-z0-9-]{1,39}\/[A-Za-z0-9_.-]{1,100}/) != nil,
              !value.contains(".."), !value.hasSuffix("/.") else { return nil }
        return value
    }

    public static func page(repository: Repository, release: Release?) -> URL? {
        guard let slug = slug(repository.full_name) else { return nil }
        var page = URLComponents()
        page.scheme = "https"
        page.host = "github.com"
        page.path = "/\(slug)/releases"
        if let release, !release.tag_name.isEmpty, ![".", ".."].contains(release.tag_name) {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-_.~")
            if let tag = release.tag_name.addingPercentEncoding(withAllowedCharacters: allowed) {
                page.percentEncodedPath += "/tag/" + tag
            }
        }
        return page.url
    }
}

/// Isolated cookies, cache and redirects; credentials follow the app’s GitHub settings. Repository renames
/// may redirect API metadata to /repositories/<id>; only that exact route is followed.
public actor PersonalGitHubClient {
    public static let shared = PersonalGitHubClient(resolveToken: { await ChangelogService.gitHubToken() })
    private typealias Source = PersonalGitHubSource
    private final class Redirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private let metadataSession: URLSession
    private let assetSession: URLSession
    private let resolveToken: @Sendable () async -> String?
    private enum Access: Hashable { case anonymous, authenticated(Int) }
    private struct Lookup: Hashable { let slug: String; let access: Access }
    private struct LookupInProgress {
        let task: Task<PersonalGitHubSource.Snapshot, Error>
        var callers: Set<UUID>
    }
    private var pending: [Lookup: LookupInProgress] = [:]

    init(configuration config: URLSessionConfiguration = .ephemeral, resolveToken: @escaping @Sendable () async -> String? = { nil }) {
        self.resolveToken = resolveToken
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 2
        metadataSession = URLSession(configuration: config, delegate: Redirects(), delegateQueue: nil)
        config.timeoutIntervalForResource = 3600
        assetSession = URLSession(configuration: config, delegate: Redirects(), delegateQueue: nil)
    }

    public func fetch(_ input: String) async throws -> PersonalGitHubSource.Snapshot {
        guard let slug = Source.slug(input)?.lowercased() else { throw Source.Failure("Enter owner/repo or an HTTPS GitHub repository URL.") }
        let generation = GitHubCredentials.current.generation
        let token = await resolveToken()
        guard GitHubCredentials.current.generation == generation else { return try await fetch(input) }
        let key = Lookup(slug: slug, access: token != nil && !GitHubCredentials.current.isRejected ? .authenticated(generation) : .anonymous)
        try Task.checkCancellation()
        let caller = UUID()
        let task: Task<PersonalGitHubSource.Snapshot, Error>
        if let existing = pending[key] {
            task = existing.task
            pending[key]?.callers.insert(caller)
        } else {
            guard pending.count < 2 else { throw Source.Failure("Other GitHub sources are being checked. Try again shortly.") }
            task = Task(priority: .utility) { try await load(slug, token: token, generation: generation) }
            pending[key] = LookupInProgress(task: task, callers: [caller])
        }
        defer { finishLookup(key, caller: caller) }
        return try await withTaskCancellationHandler {
            let snapshot = try await task.value
            try Task.checkCancellation()
            try checkCredentialGeneration(generation)
            guard snapshot.isAccessibleWithCurrentCredentials else {
                throw Source.Failure("GitHub credentials changed. Validate the repository again.", .repositoryAccess)
            }
            return snapshot
        } onCancel: {
            Task { await self.finishLookup(key, caller: caller) }
        }
    }

    private func finishLookup(_ key: Lookup, caller: UUID) {
        guard pending[key]?.callers.remove(caller) != nil, pending[key]?.callers.isEmpty == true else { return }
        pending.removeValue(forKey: key)?.task.cancel()
    }

    private func load(_ slug: String, token: String?, generation: Int) async throws -> Source.Snapshot {
        let root = "https://api.github.com"
        let revision = GitHubCredentials.current.restrictedSourceRevision
        let data = try await request(URL(string: root + "/repos/" + slug)!, metadataRedirect: true, token: token, generation: generation)
        // GitHub authorizes the repository and its release list separately.
        struct Visibility: Decodable { let visibility: String?; let `private`: Bool? }
        let access = try? JSONDecoder().decode(Visibility.self, from: data)
        let isPublic = access?.visibility == "public" && access?.private == false
        if !isPublic {
            guard token != nil, GitHubCredentials.current.mayReadRestrictedSource(generation: generation, revision: revision) else {
                throw Source.Failure("GitHub credentials are required for this repository.", .repositoryAccess)
            }
        }
        let repo = try JSONDecoder().decode(Source.Repository.self, from: data)
        guard repo.id > 0, repo.owner.id > 0, Source.slug(repo.full_name) == repo.full_name else { throw Source.Failure("Invalid GitHub repository identity.") }
        var releases: [Source.Release] = []
        for page in 1...2 {
            let endpoint = URL(string: root + "/repositories/\(repo.id)/releases?per_page=30&page=\(page)")!
            let data = try await request(endpoint, metadataRedirect: false, token: token, generation: generation)
            let slice = try JSONDecoder().decode([Source.Release].self, from: data)
            releases += slice
            if slice.count < 30 { break }
        }
        return .init(repository: repo, releases: releases, checked: Date(), truncated: releases.count == 60,
                     restrictedCredentialGeneration: isPublic ? nil : generation, rejectionRevision: revision)
    }

    private func checkCredentialGeneration(_ generation: Int) throws {
        guard generation == GitHubCredentials.current.generation else { throw Source.Failure("GitHub credentials changed. Try again.") }
    }

    private func responseBytes(_ request: URLRequest, session: URLSession, purpose: RequestPurpose, token: String?, generation: Int) async throws -> (URLSession.CountedBytes, URLResponse) {
        try checkCredentialGeneration(generation)
        guard let url = request.url, ChangelogService.isGitHubAPI(url) else { return try await session.countedBytes(for: request, purpose: purpose) }
        var outbound = request
        if let token, !GitHubCredentials.current.isRejected(generation: generation) {
            outbound.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        let result: (URLSession.CountedBytes, URLResponse)
        do {
            result = try await session.countedBytes(for: outbound, purpose: purpose, classifyGitHubErrors: true)
        } catch let refusal as GitHubRateLimitGate.Refused {
            let anonymous = refusal.credential == .anonymous
            let message = anonymous ? "Anonymous GitHub rate limit reached." : "GitHub account rate limit reached."
            throw Source.Failure(message + " Try again after " + refusal.closure.until.formatted() + ".", anonymous ? .anonymousLimit : .retry)
        }
        if GitHubCredentials.isRejection(of: outbound, result.1) {
            GitHubCredentials.current.recordRejection(generation: generation)
            return try await responseBytes(request, session: session, purpose: purpose, token: nil, generation: generation)
        }
        return result
    }

    private func request(_ url: URL, metadataRedirect: Bool, token: String?, generation: Int) async throws -> Data {
        let (bytes, response) = try await responseBytes(URLRequest(url: url, cachePolicy: URLRequest.versionFeedCachePolicy), session: metadataSession, purpose: .versionCheck, token: token, generation: generation)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if metadataRedirect, [301, 302, 307, 308].contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location"),
           location.wholeMatch(of: /https:\/\/api\.github\.com\/repositories\/[0-9]+/) != nil,
           let target = URL(string: location) {
            return try await request(target, metadataRedirect: false, token: token, generation: generation)
        }
        if [401, 403, 404].contains(http.statusCode) {
            throw Source.Failure("GitHub couldn’t read the repository or its releases. Check the repository URL and your GitHub credentials.",
                                 .repositoryAccess, confirmsRepositoryDenial: http.statusCode == 403 || http.statusCode == 404)
        }
        guard http.statusCode == 200 else { throw Source.Failure("GitHub returned HTTP \(http.statusCode). Try again later.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 4 * 1024 * 1024 else { throw Source.Failure("GitHub release metadata exceeded the size limit.") }
            data.append(byte)
        }
        return data
    }
}

extension PersonalGitHubClient {
    /// Caller owns this private staging directory and removes it on failure.
    public func downloadZIP(repository: PersonalGitHubSource.Repository, asset: PersonalGitHubSource.Asset,
                            into directory: URL) async throws -> URL {
        guard asset.id > 0, repository.id > 0, asset.supportsLocalCheck, let digest = asset.digest?.lowercased() else { throw Source.Failure("A size-bounded ZIP with a published SHA-256 digest is required.", .releasePage) }
        var url = URL(string: "https://api.github.com/repositories/\(repository.id)/releases/assets/\(asset.id)")!
        let generation = GitHubCredentials.current.generation
        let token = await resolveToken()
        for _ in 0..<4 {
            var request = URLRequest(url: url)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await responseBytes(request, session: assetSession, purpose: .install, token: token, generation: generation)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                guard let raw = http.value(forHTTPHeaderField: "Location"), let next = URL(string: raw),
                      next.scheme == "https", next.user == nil, next.password == nil, next.port == nil,
                      ["release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(next.host?.lowercased()) else { throw Source.Failure("GitHub redirected the asset to an unapproved destination.") }
                url = next
                continue
            }
            guard http.statusCode == 200 else { throw Source.Failure("Asset download returned HTTP \(http.statusCode).") }
            let archive = directory.appendingPathComponent("download.zip")
            guard FileManager.default.createFile(atPath: archive.path, contents: nil) else { throw URLError(.cannotCreateFile) }
            let file = try FileHandle(forWritingTo: archive)
            defer { try? file.close() }
            var hash = SHA256()
            var buffer = Data()
            var count: Int64 = 0
            for try await byte in bytes {
                count += 1
                guard count <= asset.size else { throw Source.Failure("Asset exceeds its published size.", .blocked) }
                buffer.append(byte)
                if buffer.count == 65536 {
                    hash.update(data: buffer)
                    try file.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            hash.update(data: buffer)
            try file.write(contentsOf: buffer)
            guard count == asset.size, "sha256:" + hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest else { throw Source.Failure("Blocked — the downloaded bytes do not match GitHub’s SHA-256 digest.", .blocked) }
            try checkCredentialGeneration(generation)
            let root = directory.appendingPathComponent("package")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let app = try await offCooperativePool { try PersonalSourceZIP.unpack(archive, into: root) }
            let quarantine = "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));DuoUpdater;\(UUID().uuidString)"
            guard setxattr(app.path, "com.apple.quarantine", quarantine, quarantine.utf8.count, 0, 0) == 0 else { throw Source.Failure("Cannot quarantine the downloaded application.", .blocked) }
            try FileManager.default.removeItem(at: archive)
            return app
        }
        throw Source.Failure("Too many asset download redirects.")
    }
}
