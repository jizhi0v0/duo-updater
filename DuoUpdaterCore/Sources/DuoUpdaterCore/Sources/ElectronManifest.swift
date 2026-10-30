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

    /// Names the directory under `~/Library/Caches` where electron-updater parks
    /// what it has downloaded — the `pending/` layout `SelfUpdaterStash` reads.
    ///
    /// Not derivable from anything else we hold. electron-updater resolves the
    /// directory as `updaterCacheDirName ?? app.getName()`, and `getName()` is
    /// Electron's own app name (package.json `name`/`productName`), which is not
    /// the bundle's display name and is not readable from outside the process.
    /// The names this key carries have no shared shape to guess from either —
    /// `@opencode-aidesktop-updater`, `com.google.antigravity`, `QQ-updater`,
    /// `xyz.chatboxapp.app-updater`, `draw.io-updater` are all real values on one
    /// machine. So an absent key means "no stash lookup", never a guess: a guessed
    /// directory that happens to exist belongs to some OTHER app, and the bytes in
    /// it would be offered as this app's update.
    public let updaterCacheDirName: String?

    public init(
        provider: String, url: String?, owner: String?, repo: String?, channel: String,
        updaterCacheDirName: String? = nil
    ) {
        self.provider = provider
        self.url = url
        self.owner = owner
        self.repo = repo
        self.channel = channel
        self.updaterCacheDirName = updaterCacheDirName
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

    /// `manifestURL` as electron-updater actually requests it: with a throwaway
    /// `noCache` query on the end. Fetch with this; resolve artifacts against
    /// `manifestURL`.
    ///
    /// The query is what gets a request past a CDN's edge copy; none of the three
    /// request headers tried below substituted for it. electron-updater's `GenericProvider` builds the
    /// manifest address with `newUrlFromBase(…, isAddNoCacheQuery)`, which appends
    /// `noCache=<Date.now() in base 32>`, and `isAddNoCacheQuery` is true unless the
    /// app sends an `Authorization` / `PRIVATE-TOKEN` header (electron-builder
    /// `AppUpdater.ts`, issue #3021). So every check an electron-builder app makes
    /// on its own reaches the origin, and the vendor never has to keep its edge
    /// copies fresh.
    ///
    /// Measured 2026-09-11 on Kimi's `kimi-img.moonshot.cn/app/upgrade/latest-mac.yml`:
    /// the bare address answered `3.2.5` from an edge copy four and a half days old
    /// (`Age: 384307`), and `Cache-Control: no-cache`, `max-age=0` and
    /// `Pragma: no-cache` on the request all got that same copy; with the query it
    /// answered `3.2.7` from origin (`Age: 0`), the version Kimi's own updater
    /// reported as latest. Reading the bare address, this source called a 3.2.7
    /// install up to date against `3.2.5`, and would leave a 3.2.5 install with
    /// nothing to offer for as long as the edge copy lived.
    ///
    /// An address that already carries a query is returned untouched rather than
    /// having that query overwritten. That is NOT parity with electron-updater for
    /// such a config: it requests `<url>/latest-mac.yml?<the config's query>`, while
    /// `manifestURL`'s string concatenation puts the channel file inside the query
    /// (`…/feed?token=abc/latest-mac.yml`). A gap in `manifestURL` that predates
    /// this function and is left as it was.
    func manifestRequestURL(noCache token: String = Self.noCacheToken()) -> URL? {
        manifestURL.map { Self.noCacheURL(for: $0, token: token) }
    }

    /// `url` with electron-updater's `noCache` query added, or `url` itself when it
    /// already carries a query. The one spelling of that request: this source
    /// fetches with it, and `duo verify` uses it to ask a `*-mac.yml` recipe's
    /// endpoint whether the bare address is being answered from a stale edge copy
    /// (`RecipeSanity.readsElectronManifest`).
    public static func noCacheURL(for url: URL, token: String = noCacheToken()) -> URL {
        guard url.query == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.queryItems = [URLQueryItem(name: "noCache", value: token)]
        return components.url ?? url
    }

    /// electron-updater's token, `Date.now().toString(32)`: epoch milliseconds in
    /// base 32. Only its uniqueness matters to a CDN; the spelling is kept so the
    /// request looks like the app's own.
    public static func noCacheToken(now: Date = Date()) -> String {
        String(Int64((now.timeIntervalSince1970 * 1000).rounded(.down)), radix: 32)
    }

    /// Read the config a packaged Electron app carries, if it carries one.
    public static func read(fromBundleAt bundleURL: URL) -> ElectronUpdateConfig? {
        guard let text = try? String(
            contentsOf: bundleURL.appendingPathComponent("Contents/Resources/app-update.yml"),
            encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// `app-update.yml` is a flat map of scalars, so this reads it as one rather
    /// than pulling a YAML parser in for six keys. Values may be single-quoted
    /// (Notion writes `url: 'https://…'`), which is the only quoting the file uses.
    ///
    /// An empty value is dropped rather than stored: QQ ships `provider: generic`
    /// with `url: ''`, and keeping that would build the relative URL
    /// `/latest-mac.yml` — a thing `URL(string:)` accepts and no one can fetch.
    public static func parse(_ text: String) -> ElectronUpdateConfig? {
        var fields: [String: String] = [:]
        // `isNewline`, not a "\n" separator: electron-builder normally writes LF,
        // but a manifest generated on a Windows CI is CRLF, and splitting on "\n"
        // alone left the whole document as one "line" — `provider` then swallowed
        // the file and `url` came back nil. `\r\n` is a SINGLE Swift Character
        // whose `isNewline` is true, so this handles both without a normalisation
        // pass. See `ElectronManifest.parse` for the same fix and the worse bug it
        // prevents there.
        for raw in ElectronManifest.strippingBOM(text).split(whereSeparator: \.isNewline) {
            let line = ElectronManifest.strippingComment(String(raw))
            guard !line.hasPrefix(" "), !line.hasPrefix("#"),
                  let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard let value = ElectronManifest.scalarValue(
                String(line[line.index(after: colon)...])) else {
                continue
            }
            fields[key] = value
        }
        guard let provider = fields["provider"] else { return nil }
        return ElectronUpdateConfig(
            provider: provider, url: fields["url"],
            owner: fields["owner"], repo: fields["repo"],
            channel: fields["channel"] ?? "latest",
            updaterCacheDirName: fields["updaterCacheDirName"])
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
        /// Declared bytes. Carried so "Update All" can order the batch
        /// smallest-first — `InstallBatchOrdering` reads `RemoteVersion.downloadSize`,
        /// and a source that reports nil silently falls back to alphabetical.
        public let size: Int64?

        public init(url: String, sha512: String?, size: Int64? = nil) {
            self.url = url
            self.sha512 = sha512
            self.size = size
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
        // The top-level scalars carry no size of their own, so a `path` fallback
        // can only report one a `files:` entry naming the same url also declares.
        return File(url: path, sha512: sha512, size: files.first { $0.url == path }?.size)
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

    /// Read a `*-mac.yml` body.
    ///
    /// electron-builder writes a flat document and that is the common case, but the
    /// file is YAML and vendors do not all use its emitter. What this reader covers
    /// is the subset a manifest actually uses: quoted and unquoted scalars, block
    /// scalars, comments, YAML `null`, flow collections for `files:`, and scalar
    /// anchors/aliases. `logicalLines` does the line-level rewriting; this function
    /// only routes keys. It is not a general YAML parser on purpose — see there.
    public static func parse(_ text: String) -> ElectronManifest? {
        var fields: [String: String] = [:]
        var files: [File] = []
        var anchors: [String: String] = [:]
        var pendingURL: String?
        var pendingSHA: String?
        var pendingSize: Int64?

        func flush() {
            if let url = pendingURL, !url.isEmpty {
                files.append(File(url: url, sha512: pendingSHA, size: pendingSize))
            }
            pendingURL = nil
            pendingSHA = nil
            pendingSize = nil
        }

        for line in logicalLines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indented = line.hasPrefix(" ") || line.hasPrefix("-")

            if indented {
                // A `- url:` starts a new entry; `sha512:` under it belongs to that
                // entry. A flow mapping (`- {url: …, sha512: …}`) is one entry. Anything
                // else indented (blockMapSize, or a block scalar's own line) is ignored.
                if trimmed.hasPrefix("- {") || trimmed.hasPrefix("- &") || trimmed.hasPrefix("{") {
                    flush()
                    var entry = trimmed
                    if entry.hasPrefix("- ") { entry = String(entry.dropFirst(2)) }
                    entry = expandingAnchor(entry, anchors: &anchors)
                    if let file = flowFile(entry, anchors: &anchors) { files.append(file) }
                } else if trimmed.hasPrefix("- url:") || trimmed.hasPrefix("url:") {
                    if trimmed.hasPrefix("- url:") { flush() }
                    pendingURL = scalarValue(expandingAnchor(
                        rawValue(of: trimmed), anchors: &anchors))
                } else if trimmed.hasPrefix("sha512:") {
                    pendingSHA = scalarValue(expandingAnchor(
                        rawValue(of: trimmed), anchors: &anchors))
                } else if trimmed.hasPrefix("size:") {
                    pendingSize = scalarValue(expandingAnchor(
                        rawValue(of: trimmed), anchors: &anchors)).flatMap(Int64.init)
                }
                continue
            }
            flush()
            guard !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard fields[key] == nil else { continue }  // first wins
            let raw = expandingAnchor(rawValue(of: line), anchors: &anchors)
            if key == "files" {
                files.append(contentsOf: flowFiles(raw, anchors: &anchors))
                continue
            }
            if let v = scalarValue(raw) { fields[key] = v }
        }
        flush()

        guard let version = fields["version"] else { return nil }
        return ElectronManifest(
            version: version, path: fields["path"],
            sha512: fields["sha512"], releaseDate: fields["releaseDate"], files: files)
    }

    /// Everything after the first colon, untrimmed.
    private static func rawValue(of line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...])
    }

    /// A YAML scalar as a Swift string, or nil when it states nothing.
    ///
    /// Quoted forms are unwrapped (`Notion` writes `url: 'https://…'`), YAML's null
    /// spellings are absent rather than the strings `"null"` / `"~"`, and a stray
    /// quote at either end is trimmed, which is what this reader has always done for
    /// the one half-quoted value seen in the wild. Unsupported escapes are left
    /// alone: a URL that needs `\"` is not one we could install.
    static func scalarValue(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.count >= 2, let quote = value.first,
           quote == "'" || quote == "\"", value.last == quote {
            var inner = String(value.dropFirst().dropLast())
            if quote == "'" { inner = inner.replacingOccurrences(of: "''", with: "'") }
            return inner.isEmpty ? nil : inner
        }
        if value == "null" || value == "Null" || value == "NULL" || value == "~" { return nil }
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " '\"\r"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `&name value` registers the anchor and yields the value; `*name` resolves it.
    ///
    /// Scalars only. An alias to a whole mapping (`<<: *base`) is not something a
    /// generated manifest has been seen to use, and implementing merge keys would
    /// mean modelling the document rather than routing six fields.
    static func expandingAnchor(_ raw: String, anchors: inout [String: String]) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("&") {
            let body = value.dropFirst()
            let name = body.prefix { !$0.isWhitespace }
            guard !name.isEmpty else { return value }
            let rest = body.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            anchors[String(name)] = rest
            return rest
        }
        if value.hasPrefix("*") {
            let name = value.dropFirst().trimmingCharacters(in: .whitespaces)
            return anchors[name] ?? ""  // an unknown alias states nothing
        }
        return value
    }

    static func strippingBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// One YAML line with a comment removed, unless the `#` is inside quotes or is
    /// part of a token (`https://host/app#fragment`). A `#` only starts a comment at
    /// the beginning of a line or after whitespace, which is YAML's own rule.
    static func strippingComment(_ line: String) -> String {
        var result = ""
        result.reserveCapacity(line.count)
        var inSingle = false
        var inDouble = false
        var escaped = false
        var previous: Character = " "
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if inDouble {
                result.append(ch)
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inDouble = false }
            } else if inSingle {
                result.append(ch)
                if ch == "'" {
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "'" {
                        result.append("'")  // YAML's escaped single quote
                        index = next
                    } else {
                        inSingle = false
                    }
                }
            } else if ch == "#", previous == " " || previous == "\t" {
                break
            } else {
                if ch == "\"" { inDouble = true }
                else if ch == "'" { inSingle = true }
                result.append(ch)
            }
            previous = ch
            index = line.index(after: index)
        }
        return result
    }

    /// Net `[` / `{` depth of a line, ignoring brackets inside quoted text.
    static func flowDepth(_ line: String) -> Int {
        var depth = 0
        var inSingle = false
        var inDouble = false
        var escaped = false
        for ch in line {
            if inDouble {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inDouble = false }
                continue
            }
            if inSingle {
                if ch == "'" { inSingle = false }
                continue
            }
            switch ch {
            case "\"": inDouble = true
            case "'": inSingle = true
            case "[", "{": depth += 1
            case "]", "}": depth -= 1
            default: break
            }
        }
        return depth
    }

    /// A flow collection's items, split on the commas at its own depth. Quotes and
    /// nested `[]` / `{}` are respected, so a URL with a comma in a quoted scalar
    /// survives.
    static func flowItems(_ text: String) -> [String] {
        var items: [String] = []
        var current = ""
        var depth = 0
        var inSingle = false
        var inDouble = false
        var escaped = false
        for ch in text {
            if inDouble {
                current.append(ch)
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inDouble = false }
                continue
            }
            if inSingle {
                current.append(ch)
                if ch == "'" { inSingle = false }
                continue
            }
            switch ch {
            case "\"": inDouble = true; current.append(ch)
            case "'": inSingle = true; current.append(ch)
            case "[", "{": depth += 1; current.append(ch)
            case "]", "}": depth -= 1; current.append(ch)
            case "," where depth == 0: items.append(current); current = ""
            default: current.append(ch)
            }
        }
        items.append(current)
        return items
    }

    /// `files:` as a flow collection: `[{url: …, sha512: …}, …]`, a single `{…}`, or
    /// nothing. `expandingAnchor` first, so `files: &all [...]` works.
    static func flowFiles(_ raw: String, anchors: inout [String: String]) -> [File] {
        let value = expandingAnchor(raw, anchors: &anchors)
            .trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("{"), value.hasSuffix("}") {
            return flowFile(value, anchors: &anchors).map { [$0] } ?? []
        }
        guard value.hasPrefix("["), value.hasSuffix("]") else { return [] }
        let inner = String(value.dropFirst().dropLast())
        return flowItems(inner).compactMap { item in
            let entry = expandingAnchor(item, anchors: &anchors)
                .trimmingCharacters(in: .whitespaces)
            guard entry.hasPrefix("{"), entry.hasSuffix("}") else { return nil }
            return flowFile(entry, anchors: &anchors)
        }
    }

    /// One `{url: …, sha512: …, size: …}` flow mapping as a `File`.
    static func flowFile(_ raw: String, anchors: inout [String: String]) -> File? {
        let value = expandingAnchor(raw, anchors: &anchors)
            .trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("{"), value.hasSuffix("}") else { return nil }
        var fields: [String: String] = [:]
        for pair in flowItems(String(value.dropFirst().dropLast())) {
            guard let colon = pair.firstIndex(of: ":") else { continue }
            guard let key = scalarValue(String(pair[..<colon])) else { continue }
            let rawValue = expandingAnchor(
                String(pair[pair.index(after: colon)...]), anchors: &anchors)
            if let field = scalarValue(rawValue) { fields[key] = field }
        }
        guard let url = fields["url"], !url.isEmpty else { return nil }
        return File(url: url, sha512: fields["sha512"],
                    size: fields["size"].flatMap(Int64.init))
    }

    /// The manifest as logical lines: no BOM, no comments, flow collections joined
    /// onto one line, and every YAML block scalar folded onto its key.
    ///
    /// electron-builder writes each value on one line, but the file is YAML and a
    /// vendor is free to emit it differently. DeepSeek Harness's nightly feed is
    /// the case that found the block-scalar half: `url: >-` with the address on
    /// the next, indented line, and the same shape for `sha512` and `path`.
    /// Reading the text after the colon literally took the indicator `>-` as the
    /// address, resolved it to a URL (`%3E-`), and found no installer kind for it
    /// — so a release whose zip was right there was offered as detection-only,
    /// with `route: manual`.
    ///
    /// Deliberately not a general YAML parser. It handles the constructs a
    /// manifest uses — block scalars with either style and chomping/indentation
    /// indicators, comments, flow collections for `files:` — and leaves every
    /// other line as it was. A block scalar's own body is never comment-stripped
    /// or scanned for brackets, which is why that work happens here rather than in
    /// a pass over `text`.
    static func logicalLines(_ text: String) -> [String] {
        let lines = strippingBOM(text)
            .split(whereSeparator: \.isNewline).map(String.init)
        var result: [String] = []
        result.reserveCapacity(lines.count)
        var i = 0
        while i < lines.count {
            let stripped = strippingComment(lines[i])
            if let header = BlockScalarHeader(stripped) {
                // Content is every following line indented deeper than the key. Blank
                // lines belong to the scalar too, but trailing ones are chomped away.
                var body: [String] = []
                var bodyIndent: Int?
                var j = i + 1
                while j < lines.count {
                    let line = lines[j]
                    if line.allSatisfy({ $0.isWhitespace }) {
                        body.append("")
                        j += 1
                        continue
                    }
                    let indent = line.prefix(while: { $0 == " " }).count
                    if indent <= header.keyColumn { break }
                    // The first content line fixes the block's indentation; a line
                    // shallower than it ends the scalar too, even when it is still
                    // deeper than the key.
                    if let bodyIndent, indent < bodyIndent { break }
                    let common = bodyIndent ?? indent
                    bodyIndent = common
                    // Strip the block's own indentation; anything past it is content.
                    body.append(String(line.dropFirst(min(indent, common))))
                    j += 1
                }
                while body.last?.isEmpty == true { body.removeLast() }
                // Folded `>` turns the body's line breaks into spaces. These values
                // (a URL, a base64 digest, a path) are single-line by construction,
                // so blank lines inside one are not worth a paragraph rule.
                let value = header.isFolded
                    ? body.filter { !$0.isEmpty }.joined(separator: " ")
                    : body.joined(separator: "\n")
                result.append(header.prefix + value)
                i = j
                continue
            }
            // A flow collection may span lines (`files: [` … `]`). Join until its
            // brackets close; every fragment is comment-stripped first so a `#`
            // inside the collection cannot unbalance it.
            var depth = flowDepth(stripped)
            if depth > 0 {
                var joined = stripped.trimmingCharacters(in: .whitespaces)
                var j = i + 1
                while j < lines.count, depth > 0 {
                    let fragment = strippingComment(lines[j])
                        .trimmingCharacters(in: .whitespaces)
                    if !fragment.isEmpty { joined += " " + fragment }
                    depth += flowDepth(fragment)
                    j += 1
                }
                result.append(joined)
                i = j
                continue
            }
            result.append(stripped)
            i += 1
        }
        return result
    }

    /// `key: >-` and the spellings around it, including a comment after the
    /// indicator and YAML's optional explicit indentation (`>2-`, `|-2`). The digit
    /// only has to be accepted, not applied: the body's own first line already
    /// fixes the indentation this reader strips.
    private struct BlockScalarHeader {
        /// Everything through the colon and one space, with the line's own
        /// indentation and `- url:` marker kept verbatim.
        let prefix: String
        /// The column the key starts in. The scalar's body must be indented
        /// deeper than this and ends at the first line that is not — which is
        /// what keeps a sibling `sha512:` from being swallowed into the `url`.
        let keyColumn: Int
        /// `>` folds the body's newlines into spaces; `|` keeps them.
        let isFolded: Bool

        init?(_ line: String) {
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
                  let colon = line.firstIndex(of: ":") else { return nil }
            let indicator = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            guard let folded = Self.style(of: indicator) else { return nil }
            isFolded = folded
            // The key starts after the indentation and the sequence marker.
            var keyStart = line.startIndex
            while keyStart < line.endIndex, line[keyStart] == " " || line[keyStart] == "-" {
                keyStart = line.index(after: keyStart)
            }
            guard keyStart < colon else { return nil }
            keyColumn = line.distance(from: line.startIndex, to: keyStart)
            prefix = String(line[...colon]) + " "
        }

        /// `>` or `|`, then at most one indentation digit and one chomping sign in
        /// either order, and nothing else. Returns whether the style folds.
        private static func style(of indicator: String) -> Bool? {
            guard let first = indicator.first, first == ">" || first == "|" else {
                return nil
            }
            let rest = indicator.dropFirst()
            let digits = rest.filter { $0.isNumber }
            let signs = rest.filter { $0 == "-" || $0 == "+" }
            guard rest.count <= 2,
                  digits.count <= 1, signs.count <= 1,
                  rest.count == digits.count + signs.count,
                  digits.allSatisfy({ ("1"..."9").contains($0) })
            else { return nil }
            return first == ">"
        }
    }
}
