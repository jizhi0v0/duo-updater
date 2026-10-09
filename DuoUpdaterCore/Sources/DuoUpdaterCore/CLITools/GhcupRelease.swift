import Foundation

/// What `ghcup upgrade` would install: the GHCup version ghcup's own metadata
/// tags `Latest`.
///
/// `ghcup upgrade` (`GHCup.OptParse.Upgrade`, v0.2.6.2) reads the metadata at
/// `ghcupURL` — `raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-0.1.0.yaml`
/// (`GHCup.Hardcoded.URLs`) — takes the highest `GHCup` version tagged `Latest`
/// (`getLatest`) and does nothing unless it is newer than its own. The release
/// channels a user can add (`prereleases`, `cross`, `3rdparty`) carry no `GHCup`
/// entry (fetched 2026-10-09), so they do not move it.
///
/// That file is what is read here, not the GitHub releases of `haskell/ghcup-hs`:
/// it is the decision `ghcup upgrade` makes, and it costs no GitHub API call. It
/// is 669,473 bytes with `cache-control: max-age=300` and an `ETag` (2026-10-09),
/// so the version-feed cache policy revalidates it to a 304. raw.githubusercontent
/// can answer 429 to a shared exit address; that reads as the channel being
/// unreadable, and `ghcup upgrade` would hit the same.
///
/// No YAML library: the `GHCup` tool's `toolVersions` are read by indentation
/// (`latest(inMetadata:)`), which copes with the two shapes `viTags` takes in
/// the file — `- Latest` at the key's own indent (104 times) or two deeper (once),
/// and `viTags: []`.
public struct GhcupRelease: Sendable {

    public static let metadata =
        URL(string: "https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-0.1.0.yaml")!

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            }
        }
    }

    typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url in
            var request = URLRequest(url: url)
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 30
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public func latest() async throws -> String {
        let (data, status) = try await fetch(Self.metadata)
        guard status == 200 else { throw Failure.http(status) }
        guard let version = await offCooperativePool({ Self.latest(inMetadata: String(decoding: data, as: UTF8.self)) })
        else { throw Failure.unreadable }
        return version
    }

    /// The highest version under `GHCup:` → `toolVersions:` whose `viTags`
    /// include `Latest`, as `getLatest` picks it.
    static func latest(inMetadata yaml: String) -> String? {
        let lines = yaml.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        func indent(_ line: String) -> Int { line.prefix(while: { $0 == " " }).count }
        func isContent(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }
        // The tool: `GHCup:` and the lines indented under it.
        guard let toolLine = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "GHCup:" })
        else { return nil }
        let toolIndent = indent(lines[toolLine])
        var tool: [String] = []
        for line in lines[(toolLine + 1)...] {
            if isContent(line), indent(line) <= toolIndent { break }
            tool.append(line)
        }
        guard let versionsLine = tool.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "toolVersions:" })
        else { return nil }
        let versionsIndent = indent(tool[versionsLine])
        var latest: [String] = []
        var version: (name: String, indent: Int)?
        var tags: (indent: Int, open: Bool)?
        for line in tool[(versionsLine + 1)...] where isContent(line) {
            let level = indent(line)
            if level <= versionsIndent { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if version == nil || level <= version!.indent {
                // A version key: `0.2.6.2:` (or quoted).
                tags = nil
                var key = trimmed
                guard key.hasSuffix(":") else { version = nil; continue }
                key.removeLast()
                key = key.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                version = (key, level)
                continue
            }
            if let open = tags, open.open {
                // A `- Tag` item belongs to the list at the key's indent or deeper.
                if trimmed.hasPrefix("- "), level >= open.indent {
                    if trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces) == "Latest", let version {
                        latest.append(version.name)
                    }
                    continue
                }
                tags = nil
            }
            if trimmed.hasPrefix("viTags:") {
                let rest = trimmed.dropFirst("viTags:".count).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("[") {
                    let items = rest.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    if items.contains("Latest"), let version { latest.append(version.name) }
                } else if rest.isEmpty {
                    tags = (level, true)
                }
            }
        }
        return latest.filter(isVersion).max { VersionComparator.compare($0, $1) == .orderedAscending }
    }

    /// `0.2.6.2`: two to five dot-separated runs of digits, as every GHCup
    /// release has been. Also what keeps a version safe in a URL path.
    static func isVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return (2...5).contains(parts.count) && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 6 && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    static let downloads = URL(string: "https://downloads.haskell.org/~ghcup")!

    /// `SHA256SUMS` of a release: one `<hex>  ./<file>` line per asset.
    static func sumsURL(version: String) -> URL {
        downloads.appendingPathComponent(version).appendingPathComponent("SHA256SUMS")
    }

    /// The release's binary for `target`, as `SHA256SUMS` names it.
    static func assetName(version: String, target: String) -> String { "\(target)-ghcup-\(version)" }

    static let targets: Set<String> = ["aarch64-apple-darwin", "x86_64-apple-darwin"]

    /// The digest `SHA256SUMS` gives for exactly `./<asset>` — not its `.sig`, not
    /// the `test-` builds beside it.
    static func digest(inSums text: String, asset: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { continue }
            var name = fields[1]
            if name.hasPrefix("*") { name = name.dropFirst() }
            if name.hasPrefix("./") { name = name.dropFirst(2) }
            guard name == asset else { continue }
            return CLIToolTrust.firstDigest(in: String(fields[0]))
        }
        return nil
    }
}

