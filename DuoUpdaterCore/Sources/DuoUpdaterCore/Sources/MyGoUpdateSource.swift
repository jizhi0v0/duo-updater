import Foundation

/// Resolves updates for apps built with MyGo (`github.com/egoist/mygo`) by
/// reading the manifest their own updater reads, at the address and with the key
/// linked into their binary (`InstalledApp.myGoUpdate`, `MyGoUpdateConfig`).
///
/// A *mechanism*, like `SparkleAppcastSource` and `ElectronManifestSource`: no
/// per-app addresses or keys. MyGo is an update framework in Sparkle's sense —
/// `mygo build` signs every platform's archive and writes `update-<target>.json`,
/// `mygo.Updater` checks it, downloads, verifies and swaps — so every app built
/// with it is covered by the same reviewed rule.
///
/// **Placed right after `SparkleAppcastSource`.** The address is the one the app
/// itself reads, which is the same standing a `SUFeedURL` has, so a hand-written
/// recipe for a MyGo app would only restate it. Pulse's was retired when this
/// source landed. Moshi Go's probe stays, and not as a restatement: a Tauri-era
/// copy filed under its id by `BundleIDMigration` links no MyGo feed, so that
/// probe is the only source for it (see `app-getmoshi-desktop.swift`).
///
/// What the manifest gives (MyGo's `update.Manifest`): `version`, `notes`
/// (Markdown), `date`, the archive's `url`, `size` and `signature`, and
/// `deltas[]` from earlier versions. The archive is `.tar.gz` holding the bundle;
/// `signature` is Ed25519 over its SHA-256, checked here with the key from the
/// installed binary — the check the app's own updater makes (`update.Verify`).
/// Patches are applied by `MyGoDelta` through `MyGoManifest.patches`.
///
/// Trust follows the installed copy. A Developer ID app takes the ordinary
/// Team-ID route with the signature on top; an ad-hoc signed one (three of the
/// five MyGo apps measured) takes `InstallTrust.myGoSignatureOnly`.
///
/// Version: `mygo build` writes the config's `version` to both
/// `CFBundleShortVersionString` and `CFBundleVersion` (`cmd/mygo/bundle.go`) and
/// to the manifest, and the app compares the manifest against it (an app may
/// override it with `App.SetVersion`, but the manifest is cut against the
/// packaged one). So the manifest's `version` is the bundle's own string on both
/// sides.
///
/// **Not covered by `duo verify`'s nightly sweep**, for the reason
/// `ElectronManifestSource` gives: there is no table of addresses to walk, only
/// whatever bundles a machine has. `RecipeHealth` is its failure signal.
public struct MyGoUpdateSource: UpdateSource {
    public let name = Self.sourceName

    public static let sourceName = "MyGo"

    private let session: URLSession
    private let githubToken: String?
    /// The installed copy's Team ID, which decides its `installTrust`. Injected
    /// so a test does not depend on what is signed how on the machine running it.
    private let teamIdentifier: @Sendable (URL) -> String?

    /// - Parameter githubToken: for feeds of tagged GitHub releases, which are
    ///   resolved through the GitHub API (60 requests an hour without one).
    public init(githubToken: String? = nil, session: URLSession = .updates) {
        self.init(
            githubToken: githubToken, session: session,
            teamIdentifier: { try? SignatureVerifier.teamIdentifier(at: $0) })
    }

    init(
        githubToken: String?, session: URLSession,
        teamIdentifier: @escaping @Sendable (URL) -> String?
    ) {
        self.githubToken = githubToken
        self.session = session
        self.teamIdentifier = teamIdentifier
    }

    /// MyGo's own limits (`update.MaxManifestSize`, `MaxArchiveSize`).
    static let maxManifestBytes = 1 << 20
    static let maxArchiveBytes: Int64 = 1 << 30

    public enum Failure: Error, LocalizedError, Equatable {
        case manifestStatus(Int)
        case manifestUnreadable
        /// No `version`, `url` or `signature`, or a size MyGo would refuse:
        /// MyGo's own updater treats such a manifest as no update at all.
        case manifestIncomplete
        case releasesStatus(Int)
        case noTaggedRelease(prefix: String)
        case taggedFeedMalformed

