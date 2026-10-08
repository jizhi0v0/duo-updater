import Foundation

/// One published herdr build: a stable release, or a preview built from
/// `master` after the stable release it names as its base.
///
/// herdr spells a preview's version `<base>-preview.<build_id>`
/// (`src/build_info.rs`), and `herdr --version` prints that: the 2026-09-29
/// preview is `0.9.2-preview.2026-09-29-8e78f929d8f0`. Its `base` is the last
/// stable release when it was built — Cargo's version is bumped at a release —
/// so a preview is newer than its base and older than the next stable release.
/// Two previews order by the date their id starts with, then by when they were
/// built (2026-09-29 has two).
public struct HerdrBuild: Sendable, Equatable, Codable {
    /// `0.9.2`: the stable release, or a preview's base.
    public let base: String
    /// `2026-09-29-8e78f929d8f0`; nil for a stable release.
    public let previewID: String?
    /// ISO 8601, for two previews of one day; nil for a stable release.
    public let builtAt: String?

    public init(base: String, previewID: String? = nil, builtAt: String? = nil) {
        self.base = base
        self.previewID = previewID
        self.builtAt = builtAt
    }

    public var isPreview: Bool { previewID != nil }

    /// What `herdr --version` prints after `herdr `.
    public var version: String { previewID.map { "\(base)-preview.\($0)" } ?? base }

    /// Older, the same build, or newer; nil when it cannot be told — two previews
    /// of one day without both build times.
    public static func compare(_ a: HerdrBuild, _ b: HerdrBuild) -> ComparisonResult? {
        let bases = VersionComparator.compare(a.base, b.base)
        if bases != .orderedSame { return bases }
        switch (a.previewID, b.previewID) {
        case (nil, nil): return .orderedSame
        case (nil, _?): return .orderedAscending
        case (_?, nil): return .orderedDescending
        case let (x?, y?):
            if x == y { return .orderedSame }
            let (dayX, dayY) = (x.prefix(10), y.prefix(10))
            if dayX != dayY { return dayX < dayY ? .orderedAscending : .orderedDescending }
            guard let timeX = a.builtAt, let timeY = b.builtAt, timeX != timeY else { return nil }
            return timeX < timeY ? .orderedAscending : .orderedDescending
        }
    }

    /// `0.9.3`: three numbers, what every stable tag and preview base is. Also
    /// what makes a version safe in a URL.
    static func isBase(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.count <= 10 && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// `2026-09-29-8e78f929d8f0`: a day and twelve hex digits, every preview tag
    /// so far.
    static func isPreviewID(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts[0...2].allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts[3].count == 12, parts[3].allSatisfy({ $0.isHexDigit && ($0.isNumber || $0.isLowercase) })
        else { return false }
        return true
    }
}

/// herdr's channels and published builds, as `herdr update` reads them
/// (`src/update.rs`), and the sha256 the vendor published for each.
///
/// **Stable**: `https://herdr.dev/latest.json` — what the installer reads too.
/// `version` is the newest release; its `sha256[<target>]` (and `assets[<target>]`,
/// the GitHub asset URL) is what `herdr update` downloads and checks. `releases`
/// has an entry for each of the 59 stable releases (0.1.0 to 0.9.3 on
/// 2026-10-07) with its `notes`; only 0.8.0 and later carry a `sha256` map.
///
/// **Preview**: `https://herdr.dev/preview.json` —
/// `{schema_version, channel: "preview", base_version, build_id, built_at, …,
/// assets: {<target>: {url, sha256}}, builds: {<build_id>: {base_version,
/// built_at, tag, assets, …}}}`. The top level is the newest build, what
/// `herdr update` installs whenever its build id differs from the running
/// one's; `builds` keeps the 30 newest (2026-06-05 to 2026-09-29).
///
/// **Older builds** — stable releases before 0.8.0, the five previews `builds`
/// no longer lists — are proven by GitHub's own per-asset digest
/// (`"digest": "sha256:…"`), which every one of the 94 releases (59 stable, 35
/// `preview-<build_id>` prereleases) carries for `herdr-macos-aarch64` and
/// `-x86_64`. Measured 2026-10-07: v0.9.3's `herdr-macos-aarch64` is
/// `5173a3e0…2884157` in latest.json, in its GitHub digest and on disk alike. A
/// preview's base is read from its release body's `Base stable: v<x.y.z>` line,
/// which the older previews carry, else from the body's `compare/v<x.y.z>...`
/// link: the five newest previews (2026-09-16 to 09-29) have only the link
/// (checked 2026-10-08), so they are named once `builds` drops them too.
public struct HerdrRelease: Sendable {