/// Whether a `ghcup` is byte for byte the build the GHCup project published for
/// its version — the second arm of the trust rule (`CLIToolTrust`), for a binary
/// that is only ever ad hoc signed.
///
/// The project publishes the sha256 of each bare binary in the release's
/// `SHA256SUMS` on downloads.haskell.org (`<hex>  ./aarch64-apple-darwin-ghcup-0.2.6.2`,
/// 0.2.6.2 arm64: `4e521e00…cc1d`, the same as the metadata's `dlHash` that
/// `ghcup upgrade` checks its download against). The file is 5 KB, so it is
/// fetched by the check itself, once per version (`GhcupPublishedDigests`).
/// `SHA256SUMS.sig` is a GPG signature; nothing here checks it, as `ghcup` itself
/// does not unless told to.
struct GhcupVerifier: Sendable {

    /// A URL's body; throws on anything but a 2xx.
    typealias Download = @Sendable (URL) async throws -> Data

    let download: Download
    let digests: GhcupPublishedDigests

    init(download: @escaping Download = GhcupVerifier.get, digests: GhcupPublishedDigests = .shared) {
        self.download = download
        self.digests = digests
    }

    /// Whether `sha256` is `version`'s published build for `target`.
    func verify(sha256: String?, version: String, target: String) async -> UvVerifier.Result {
        let published: String
        switch await publishedDigest(version: version, target: target) {
        case .success(let digest): published = digest
        case .failure(let failure): return .couldNotVerify(failure.reason)
        }
        return CLIToolTrust.matches(sha256, published: published)
            ? .matches
            : .differs("not the ghcup \(version) the GHCup project published")
    }

    struct Failure: Error {
        let reason: String
    }

    func publishedDigest(version: String, target: String) async -> Result<String, Failure> {
        guard GhcupRelease.isVersion(version), GhcupRelease.targets.contains(target) else {
            return .failure(Failure(reason: "no published ghcup \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let sums: String
        do {
            sums = String(decoding: try await download(GhcupRelease.sumsURL(version: version)), as: UTF8.self)
        } catch {
            return .failure(Failure(reason: "could not read ghcup \(version)'s SHA256SUMS: \(error)"))
        }
        guard let digest = GhcupRelease.digest(inSums: sums, asset: GhcupRelease.assetName(version: version, target: target))
        else {
            return .failure(Failure(reason: "ghcup \(version)'s SHA256SUMS names no \(target) build"))
        }
        await offCooperativePool { digests.remember(digest, version: version, target: target) }
        return .success(digest)
    }

    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw GhcupRelease.Failure.http(status) }
        return data
    }
}

/// The published sha256 of each release's `ghcup`, by version and target, as
/// `GhcupVerifier` read it from `SHA256SUMS`: `LuvusPublishedDigests`, in
/// `com.duoupdater.app/ghcup-published-digests.json`.
public final class GhcupPublishedDigests: @unchecked Sendable {

    public static let shared = GhcupPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-ghcup-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("ghcup-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("ghcup-published-digests.json"))
    }

    static func key(version: String, target: String) -> String { "\(version) \(target)" }

    /// Blocking.
    func digest(version: String, target: String) -> String? {
        lock.withLock { load()[Self.key(version: version, target: target)] }
    }

    /// Blocking.
    func remember(_ digest: String, version: String, target: String) {
        lock.withLock {
            var entries = load()
            entries[Self.key(version: version, target: target)] = digest
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Under the lock.
    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return entries
    }
}