        public var errorDescription: String? {
            switch self {
            case .manifestStatus(let code): return "The MyGo update manifest returned HTTP \(code)."
            case .manifestUnreadable: return "The MyGo update manifest could not be read."
            case .manifestIncomplete: return "The MyGo update manifest is incomplete."
            case .releasesStatus(let code): return "GitHub's release list returned HTTP \(code)."
            case .noTaggedRelease(let prefix): return "No published release is tagged “\(prefix)…”."
            case .taggedFeedMalformed: return "The app's MyGo update feed is not a GitHub release feed."
            }
        }
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard let config = app.myGoUpdate else { return nil }
        let healthID = app.bundleID ?? config.feed
        do {
            let remote = try await resolve(config, for: app)
            await RecipeHealth.shared.recordSuccess(id: healthID, source: name)
            return remote
        } catch {
            Log.source.notice(
                "mygo: \(app.bundleID ?? "?", privacy: .public) \(config.feed, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await RecipeHealth.shared.recordMiss(
                id: healthID, source: name, detail: error.localizedDescription)
            throw error
        }
    }

    private func resolve(_ config: MyGoUpdateConfig, for app: InstalledApp) async throws -> RemoteVersion {
        let manifestURL: URL
        if config.isTagged {
            manifestURL = try await resolveTagged(config.feed)
        } else if let url = config.manifestURL {
            manifestURL = url
        } else {
            throw Failure.manifestUnreadable
        }

        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 15
        // A manifest keeps its name from version to version (MyGo uploads it with
        // `Cache-Control: no-cache` to S3 for this reason), so it is revalidated
        // like every other version feed.
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.versionFeedData(
            for: request, label: "MyGo \(app.name)")
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.manifestStatus(http.statusCode)
        }
        guard data.count <= Self.maxManifestBytes,
              let body = String(data: data, encoding: .utf8),
              let release = MyGoManifest.release(inBody: body)
        else { throw Failure.manifestUnreadable }

        // MyGo's own updater refuses all of these (`checkUpdate`, `installUpdate`).
        guard !release.version.isEmpty,
              let raw = release.url, let archiveURL = URL(string: raw, relativeTo: manifestURL)?.absoluteURL,
              archiveURL.scheme == "https",
              let signature = release.signature, !signature.isEmpty,
              let size = release.size, size > 0, size <= Self.maxArchiveBytes
        else { throw Failure.manifestIncomplete }

        // A Security call: off the cooperative pool (#351).
        let lookup = teamIdentifier, path = app.path
        let team = await offCooperativePool { lookup(path) }
        let fields = ReleaseDate.publishedFields(from: release.date)
        let changelog = Self.changelog(
            notes: release.notes ?? "", version: release.version,
            date: AppcastMarkdownParser.displayDate(from: release.date))