    public static let stableManifest = URL(string: "https://herdr.dev/latest.json")!
    public static let previewManifest = URL(string: "https://herdr.dev/preview.json")!

    static func releasesPage(_ page: Int) -> URL {
        URL(string: "https://api.github.com/repos/herdrdev/herdr/releases?per_page=100&page=\(page)")!
    }

    /// Releases looked through for a digest: 300, three times what exists today.
    static let maxPages = 3

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        /// GitHub's API rate limit (`GitHubReleasesSource.isRateLimited`), on the
        /// releases looked through for a digest.
        case rateLimited(Int)
        case unreadable
        /// The channel has no build for this Mac.
        case noBuild(String)
        /// A release matched, but names no version this code can order: a
        /// preview whose body has neither a `Base stable:` line nor a compare link.
        case unnamed(String)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .rateLimited(let status):
                return GitHubReleasesSource.GitHubError.rateLimited(status).errorDescription ?? "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .noBuild(let target): return "the channel has no \(target) build"
            case .unnamed(let tag): return "its release \(tag) names no base version"
            }
        }
    }

    /// Whether a file's sha256 is a build herdr published.
    public enum Identity: Sendable, Equatable {
        case published(HerdrBuild)
        /// In none of herdr's manifests nor its GitHub releases.
        case unpublished
        /// The sources could not all be asked.
        case couldNotVerify(String)
        /// As `couldNotVerify`, and GitHub's releases were among the sources left
        /// unasked because its API's rate limit refused them: a token lifts it.
        case rateLimited(String)
    }

    /// What one look at a channel answers: the build it offers for this Mac, and
    /// which build the file at hand is.
    public struct Resolution: Sendable, Equatable {
        public let offered: HerdrBuild
        public let installed: Identity
    }

    /// The body, the status and the answer's `X-RateLimit-Remaining`.
    typealias Fetch = @Sendable (URL) async throws -> (Data, Int, String?)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url in
            var request = URLRequest(url: url)
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            if ChangelogService.isGitHubAPI(url) {
                // What `ChangelogService` sends to the GitHub API, its token
                // included: unauthenticated, the API allows 60 requests an hour.
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                if let token = await ChangelogService.gitHubToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            }
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            let http = response as? HTTPURLResponse
            return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// One manifest, read: the build it offers for each target, and every build
    /// it names by sha256.
    struct Manifest: Sendable, Equatable {
        /// target → (build, sha256)
        let offers: [String: Offer]
        /// sha256 → build, for every build and target listed.
        let builds: [String: HerdrBuild]

        struct Offer: Sendable, Equatable {
            let build: HerdrBuild
            let sha256: String
        }
    }

    func manifest(channel: String) async throws -> Manifest {
        let url = channel == "preview" ? Self.previewManifest : Self.stableManifest
        let (data, status, _) = try await fetch(url)
        guard status == 200 else { throw Failure.http(status) }
        let parsed = channel == "preview" ? Self.parsePreview(data) : Self.parseStable(data)
        guard let parsed else { throw Failure.unreadable }
        return parsed
    }

    /// The channel's build for `target` and which build `sha256` is: the
    /// channel's manifest, then the other one, then GitHub's digests.
    public func resolve(channel: String, target: String, sha256: String) async throws -> Resolution {
        let primary = try await manifest(channel: channel)
        guard let offer = primary.offers[target] else { throw Failure.noBuild(target) }
        let hash = sha256.lowercased()
        if let build = primary.builds[hash] {
            return Resolution(offered: offer.build, installed: .published(build))
        }
        var unasked: [String] = []
        var rateLimited = false
        do {
            if let build = try await manifest(channel: channel == "preview" ? "stable" : "preview").builds[hash] {
                return Resolution(offered: offer.build, installed: .published(build))
            }
        } catch {
            unasked.append("herdr's \(channel == "preview" ? "stable" : "preview") manifest (\(error))")
        }
        do {
            if let build = try await gitHubBuild(sha256: hash, target: target) {
                return Resolution(offered: offer.build, installed: .published(build))
            }
        } catch {
            unasked.append("herdr's GitHub releases (\(error))")
            if case .rateLimited? = error as? Failure { rateLimited = true }
        }
        guard unasked.isEmpty else {
            let reason = "could not ask " + unasked.joined(separator: " or ")
            return Resolution(offered: offer.build,
                              installed: rateLimited ? .rateLimited(reason) : .couldNotVerify(reason))
        }
        return Resolution(offered: offer.build, installed: .unpublished)
    }

    /// The release whose `herdr-<target>` asset GitHub digests as `sha256`;
    /// nil when none of the newest `maxPages` pages has it.
    func gitHubBuild(sha256: String, target: String) async throws -> HerdrBuild? {
        for page in 1...Self.maxPages {
            let (data, status, remaining) = try await fetch(Self.releasesPage(page))
            guard status == 200 else {
                throw GitHubReleasesSource.isRateLimited(status, rateLimitRemaining: remaining)
                    ? Failure.rateLimited(status) : Failure.http(status)
            }
            guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw Failure.unreadable
            }
            if let build = try Self.build(in: releases, sha256: sha256, target: target) { return build }
            if releases.count < 100 { break }
        }
        return nil
    }

    // MARK: - Parsing

    /// latest.json. nil when it is not one.
    static func parseStable(_ data: Data) -> Manifest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String, HerdrBuild.isBase(version)
        else { return nil }
        let releases = json["releases"] as? [String: Any] ?? [:]
        var builds: [String: HerdrBuild] = [:]
        for (name, value) in releases {
            guard HerdrBuild.isBase(name), let release = value as? [String: Any] else { continue }
            for hex in digests(release["sha256"]).values { builds[hex] = HerdrBuild(base: name) }
        }
        // The newest release's hashes: top-level `sha256`, else its entry in
        // `releases` (`release_info_from_manifest`). An `assets` value may also be
        // an object carrying its own (`AssetRef`).
        var newest = digests(json["sha256"])
        for (target, hex) in digests((releases[version] as? [String: Any])?["sha256"]) where newest[target] == nil {
            newest[target] = hex
        }
        for (target, hex) in assetDigests(json["assets"]) { newest[target] = hex }
        let build = HerdrBuild(base: version)
        var offers: [String: Manifest.Offer] = [:]
        for (target, hex) in newest {
            offers[target] = Manifest.Offer(build: build, sha256: hex)
            builds[hex] = build
        }
        return Manifest(offers: offers, builds: builds)
    }

    /// preview.json. nil when it is not one.
    static func parsePreview(_ data: Data) -> Manifest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["channel"] as? String == "preview",
              let base = json["base_version"] as? String, HerdrBuild.isBase(base),
              let id = (json["build_id"] as? String)?.trimmingCharacters(in: .whitespaces), HerdrBuild.isPreviewID(id)
        else { return nil }
        var builds: [String: HerdrBuild] = [:]
        for (name, value) in json["builds"] as? [String: Any] ?? [:] {
            guard HerdrBuild.isPreviewID(name), let entry = value as? [String: Any],
                  let entryBase = entry["base_version"] as? String, HerdrBuild.isBase(entryBase)
            else { continue }
            let build = HerdrBuild(base: entryBase, previewID: name, builtAt: entry["built_at"] as? String)
            for hex in assetDigests(entry["assets"]).values { builds[hex] = build }
        }
        let newest = HerdrBuild(base: base, previewID: id, builtAt: json["built_at"] as? String)
        var top = assetDigests(json["assets"])
        // `herdr update` falls back to the newest build's entry in `builds`.
        if let entry = (json["builds"] as? [String: Any])?[id] as? [String: Any] {
            for (target, hex) in assetDigests(entry["assets"]) where top[target] == nil { top[target] = hex }
        }
        var offers: [String: Manifest.Offer] = [:]
        for (target, hex) in top {
            offers[target] = Manifest.Offer(build: newest, sha256: hex)
            builds[hex] = newest
        }
        return Manifest(offers: offers, builds: builds)
    }

    /// `{target: hex}`, only well-formed digests, lowercased.
    static func digests(_ value: Any?) -> [String: String] {
        var out: [String: String] = [:]
        for (target, hex) in value as? [String: Any] ?? [:] {
            if let hex = (hex as? String).flatMap(CLIToolTrust.firstDigest) { out[target] = hex }
        }
        return out
    }

    /// `{target: {url, sha256}}` → `{target: hex}`; a bare URL string carries none.
    static func assetDigests(_ value: Any?) -> [String: String] {
        var out: [String: String] = [:]
        for (target, asset) in value as? [String: Any] ?? [:] {
            if let hex = ((asset as? [String: Any])?["sha256"] as? String).flatMap(CLIToolTrust.firstDigest) {
                out[target] = hex
            }
        }
        return out
    }

    /// The build of the release among `releases` whose `herdr-<target>` asset
    /// GitHub digests as `sha256`.
    static func build(in releases: [[String: Any]], sha256: String, target: String) throws -> HerdrBuild? {
        let name = "herdr-\(target)"
        for release in releases where release["draft"] as? Bool != true {
            guard let tag = release["tag_name"] as? String,
                  let asset = (release["assets"] as? [[String: Any]] ?? []).first(where: { $0["name"] as? String == name }),
                  let digest = asset["digest"] as? String, digest.hasPrefix("sha256:"),
                  CLIToolTrust.matches(sha256, published: String(digest.dropFirst("sha256:".count)))
            else { continue }
            if tag.hasPrefix("v"), HerdrBuild.isBase(String(tag.dropFirst())) {
                return HerdrBuild(base: String(tag.dropFirst()))
            }
            if tag.hasPrefix("preview-"), HerdrBuild.isPreviewID(String(tag.dropFirst("preview-".count))),
               let base = previewBase(release["body"] as? String) {
                return HerdrBuild(base: base, previewID: String(tag.dropFirst("preview-".count)),
                                  builtAt: release["published_at"] as? String)
            }
            throw Failure.unnamed(tag)
        }
        return nil
    }

    /// `Base stable: v0.6.8` in a preview release's body, else the base its
    /// "View changes" link compares against: `…/compare/v0.9.2...8e78f929d8f0…`.
    static func previewBase(_ body: String?) -> String? {
        guard let body else { return nil }
        let forms = [("Base stable: v", #"Base stable: v\d+\.\d+\.\d+\b"#),
                     ("/compare/v", #"/compare/v\d+\.\d+\.\d+(?=\.\.\.)"#)]
        for (marker, pattern) in forms {
            guard let range = body.range(of: pattern, options: .regularExpression) else { continue }
            let version = String(body[range].dropFirst(marker.count))
            if HerdrBuild.isBase(version) { return version }
        }
        return nil
    }
}
