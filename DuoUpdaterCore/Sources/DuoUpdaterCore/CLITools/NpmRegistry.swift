import Foundation

/// What the npm registry says about one package: its dist-tags, and for every
/// version the parts of its manifest an update decision needs.
///
/// Read from the abbreviated metadata (`Accept: application/vnd.npm.install-v1+json`),
/// the document npm itself installs from: `dist-tags`, and per version `engines`,
/// `deprecated` and `bin` — no `repository`, no readme. Measured 2026-10-02:
/// openclaw's is 734 KB for 262 versions, pnpm's 1.9 MB for 1335.
public struct NpmPackument: Sendable, Equatable {

    public struct Manifest: Sendable, Equatable {
        /// `engines.node` as written; nil when absent (or not a string — pnpm has
        /// `"node": null` in some old versions).
        public let node: String?
        public let npm: String?
        public let deprecated: Bool

        public init(node: String? = nil, npm: String? = nil, deprecated: Bool = false) {
            self.node = node
            self.npm = npm
            self.deprecated = deprecated
        }
    }

    public let distTags: [String: String]
    public let versions: [String: Manifest]

    public init(distTags: [String: String], versions: [String: Manifest]) {
        self.distTags = distTags
        self.versions = versions
    }

    /// nil when the document is not a packument. A version's `engines` that is
    /// not an object (an array, in some packages from 2011) constrains nothing,
    /// as for npm.
    public static func parse(_ data: Data) -> NpmPackument? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = json["dist-tags"] as? [String: Any],
              let versions = json["versions"] as? [String: Any]
        else { return nil }
        var manifests: [String: Manifest] = [:]
        for (version, value) in versions {
            let manifest = value as? [String: Any] ?? [:]
            let engines = manifest["engines"] as? [String: Any]
            // `deprecated` is a message; an empty string is npm's "un-deprecate".
            let deprecated = (manifest["deprecated"] as? String).map { !$0.isEmpty } ?? false
            manifests[version] = Manifest(
                node: engines?["node"] as? String, npm: engines?["npm"] as? String, deprecated: deprecated)
        }
        return NpmPackument(distTags: tags.compactMapValues { $0 as? String }, versions: manifests)
    }
}

/// Reads packuments from the public registry.
public struct NpmRegistry: Sendable {

    public static let base = URL(string: "https://registry.npmjs.org/")!

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// 404: not on the public registry.
        case notFound
        case http(Int)
        case unreadable

        public var description: String {
            switch self {
            case .notFound: return "not on the npm registry"
            case .http(let code): return "HTTP \(code)"
            case .unreadable: return "the registry's answer is not package metadata"
            }
        }
    }

    let session: URLSession

    public init(session: URLSession = .updates) {
        self.session = session
    }

    /// `@scope/name` is one path segment with its slash escaped, as npm sends it.
    public static func url(for name: String) -> URL {
        let escaped = name.replacingOccurrences(of: "/", with: "%2f")
        return URL(string: escaped, relativeTo: base)!.absoluteURL
    }

    public func packument(_ name: String) async throws -> NpmPackument {
        var request = URLRequest(url: Self.url(for: name))
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        request.setValue("application/vnd.npm.install-v1+json; q=1.0, application/json; q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw Failure.notFound }
        guard status == 200 else { throw Failure.http(status) }
        guard let packument = await offCooperativePool({ NpmPackument.parse(data) }) else { throw Failure.unreadable }
        return packument
    }
}

/// Which version an install should move to, and what stands in the way of a newer one.
///
/// The rules the user agreed (2026-10-01):
/// - **The track.** A release follows `latest`, as `npm install -g <name>` does.
///   A prerelease follows the dist-tag its version belongs to — the tag named
///   after its prerelease word (`beta` for `2026.9.1-beta.1`), else the highest
///   other tag pointing at a prerelease with that word — and falls back to
///   `latest`. A package with its own channel setting passes it in (openclaw).
/// - **Never a downgrade.** An install above its tag is `ahead`; `npm update -g`
///   was seen to take `prettier@next` 4.0.0-alpha.13 down to 3.9.9.
/// - **The newest version this prefix's node runs**, never above the tag's
///   version: npm's own pick (`npm-pick-manifest`) also prefers a version whose
///   `engines` match the running node, but may then reach versions above
///   `latest` that no tag points at (pnpm's 12.8.2 over `latest` 12.8.1, tagged
///   `next-12` only, 2026-10-02) — an install is not offered what its channel
///   has not published. Deprecated versions are not offered.
/// - On the `latest` track only releases are candidates; on a prerelease track
///   prereleases are too.
public struct NpmPick: Sendable, Equatable {
    /// The dist-tag followed, and the version it points at.
    public let tag: String
    public let tagVersion: String
    /// The newest version above the installed one this prefix can run, or nil.
    public let offered: String?
    /// Set when the tag's version is newer than the installed one but its
    /// `engines` exclude this prefix's node or npm.
    public let gap: NpmPackage.RuntimeGap?
    /// Versions above the installed one, up to `offered` (or the tag's version
    /// when nothing is offered), newest first, at most `pendingLimit` — whose
    /// release notes the row shows.
    public let pending: [String]

