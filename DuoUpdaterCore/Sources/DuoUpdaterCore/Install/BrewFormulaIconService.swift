import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An installed formula's own icon, fetched from where the project itself
/// publishes one, for the Brew rows of formulae the app bundles no logo for.
///
/// Where it looks, in order, never anywhere else:
/// - a formula whose homepage is on GitHub (`github.com/<owner>/…` or
///   `<owner>.github.io`): the owner's avatar, when the owner is an
///   organisation, whose avatar is usually its logo. A person's avatar is a
///   photo of them (10 of 28 icons on the author's machine, 2026-10-08), so a
///   formula owned by a person keeps the Homebrew logo;
/// - any other homepage: the page's own `apple-touch-icon` / `icon` links,
///   largest first, then the site's `/favicon.ico` — only those on the
///   homepage's own host or its subdomains (``SameSite``). A link to a CDN or
///   another host is dropped, and these requests do not follow a redirect off
///   the site.
///
/// So every request goes to the formula's own site or to GitHub (the owner
/// lookup is `api.github.com/users/<owner>`), as the
/// README's Privacy section says; no icon service or CDN learns what is
/// installed. The homepage comes from `brew info --installed`, read locally.
///
/// Lazy: the UI asks when a row appears. Results are cached on disk as small
/// PNGs; a formula with nothing usable is remembered as a miss for
/// ``missLifetime`` so a closed or icon-less site is not asked on every launch.
public actor BrewFormulaIconService {
    public static let shared = BrewFormulaIconService()

    private let session: URLSession
    private let directory: URL
    private let brewPath: @Sendable () -> String?

    /// Homepages of every installed formula, from one `brew info --installed`
    /// (about a second for 180 formulae, measured 2026-10-08), so a screenful of
    /// rows costs one subprocess, not one each. Read once per launch.
    private var homepages: Task<[String: URL], Never>?
    private var inflight: [String: Task<Data?, Never>] = [:]

    /// Fetches at once. Rows appear a screenful at a time and each can mean two
    /// or three requests to a different site; this keeps that from bursting.
    private static let concurrentFetches = 4
    private var freeSlots = BrewFormulaIconService.concurrentFetches
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// How long a formula with no usable icon is left alone before asking again.
    static let missLifetime: TimeInterval = 7 * 24 * 3600
    /// Stored size: the 44 pt detail header at a Retina display's 2x scale.
    static let storedPixelSize = 128
    /// Smaller than this is a 16 px favicon blown up to a blur; not worth drawing.
    static let minimumPixelSize = 32
    /// The page head is where the icon links are; nothing past this is read.
    static let htmlByteLimit = 256 * 1024
    /// An icon larger than this is not an icon.
    static let iconByteLimit = 1024 * 1024

    public init(session: URLSession = .updates, cacheDirectory: URL? = nil) {
        self.init(session: session, cacheDirectory: cacheDirectory, brewPath: HomebrewInstaller.brewPath)
    }

    /// `brewPath` is a test seam.
    init(
        session: URLSession,
        cacheDirectory: URL?,
        brewPath: @escaping @Sendable () -> String?
    ) {
        self.session = session
        self.brewPath = brewPath
        self.directory = cacheDirectory ?? DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("formula-icons", isDirectory: true)
    }

    /// PNG bytes of `formula`'s icon, or nil when it has none we can use.
    public func icon(forFormula formula: String) async -> Data? {
        let token = formula.filesystemSafeToken
        let png = directory.appendingPathComponent(token + ".png")
        let miss = directory.appendingPathComponent(token + ".miss")
        if let cached = try? Data(contentsOf: png) { return cached }
        // FileManager, not `URL.resourceValues`: those are cached on the URL value.
        if let written = (try? FileManager.default.attributesOfItem(atPath: miss.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(written) < Self.missLifetime {
            return nil
        }
        if let task = inflight[formula] { return await task.value }

        let task = Task<Data?, Never> {
            guard let homepage = await homepage(of: formula) else { return nil }
            await acquireSlot()
            // Filed against the formula, so the request log's App column names it.
            let outcome = await RequestAttribution.withApp(Self.attributionID(formula, brewPath: brewPath())) {
                await fetchIcon(homepage: homepage)
            }
            releaseSlot()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            switch outcome {
            case .found(let icon):
                try? icon.write(to: png, options: .atomic)
                try? FileManager.default.removeItem(at: miss)
                return icon
            case .none:
                try? Data().write(to: miss, options: .atomic)
                return nil
            case .unknown:
                // GitHub didn't answer who the owner is (rate limit, offline):
                // asked again next launch rather than remembered as a miss.
                return nil
            }
        }
        inflight[formula] = task
        let result = await task.value
        if inflight[formula] == task { inflight[formula] = nil }
        return result
    }

    // MARK: - Fetching

    private enum Outcome { case found(Data), none, unknown }

    private func fetchIcon(homepage: URL) async -> Outcome {
        if let owner = Self.githubOwner(ofHomepage: homepage) {
            switch await organizationAvatar(owner) {
            case nil: return .unknown
            case .some(nil): return .none
            case .some(let avatar?): return await download(avatar)
            }
        }
        if Self.isSharedHost(homepage) { return .none }
        guard let (candidates, pageAnswered) = await candidates(for: homepage) else { return .unknown }
        var transient = !pageAnswered
        for candidate in candidates.prefix(4) {
            switch await download(candidate) {
            case .found(let icon): return .found(icon)
            case .unknown: transient = true
            case .none: continue
            }
        }
        // A miss is remembered only when every site answered; a timeout or a
        // 5xx is asked again next launch (gnu.org took 2.4–3.6 s a page on
        // 2026-10-08 and a queued batch lost three GNU formulae to it).
        return transient ? .unknown : .none
    }

    /// The avatar of a GitHub login that is an organisation; `.some(nil)` for a
    /// person or a login that doesn't exist, nil when GitHub didn't say.
    ///
    /// The API's `avatar_url`, not `avatars.githubusercontent.com/<login>`: that
    /// by-login address answered `apple` and `esnet` with the same placeholder
    /// image (one ETag, 2026-10-08), while their `avatar_url`s are their logos.
    private func organizationAvatar(_ owner: String) async -> URL?? {
        guard let url = URL(string: "https://api.github.com/users/\(owner)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token = await ChangelogService.gitHubToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await session.countedData(for: request, purpose: .packageIcon),
              let http = response as? HTTPURLResponse
        else { return nil }
        if http.statusCode == 404 { return .some(nil) }
        guard (200..<300).contains(http.statusCode) else { return nil }
        return .some(Self.organizationAvatar(fromUser: data))
    }

    /// The page's icon links and whether the page itself answered; nil when the
    /// homepage can't be asked at all.
    private func candidates(for homepage: URL) async -> (urls: [URL], pageAnswered: Bool)? {
        guard let page = Self.secure(homepage) else { return ([], true) }
        let favicon = Self.faviconFallback(page).map { [$0] } ?? []
        var request = URLRequest(url: page)
        request.timeoutInterval = 15
        guard let (bytes, response) = try? await session.countedBytes(
                for: SameSite.confine(request), purpose: .packageIcon),
              let http = response as? HTTPURLResponse
        else { return (favicon, false) }
        // Left unread, a non-2xx body is still recorded, as is a page cut off at
        // `htmlByteLimit`: `countedBytes` settles a stream released before its end.
        guard (200..<300).contains(http.statusCode) else {
            return (favicon, !Self.isTransient(status: http.statusCode))
        }
        var head = Data()
        do {
            for try await byte in bytes {
                head.append(byte)
                if head.count >= Self.htmlByteLimit { break }
            }
        } catch {}
        // Relative links resolve against where the page actually came from.
        let base = http.url ?? page
        return (Self.iconCandidates(inHTML: String(decoding: head, as: UTF8.self), base: base), true)
    }

    /// Confined: neither a site's icon nor a GitHub avatar is followed off its host.
    private func download(_ url: URL) async -> Outcome {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request = SameSite.confine(request)
        guard let (data, response) = try? await session.countedData(for: request, purpose: .packageIcon),
              let http = response as? HTTPURLResponse
        else { return .unknown }
        guard (200..<300).contains(http.statusCode) else {
            return Self.isTransient(status: http.statusCode) ? .unknown : .none
        }
        guard data.count <= Self.iconByteLimit, let icon = Self.normalizedIcon(data) else { return .none }
        return .found(icon)
    }

    /// A status worth asking again: rate limited or the server's own failure.
    static func isTransient(status: Int) -> Bool { status == 429 || status >= 500 }

    private func acquireSlot() async {
        if freeSlots > 0 { freeSlots -= 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func releaseSlot() {
        if waiting.isEmpty { freeSlots += 1 } else { waiting.removeFirst().resume() }
    }

    // MARK: - Homepages (local)

    private func homepage(of formula: String) async -> URL? {
        if homepages == nil {
            let brewPath = brewPath
            homepages = Task { await Self.installedHomepages(brewPath: brewPath) }
        }
        return await homepages?.value[formula]
    }

    /// `name` and `full_name` → `homepage` for every installed formula.
    static func installedHomepages(brewPath: @Sendable () -> String?) async -> [String: URL] {
        guard let brew = brewPath() else { return [:] }
        var env = ProcessInfo.processInfo.environmentWithSystemProxy
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        guard let outcome = try? await ChildProcess.run(
                brew, ["info", "--json=v2", "--installed"], environment: env,
                standardError: .discard, onCancel: .runToCompletion),
              outcome.succeeded
        else { return [:] }
        return parseHomepages(outcome.standardOutput)
    }

    static func parseHomepages(_ data: Data) -> [String: URL] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]]
        else { return [:] }
        var result: [String: URL] = [:]
        for formula in formulae {
            guard let raw = formula["homepage"] as? String, let url = URL(string: raw) else { continue }
            for key in ["name", "full_name"] {
                if let name = formula[key] as? String { result[name] = url }
            }
        }
        return result
    }

    // MARK: - Pure rules

    /// The formula's `opt` path (`/opt/homebrew/opt/automake`), its stand-in for
    /// an app bundle path in request attribution: what every request made for a
    /// formula (its icon, its release notes) is filed under.
    public static func attributionID(forFormula formula: String) -> String? {
        attributionID(formula, brewPath: HomebrewInstaller.brewPath())
    }

    /// `attributionID(forFormula:)` against a given `brew`. A tap's prefix is dropped.
    static func attributionID(_ formula: String, brewPath: String?) -> String? {
        guard let brewPath else { return nil }
        let short = formula.split(separator: "/").last.map(String.init) ?? formula
        return URL(fileURLWithPath: brewPath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("opt").appendingPathComponent(short).path
    }

    /// The GitHub login a homepage on `github.com/<owner>/…` or
    /// `<owner>.github.io` belongs to, else nil.
    static func githubOwner(ofHomepage homepage: URL) -> String? {
        guard let host = homepage.host?.lowercased() else { return nil }
        let owner: String?
        if host == "github.com" || host == "www.github.com" {
            owner = homepage.pathComponents.dropFirst().first
        } else if host.hasSuffix(".github.io") {
            owner = String(host.dropLast(".github.io".count))
        } else {
            owner = nil
        }
        // GitHub logins: letters, digits and single hyphens.
        guard let owner, !owner.isEmpty,
              owner.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        return owner
    }

    /// From a `GET /users/<login>` body: the avatar, sized for storage, when the
    /// login is an organisation over HTTPS; nil for a person.
    static func organizationAvatar(fromUser data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "Organization",
              let raw = object["avatar_url"] as? String,
              var parts = URLComponents(string: raw), parts.scheme == "https"
        else { return nil }
        parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "s" }
            + [URLQueryItem(name: "s", value: String(storedPixelSize))]
        return parts.url
    }

    /// Hosts that serve many projects' pages under their own icon: a homepage
    /// there would show SourceForge's flame for iperf (seen 2026-10-08), not
    /// iperf's. GitHub is handled apart, through the owner.
    static let sharedHosts: Set<String> = [
        "sourceforge.net", "gitlab.com", "codeberg.org", "bitbucket.org",
        "launchpad.net", "sr.ht", "savannah.gnu.org", "savannah.nongnu.org",
        "pypi.org", "crates.io", "www.npmjs.com", "npmjs.com", "hackage.haskell.org",
    ]

    static func isSharedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return sharedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// `url` over HTTPS: an `http` homepage is asked for its HTTPS twin, since
    /// App Transport Security refuses cleartext anyway. nil for anything else.
    static func secure(_ url: URL) -> URL? {
        switch url.scheme?.lowercased() {
        case "https": return url
        case "http":
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.scheme = "https"
            return parts?.url
        default: return nil
        }
    }

    static func faviconFallback(_ page: URL) -> URL? {
        URL(string: "/favicon.ico", relativeTo: page)?.absoluteURL
    }

    /// The page's icon links on `base`'s own site, best first, then
    /// `/favicon.ico`; a link to another host (a CDN, an icon service) is
    /// dropped, so asking for it can't tell that host what is installed. Best is largest:
    /// an `apple-touch-icon` is 180 px unless it says otherwise, an `icon` with
    /// no `sizes` is taken as 32 px. SVG and `mask-icon` links are skipped: the
    /// one is not decodable here, the other is a single-colour stencil.
    static func iconCandidates(inHTML html: String, base: URL) -> [URL] {
        var scored: [(url: URL, size: Int)] = []
        let linkTag = try! NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..., in: html)
        for match in linkTag.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let attributes = parseAttributes(String(html[tagRange]))
            guard let rel = attributes["rel"]?.lowercased(),
                  let href = attributes["href"], !href.isEmpty
            else { continue }
            let rels = Set(rel.split(whereSeparator: \.isWhitespace).map(String.init))
            let isTouch = rels.contains("apple-touch-icon") || rels.contains("apple-touch-icon-precomposed")
            guard isTouch || rels.contains("icon") else { continue }
            if attributes["type"]?.lowercased() == "image/svg+xml" { continue }
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  let secure = secure(url),
                  SameSite.matches(secure, base),
                  !secure.path.lowercased().hasSuffix(".svg")
            else { continue }
            let declared = attributes["sizes"].flatMap(largestDeclaredSize)
            scored.append((secure, declared ?? (isTouch ? 180 : 32)))
        }
        // Stable: equal sizes keep the page's order.
        var ordered = scored.enumerated()
            .sorted { $0.element.size != $1.element.size ? $0.element.size > $1.element.size : $0.offset < $1.offset }
            .map(\.element.url)
        if let favicon = faviconFallback(base).flatMap(secure), !ordered.contains(favicon) {
            ordered.append(favicon)
        }
        var seen = Set<URL>()
        return ordered.filter { seen.insert($0).inserted }
    }

    /// `sizes="16x16 32x32"` → 32.
    static func largestDeclaredSize(_ sizes: String) -> Int? {
        sizes.lowercased().split(whereSeparator: \.isWhitespace)
            .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }
            .max()
    }

    /// The attributes of one tag, names lowercased, values unquoted.
    static func parseAttributes(_ tag: String) -> [String: String] {
        let attribute = try! NSRegularExpression(
            pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#)
        var result: [String: String] = [:]
        for match in attribute.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let name = Range(match.range(at: 1), in: tag) else { continue }
            let value = (2...4).lazy.compactMap { Range(match.range(at: $0), in: tag) }.first
            result[tag[name].lowercased()] = value.map { String(tag[$0]) } ?? ""
        }
        return result
    }

    /// `data` as a PNG no larger than ``storedPixelSize``, from its largest frame
    /// (an `.ico` holds several sizes); nil when it doesn't decode or is smaller
    /// than ``minimumPixelSize``.
    static func normalizedIcon(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var best: (index: Int, size: Int)?
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int
            else { continue }
            let size = min(width, height)
            if size > (best?.size ?? 0) { best = (index, size) }
        }
        guard let best, best.size >= minimumPixelSize else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(best.size, storedPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, best.index, options as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
