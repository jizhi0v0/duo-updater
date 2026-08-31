import Foundation

/// The electron-builder equivalent of `SUFeedURL`: the update configuration a
/// packaged Electron app carries in `Contents/Resources/app-update.yml`, and the
/// `*-mac.yml` manifest it points at.
///
/// Why this is a *generic mechanism* and not a registry, which is the whole
/// reason `ElectronManifestSource` can exist at all: electron-builder writes this
/// file itself at build time — "automatically creates app-update.yml file for you
/// on build in the resources (this file is internal)" — so reading it is as
/// deterministic as reading a plist key. That is the line between what may run in
/// production and what may not. Recovering an address by scanning a binary for
/// URL literals is a heuristic and belongs in `FeedDiscovery`, where a person
/// reads the result; reading a file the build system generated is not.
public struct ElectronUpdateConfig: Sendable, Hashable {
    public let provider: String
    public let url: String?
    public let owner: String?
    public let repo: String?
    /// Names the manifest file (`<channel>-mac.yml`); absent means `latest`.
    ///
    /// electron-builder puts the release channel AND the architecture in this one
    /// slot — Typeless ships `channel: arm64`, which is why the manifest it reads
    /// is `arm64-mac.yml`. We never second-guess it: whatever the app was built to
    /// ask for is what we ask for.
    public let channel: String

    public init(provider: String, url: String?, owner: String?, repo: String?, channel: String) {
        self.provider = provider
        self.url = url
        self.owner = owner
        self.repo = repo
        self.channel = channel
    }

    /// The macOS manifest address, for the one provider that states it outright.
    ///
    /// `github` gives only owner/repo and `s3` only a bucket, and both would have
    /// to be *constructed*. Termius is the standing argument against constructing
    /// them: its config names the private bucket `termius.desktop.autoupdate`,
    /// which does not resolve at all, while the address that answers is
    /// `autoupdate.termius.com` — a host the config never mentions. A constructed
    /// address that happens to 404 is a dead row; one that happens to answer with
    /// someone else's manifest is worse. Those apps keep their hand-written,
    /// audited recipes.
    public var manifestURL: URL? {
        guard provider.lowercased() == "generic", let url, !url.isEmpty else { return nil }
        let base = url.hasSuffix("/") ? String(url.dropLast()) : url
        return URL(string: "\(base)/\(channel)-mac.yml")
    }

