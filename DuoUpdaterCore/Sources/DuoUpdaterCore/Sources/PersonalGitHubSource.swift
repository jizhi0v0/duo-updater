import CryptoKit
import Foundation

/// Metadata for a personal subscription. This type cannot produce an install route.
public enum PersonalGitHubSource {
    public struct Failure: LocalizedError, Sendable {
        public let errorDescription: String?
        public enum Disposition: Sendable { case retry, releasePage, blocked, reviewSource }
        public let disposition: Disposition
        public init(_ message: String, _ disposition: Disposition = .retry) {
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
        public let releases: [Release]
        public let checked: Date
        public let truncated: Bool

        public func matches(track: Track, installed: String?, includeStable: Bool) -> [Release] {
            let local = installed.flatMap(Version.init)
            let candidates = releases.compactMap { release -> (release: Release, version: Version)? in
                guard !release.draft, let version = Version(release.tag_name) else { return nil }
                if version.stage == 4 {
                    guard !release.prerelease, track == .stable || (includeStable && local?.stage != 4 && local?.base == version.base) else { return nil }
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

/// No shared credentials, cookies, cache, or automatic redirects. Repository renames
/// may redirect API metadata to /repositories/<id>; only that exact route is followed.
public actor PersonalGitHubClient {
    public static let shared = PersonalGitHubClient()
    private typealias Source = PersonalGitHubSource
    private final class Redirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private let session: URLSession
    private var rateLimitReset: Date?
    private var pending: [String: Task<PersonalGitHubSource.Snapshot, Error>] = [:]

    init(configuration config: URLSessionConfiguration = .ephemeral) {
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: config, delegate: Redirects(), delegateQueue: nil)
    }

    public func fetch(_ input: String) async throws -> PersonalGitHubSource.Snapshot {
        guard let slug = Source.slug(input)?.lowercased() else { throw Source.Failure("Enter owner/repo or an HTTPS GitHub repository URL.") }
        if let rateLimitReset, rateLimitReset > Date() {
            throw Source.Failure("Anonymous GitHub rate limit reached. Try again after " + rateLimitReset.formatted() + ".")
        }
        if let task = pending[slug] { return try await task.value }
        guard pending.count < 2 else { throw Source.Failure("Other GitHub sources are being checked. Try again shortly.") }
        let task = Task(priority: .utility) { try await load(slug) }
        pending[slug] = task
        defer { pending[slug] = nil }
        return try await task.value
    }

    private func load(_ slug: String) async throws -> Source.Snapshot {
        let root = "https://api.github.com"
        let data = try await request(URL(string: root + "/repos/" + slug)!, metadataRedirect: true)
        let repo = try JSONDecoder().decode(Source.Repository.self, from: data)
        guard repo.id > 0, repo.owner.id > 0, Source.slug(repo.full_name) == repo.full_name else { throw Source.Failure("Invalid GitHub repository identity.") }
        var releases: [Source.Release] = []
        for page in 1...2 {
            let endpoint = URL(string: root + "/repositories/\(repo.id)/releases?per_page=30&page=\(page)")!
            let data = try await request(endpoint, metadataRedirect: false)
            let slice = try JSONDecoder().decode([Source.Release].self, from: data)
            releases += slice
            if slice.count < 30 { break }
        }
        return .init(repository: repo, releases: releases.filter { !$0.draft }, checked: Date(), truncated: releases.count == 60)
    }

    private func request(_ url: URL, metadataRedirect: Bool) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if metadataRedirect, [301, 302, 307, 308].contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location"),
           location.wholeMatch(of: /https:\/\/api\.github\.com\/repositories\/[0-9]+/) != nil,
           let target = URL(string: location) {
            return try await request(target, metadataRedirect: false)
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { fields, field in
            if let key = field.key as? String { fields[key] = String(describing: field.value) }
        }
        if let closure = GitHubRateLimitGate.closure(status: http.statusCode, headers: headers, body: nil, strikesBefore: 0, now: Date()) {
            rateLimitReset = closure.until
            if http.statusCode != 200 {
                throw Source.Failure("Anonymous GitHub rate limit reached. Try again after " + closure.until.formatted() + ".")
            }
        }
        guard http.statusCode == 200 else { throw Source.Failure("GitHub returned HTTP \(http.statusCode). Check the public repository or retry later.") }
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
        for _ in 0..<4 {
            var request = URLRequest(url: url)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
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