        return RemoteVersion(
            shortVersion: release.version,
            version: release.version,
            marketingMatchesBundle: true,
            downloadURL: archiveURL,
            pageURL: Self.releasePage(for: archiveURL),
            downloadSize: size,
            sourceName: name,
            vendorInstallerKind: .tarGz,
            installTrust: team == nil ? .myGoSignatureOnly : .developerID,
            myGoSignature: MyGoSignature(
                publicKey: config.publicKey,
                signature: MyGoManifest.archiveSignature(
                    inBody: body, forVersion: release.version, url: archiveURL,
                    feedURL: manifestURL)),
            structuredChangelog: changelog,
            publishedAt: fields.publishedAt,
            vendorDay: fields.vendorDay,
            deltas: MyGoManifest.patches(
                inBody: body, forVersion: release.version, feedURL: manifestURL,
                publicKey: config.publicKey))
    }

    /// The manifest's `notes` as a changelog.
    ///
    /// Normally one entry: `mygo build` copies the `## <version>` section of the
    /// app's changelog (Pulse, Gotify Desktop). But the file is the developer's,
    /// and some keep the whole history in it under `### <version>` headings —
    /// Leafmark 0.9.2's notes are 7 KB of `### 0.9.2` … `### 0.1.0` (2026-10-13).
    /// Read as one entry, every past release became an item of this one. So when
    /// the notes open on the release's own version as a heading and name at least
    /// one more version the same way, each such heading starts an entry. Anything
    /// else stays a single entry: a heading that is not a bare version is a
    /// section, not a release.
    static func changelog(notes raw: String, version: String, date: String?) -> Changelog? {
        let notes = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return nil }
        var sections: [(version: String, lines: [String])] = []
        var preamble: [String] = []
        for line in notes.components(separatedBy: "\n") {
            if let heading = versionHeading(line) {
                sections.append((heading, []))
            } else if sections.isEmpty {
                preamble.append(line)
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }
        let opensOnThisRelease = sections.first?.version == normalized(version)
            && preamble.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard sections.count >= 2, opensOnThisRelease else {
            return AppcastMarkdownParser.entry(from: notes, version: version, date: date)
                .map { Changelog(entries: [$0]) }
        }
        let entries = sections.enumerated().compactMap { index, section in
            AppcastMarkdownParser.entry(
                from: section.lines.joined(separator: "\n"),
                version: index == 0 ? version : section.version,
                date: index == 0 ? date : nil)
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    /// The version a Markdown heading names and nothing else — `## 1.2.0`,
    /// `### v1.2.0`, `## [1.2.0]` — normalized; nil for any other line.
    private static func versionHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        guard text.wholeMatch(of: #/\[?v?[0-9]+(?:\.[0-9]+)+(?:-[0-9A-Za-z.]+)?\]?/#) != nil else {
            return nil
        }
        return normalized(text)
    }

    private static func normalized(_ version: String) -> String {
        var v = version.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        if v.hasPrefix("v") { v.removeFirst() }
        return v
    }

    /// The GitHub release page of an archive served from a release, else nil.
    static func releasePage(for archive: URL) -> URL? {
        let parts = archive.pathComponents
        guard archive.host == "github.com", parts.count == 7,
              parts[3] == "releases", parts[4] == "download"
        else { return nil }
        var page = URLComponents()
        page.scheme = "https"
        page.host = "github.com"
        page.path = "/\(parts[1])/\(parts[2])/releases/tag/\(parts[5])"
        return page.url
    }

    // MARK: - Tagged GitHub feeds

    /// The manifest a feed of tagged releases names now: the release with the
    /// HIGHEST version among those whose tag has the feed's prefix and that are
    /// neither a draft nor a prerelease, over at most 10 pages of 100.
    ///
    /// Where this parts company with MyGo's own `update.ResolveFeed`, which takes
    /// the first such release in the list: the list's order is not a release
    /// order (a backport published after a newer release would come first), and
    /// an offer of an older version as "latest" is the one wrong answer a
    /// version source must not give. So every page is read, up to MyGo's own
    /// bound; a repository with under 100 releases still costs one request.
    private func resolveTagged(_ feed: String) async throws -> URL {
        guard let tagged = TaggedFeed(feed) else { throw Failure.taggedFeedMalformed }
        var eligible: [TaggedFeed.Release] = []
        for page in 1...10 {
            guard let url = URL(string:
                "https://api.github.com/repos/\(tagged.repo)/releases?per_page=100&page=\(page)")
            else { throw Failure.taggedFeedMalformed }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
            if let githubToken {
                request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await session.versionFeedData(
                for: request, label: "MyGo releases \(tagged.repo)")
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Failure.releasesStatus(http.statusCode)
            }
            guard let releases = try? JSONDecoder().decode([TaggedFeed.Release].self, from: data) else {
                throw Failure.manifestUnreadable
            }
            eligible += releases
            if releases.count < 100 { break }
        }
        guard let tag = tagged.newestTag(in: eligible), let manifest = tagged.manifestURL(tag: tag) else {
            throw Failure.noTaggedRelease(prefix: tagged.prefix)
        }
        return manifest
    }

    /// `https://github.com/<owner>/<repo>/releases/download/<prefix>{version}/<name>`
    /// (MyGo's `update.TaggedFeed`), taken apart.
    struct TaggedFeed: Equatable {
        let repo: String
        /// The tag prefix, unescaped.
        let prefix: String
        /// The manifest's file name, as escaped in the feed.
        let name: String

        init?(_ feed: String) {
            let parts = feed.split(separator: "/", omittingEmptySubsequences: false)
            // https: "" github.com owner repo releases download <prefix>{version} <name>
            guard parts.count == 9, parts[0] == "https:", parts[1].isEmpty,
                  parts[2] == "github.com", parts[5] == "releases", parts[6] == "download",
                  parts[7].hasSuffix(MyGoUpdateConfig.versionPlaceholder),
                  !parts[3].isEmpty, !parts[4].isEmpty, !parts[8].isEmpty,
                  let prefix = String(parts[7].dropLast(MyGoUpdateConfig.versionPlaceholder.count))
                    .removingPercentEncoding
            else { return nil }
            repo = "\(parts[3])/\(parts[4])"
            self.prefix = prefix
            name = String(parts[8])
        }

        struct Release: Decodable, Equatable {
            let tagName: String
            let draft: Bool
            let prerelease: Bool

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name", draft, prerelease
            }
        }

        /// The tag of the highest-versioned published release with the prefix,
        /// whatever order the list is in. Compared on what follows the prefix.
        func newestTag(in releases: [Release]) -> String? {
            releases
                .filter { !$0.draft && !$0.prerelease && $0.tagName.hasPrefix(prefix) }
                .max {
                    VersionComparator.compare(
                        String($0.tagName.dropFirst(prefix.count)),
                        String($1.tagName.dropFirst(prefix.count))) == .orderedAscending
                }?
                .tagName
        }

        /// What Go's `url.PathEscape` leaves unescaped, measured with go1.27.2 over
        /// every printable ASCII character: unreserved characters plus `$&+:=@`.
        /// (`CharacterSet.urlPathAllowed` would also keep `;` and `,`, which Go
        /// escapes.)
        static let pathSegmentAllowed = CharacterSet(
            charactersIn: "$&+-.0123456789:=@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~")

        /// The feed with its tag filled in, escaped as Go's `url.PathEscape`
        /// escapes a path segment.
        func manifestURL(tag: String) -> URL? {
            guard let escaped = tag.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed)
            else { return nil }
            return URL(string: "https://github.com/\(repo)/releases/download/\(escaped)/\(name)")
        }
    }
}