    static let pendingLimit = 10

    /// The tag an install at `installed` follows; nil when the packument has no
    /// tags at all.
    static func track(installed: NpmVersion, distTags: [String: String]) -> String? {
        if let word = installed.prereleaseName {
            if distTags[word] != nil { return word }
            let named = distTags
                .filter { $0.key != "latest" }
                .compactMap { tag, version -> (String, NpmVersion)? in
                    guard let v = NpmVersion(version), v.prereleaseName == word else { return nil }
                    return (tag, v)
                }
                .max { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 > $1.0) }
            if let named { return named.0 }
        }
        return distTags["latest"] != nil ? "latest" : nil
    }

    /// openclaw's channel, as its `resolveNpmChannelTag` maps it: `beta` reads
    /// the `beta` tag unless `latest` is newer or `beta` is missing.
    static func openclawTag(channel: String, distTags: [String: String]) -> String? {
        guard channel == "beta" else { return distTags["latest"] != nil ? "latest" : nil }
        guard let beta = distTags["beta"].flatMap(NpmVersion.init) else { return "latest" }
        if let latest = distTags["latest"].flatMap(NpmVersion.init), beta < latest { return "latest" }
        return "beta"
    }

    /// nil when the installed version or the tag's version is not semver.
    static func pick(
        _ packument: NpmPackument, installed: String, tag: String, node: NpmVersion?, npm: NpmVersion?
    ) -> NpmPick? {
        guard let current = NpmVersion(installed), let tagged = packument.distTags[tag],
              let ceiling = NpmVersion(tagged)
        else { return nil }
        guard current < ceiling else {
            return NpmPick(tag: tag, tagVersion: tagged, offered: nil, gap: nil, pending: [])
        }
        let prereleaseTrack = tag != "latest" || current.isPrerelease
        let candidates = packument.versions.compactMap { text, manifest -> (NpmVersion, String, NpmPackument.Manifest)? in
            guard let v = NpmVersion(text), current < v, v <= ceiling,
                  prereleaseTrack || !v.isPrerelease else { return nil }
            return (v, text, manifest)
        }.sorted { $0.0 > $1.0 }
        let offered = candidates.first { !$0.2.deprecated && runs($0.2, node: node, npm: npm) }
        let tagManifest = packument.versions[tagged]
        let gap = tagManifest.flatMap { runs($0, node: node, npm: npm) ? nil : NpmPackage.RuntimeGap(
            version: tagged, node: $0.node, npm: $0.npm, nodeVersion: node?.description,
            minimumNode: $0.node.flatMap(NpmRange.init).flatMap { range in node.flatMap(range.minimum(above:)) }?.description)
        }
        let top = offered?.0 ?? ceiling
        let pending = candidates.filter { $0.0 <= top }.prefix(pendingLimit).map(\.1)
        return NpmPick(tag: tag, tagVersion: tagged, offered: offered?.1, gap: gap, pending: Array(pending))
    }

    /// `engines` met, the way npm checks them (`checkEngine`): an unknown node or
    /// npm version is not held against anything; a range npm cannot parse is
    /// never met.
    static func runs(_ manifest: NpmPackument.Manifest, node: NpmVersion?, npm: NpmVersion?) -> Bool {
        if let node, let range = manifest.node {
            guard NpmRange(range)?.satisfies(node) == true else { return false }
        }
        if let npm, let range = manifest.npm {
            guard NpmRange(range)?.satisfies(npm) == true else { return false }
        }
        return true
    }
}