    /// Read the config a packaged Electron app carries, if it carries one.
    public static func read(fromBundleAt bundleURL: URL) -> ElectronUpdateConfig? {
        guard let text = try? String(
            contentsOf: bundleURL.appendingPathComponent("Contents/Resources/app-update.yml"),
            encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// `app-update.yml` is a flat map of scalars, so this reads it as one rather
    /// than pulling a YAML parser in for five keys. Values may be single-quoted
    /// (Notion writes `url: 'https://…'`), which is the only quoting the file uses.
    ///
    /// An empty value is dropped rather than stored: QQ ships `provider: generic`
    /// with `url: ''`, and keeping that would build the relative URL
    /// `/latest-mac.yml` — a thing `URL(string:)` accepts and no one can fetch.
    public static func parse(_ text: String) -> ElectronUpdateConfig? {
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix(" "), !line.hasPrefix("#"),
                  let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == "'" || f == "\"", value.last == f {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { fields[key] = value }
        }
        guard let provider = fields["provider"] else { return nil }
        return ElectronUpdateConfig(
            provider: provider, url: fields["url"],
            owner: fields["owner"], repo: fields["repo"],
            channel: fields["channel"] ?? "latest")
    }
}

/// The `*-mac.yml` a vendor publishes beside its builds.
///
/// The top-level scalars and the `files:` list are read separately, and the
/// distinction is load-bearing. `files:` entries repeat `url:` and `sha512:`
/// indented underneath — Canva's lists the same dmg three times — so a reader
/// that took "the first url" would be taking one of those.
///
/// **The top-level `path` is NOT necessarily this Mac's artifact**, which is the
/// mistake this type exists to stop anyone making twice: ChatWise 26.8.0 names
/// `ChatWise-26.8.0-x64.zip` there, an Intel build, while its `files:` list also
/// carries the arm64 one. DuoUpdater is arm64-only (`App/project.yml`), so taking
/// `path` would have handed an Apple-silicon Mac a build it cannot run — the
/// "installed fine, won't open" failure the whole registry pins arm64 to avoid.
/// See ``artifact(forArch:)``.
public struct ElectronManifest: Sendable, Hashable {
    public struct File: Sendable, Hashable {
        /// Relative to the manifest's own directory, the way Sparkle resolves an
        /// enclosure against its appcast.
        public let url: String
        public let sha512: String?

        public init(url: String, sha512: String?) {
            self.url = url
            self.sha512 = sha512
        }
    }

    public let version: String
    public let path: String?
    public let sha512: String?
    public let releaseDate: String?
    public let files: [File]

    public init(
        version: String, path: String?, sha512: String?, releaseDate: String?,
        files: [File] = []
    ) {
        self.version = version
        self.path = path
        self.sha512 = sha512
        self.releaseDate = releaseDate
        self.files = files
    }

    /// The artifact this host should download, or nil when the manifest publishes
    /// none it can run.
    ///
    /// Order: an entry naming the host architecture, then a `universal` one, then
    /// the top-level `path` — but **only when `path` does not name a foreign
    /// architecture**. Refusing is the right answer for an x64-only manifest: a
    /// detection-only row that says "1.2.3 is out" is honest, where an install
    /// button that fetches an Intel build is not.
    public func artifact(forArch arch: String = "arm64") -> File? {
        if let native = files.first(where: { $0.url.localizedCaseInsensitiveContains(arch) }) {
            return native
        }
        if let universal = files.first(where: {
            $0.url.localizedCaseInsensitiveContains("universal")
        }) {
            return universal
        }
        guard let path, !path.isEmpty, !Self.namesForeignArch(path, host: arch) else { return nil }
        return File(url: path, sha512: sha512)
    }

    /// Whether a filename advertises an architecture that is not this host's. Only
    /// the tokens electron-builder actually emits — an unmarked name is treated as
    /// runnable, because most vendors ship one universal artifact and label it
    /// nothing at all.
    static func namesForeignArch(_ name: String, host: String) -> Bool {
        for token in ["x64", "x86_64", "intel", "arm64"] where token != host {
            if name.localizedCaseInsensitiveContains(token) { return true }
        }
        return false
    }

    public func artifactURL(forArch arch: String = "arm64", relativeTo manifest: URL) -> URL? {
        guard let file = artifact(forArch: arch) else { return nil }
        return URL(string: file.url, relativeTo: manifest.deletingLastPathComponent())?.absoluteURL
    }

    public static func parse(_ text: String) -> ElectronManifest? {
        var fields: [String: String] = [:]
        var files: [File] = []
        var pendingURL: String?
        var pendingSHA: String?

        func flush() {
            if let url = pendingURL { files.append(File(url: url, sha512: pendingSHA)) }
            pendingURL = nil
            pendingSHA = nil
        }

        for raw in text.split(separator: "\n") {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indented = line.hasPrefix(" ") || line.hasPrefix("-")

            if indented {
                // A `- url:` starts a new entry; `sha512:` under it belongs to that
                // entry. Anything else indented (size, blockMapSize) is ignored.
                if trimmed.hasPrefix("- url:") || trimmed.hasPrefix("url:") {
                    if trimmed.hasPrefix("- url:") { flush() }
                    pendingURL = value(of: trimmed)
                } else if trimmed.hasPrefix("sha512:") {
                    pendingSHA = value(of: trimmed)
                }
                continue
            }
            flush()
            guard !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard fields[key] == nil else { continue }  // first wins
            let v = value(of: line)
            if !v.isEmpty { fields[key] = v }
        }
        flush()

        guard let version = fields["version"] else { return nil }
        return ElectronManifest(
            version: version, path: fields["path"],
            sha512: fields["sha512"], releaseDate: fields["releaseDate"], files: files)
    }

    private static func value(of line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " '\"\r"))
    }
}