// MARK: - The nightly key check

/// What a nightly key check saw (`MyGoUpdateSource.checkKey`,
/// `SparkleAppcastSource.checkKey`): whether the vendor still signs with the key
/// recorded for the app.
public enum UpdateKeyCheck: Sendable, Equatable {
    /// The smallest signed file of the release verified against the key.
    case verified(file: URL, bytes: Int)
    /// It did not: the vendor signs with another key, or the file is not the one
    /// the feed describes. Either way every one-click of this release fails.
    case invalid(file: URL)
    /// Neither the archive nor any patch carries a signature.
    case noSignedFile
    /// The smallest signed file is larger than the sweep will download.
    case tooLarge(file: URL, bytes: Int64)
    /// The file could not be fetched; says nothing about the key.
    case unreachable(file: URL, detail: String)

    /// The most a key check downloads. MyGo patches run 0.16–1.3 MB and archives
    /// 6–33 MB in the apps measured; a release with no patch and a larger
    /// archive is reported rather than fetched.
    public static let byteCap: Int64 = 64 * 1024 * 1024

    /// Download the smallest of `signed` and check it with `verify` (which
    /// throws when the signature does not hold).
    static func smallest(
        of signed: [(url: URL, size: Int64, signature: String)],
        session: URLSession,
        verify: (Data, String) throws -> Void
    ) async -> UpdateKeyCheck {
        guard let smallest = signed.min(by: { $0.size < $1.size }) else { return .noSignedFile }
        guard smallest.size <= byteCap else {
            return .tooLarge(file: smallest.url, bytes: smallest.size)
        }
        var request = URLRequest(url: smallest.url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .unreachable(file: smallest.url, detail: "HTTP \(http.statusCode)")
            }
            do {
                try verify(data, smallest.signature)
                return .verified(file: smallest.url, bytes: data.count)
            } catch {
                return .invalid(file: smallest.url)
            }
        } catch {
            return .unreachable(file: smallest.url, detail: error.localizedDescription)
        }
    }
}

/// The MyGo sweep's name for `UpdateKeyCheck`, from before Sparkle had one.
public typealias MyGoKeyCheck = UpdateKeyCheck

extension MyGoUpdateSource {

    /// See `UpdateKeyCheck.byteCap`.
    public static let keyCheckByteCap: Int64 = UpdateKeyCheck.byteCap

    /// Download the smallest file `remote` publishes a signature for — a patch
    /// when there is one, else the archive — and verify it against `publicKey`.
    /// For `duo verify`, which has no installed binary to take the key from.
    public func checkKey(_ remote: RemoteVersion, publicKey: String) async -> MyGoKeyCheck {
        var signed: [(url: URL, size: Int64, signature: String)] = remote.deltas.compactMap {
            guard $0.format == .myGo, let signature = $0.edSignature else { return nil }
            return ($0.url, $0.size ?? .max, signature)
        }
        if let url = remote.downloadURL, let signature = remote.myGoSignature?.signature {
            signed.append((url, remote.downloadSize ?? .max, signature))
        }
        return await UpdateKeyCheck.smallest(of: signed, session: session) { data, signature in
            try SignatureVerifier.verifyMyGoSignature(
                fileData: data, signatureBase64: signature, publicKeyBase64: publicKey)
        }
    }
}
