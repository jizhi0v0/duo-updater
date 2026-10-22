import Foundation

/// Fetches and keeps what `RuntimeSecurityRules` reads: nodejs.org's release
/// index, nodejs/Release's schedule, php.net's branches and php-src's GitHub
/// security advisories.
///
/// Each source is asked at most once a day, and conditionally (`ETag` /
/// `Last-Modified` from its last 200). A copy is spoken from for 48 hours after
/// it was last confirmed — a 200, or a 304 to it — and not after: past that,
/// or with no copy at all, that source gives no notices, so a failed fetch
/// never turns into a stale verdict. Only the sources an install needs are
/// asked: a Mac without PHP never reaches GitHub for its advisories.
///
/// The advisories go through the app's GitHub plumbing: the token chain
/// (`ChangelogService.gitHubToken`), `countedData` (the rate-limit gate, the
/// rejected-token retry, `GitHubAPIMock`), and `GitHubConditionalCache`'s
/// credential fingerprint and conditional headers, so a 304 to an
/// authenticated request costs no quota. Not that cache's storage: its entries
/// expire after a day — the cadence here, so every validator would have
/// expired by the next ask — and `GitHubReleasesSource` prunes it to the
/// registry's endpoints. The validators and raw bodies live in this store's
/// own file instead, beside it in `DuoStateDirectory`, shared by the app and
/// `duo`.
public actor RuntimeSecurityFeeds {

    public static let shared = RuntimeSecurityFeeds()

    enum Source: String, Codable, CaseIterable, Sendable {
        case nodeReleases
        case nodeSchedule
        case phpBranches
        case phpAdvisories

        var url: URL {
            switch self {
            case .nodeReleases: URL(string: "https://nodejs.org/dist/index.json")!
            case .nodeSchedule: URL(string: "https://raw.githubusercontent.com/nodejs/Release/main/schedule.json")!
            case .phpBranches: URL(string: "https://www.php.net/releases/branches.php")!
            case .phpAdvisories: URL(string: "https://api.github.com/repos/php/php-src/security-advisories?per_page=100")!
            }
        }

        /// Whether `pages` are this source's data — a 200 that isn't is a failure.
        func parses(_ pages: [Data]) -> Bool {
            switch self {
            case .nodeReleases: pages.count == 1 && NodeReleaseIndex(json: pages[0]) != nil
            case .nodeSchedule: pages.count == 1 && NodeReleaseSchedule(json: pages[0]) != nil
            case .phpBranches: pages.count == 1 && PHPBranches(json: pages[0]) != nil
            case .phpAdvisories: !pages.isEmpty && PHPAdvisories(pages: pages) != nil
            }
        }
    }

    /// One source's last good copy: its raw body (each page, for the
    /// advisories), validators, and when it was last confirmed and last asked.
    struct Entry: Codable, Sendable, Equatable {
        var pages: [Data] = []
        var etag: String?
        var lastModified: String?
        /// `GitHubConditionalCache.authFingerprint` of the credential the copy
        /// was fetched with; its validators are sent only under the same one.
        var authFingerprint: String?
        /// The last 200, or 304 to this copy.
        var confirmedAt: Date?
        /// The last request, answered or not.
        var askedAt: Date?
    }

    /// How long after the last ask a source is asked again.
    static let askInterval: TimeInterval = 24 * 60 * 60
    /// How long after it was last confirmed a copy is spoken from.
    static let maxAge: TimeInterval = 48 * 60 * 60
    /// Pages of advisories followed at most; php-src had 66 advisories on one
    /// page of 100 on 2026-10-22.
    static let maxPages = 10

    private let fileURL: URL
    private let session: URLSession
    private let token: @Sendable () async -> String?
    private let now: @Sendable () -> Date
    private var entries: [Source: Entry]?
    private var inFlight: [Source: Task<Void, Never>] = [:]

    init(
        fileURL: URL? = nil,
        session: URLSession = .updates,
        token: @escaping @Sendable () async -> String? = { await ChangelogService.gitHubToken() },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileURL = fileURL ?? DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("runtime-security-feeds.json")
        self.session = session
        self.token = token
        self.now = now
    }

    /// The notices for what is installed under `home` and `brewRoot` now,
    /// asking each needed source first if its day is up.
    public func report(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        brewRoot: URL? = RuntimeInstall.defaultBrewRoot
    ) async -> RuntimeSecurityReport {
        await report(for: RuntimeInstall.installed(home: home, brewRoot: brewRoot))
    }

    public func report(for installs: [RuntimeInstall]) async -> RuntimeSecurityReport {
        var needed: [Source] = []
        if installs.contains(where: { $0.kind == .node }) { needed += [.nodeReleases, .nodeSchedule] }
        if installs.contains(where: { $0.kind == .php }) { needed += [.phpBranches, .phpAdvisories] }
        guard !needed.isEmpty else { return RuntimeSecurityReport() }
        return RuntimeSecurityReport(installs: installs, data: await data(needed), today: Self.day(now()))
    }

    /// `sources`' data, each asked first when due; nil for one without a copy
    /// confirmed in the last `maxAge`.
    func data(_ sources: [Source]) async -> RuntimeSecurityData {
        await withTaskGroup(of: Void.self) { group in
            for source in sources { group.addTask { await self.refreshIfDue(source) } }
        }
        let current = now()
        func pages(_ source: Source) -> [Data]? {
            guard let entry = loadedEntries()[source], let confirmed = entry.confirmedAt,
                  current.timeIntervalSince(confirmed) <= Self.maxAge, !entry.pages.isEmpty
            else { return nil }
            return entry.pages
        }
        return RuntimeSecurityData(
            nodeReleases: pages(.nodeReleases).flatMap { NodeReleaseIndex(json: $0[0]) },
            nodeSchedule: pages(.nodeSchedule).flatMap { NodeReleaseSchedule(json: $0[0]) },
            phpBranches: pages(.phpBranches).flatMap { PHPBranches(json: $0[0]) },
            phpAdvisories: pages(.phpAdvisories).flatMap { PHPAdvisories(pages: $0) })
    }

    /// Ask `source` unless it was asked in the last `askInterval`; one ask at a
    /// time per source.
    private func refreshIfDue(_ source: Source) async {
        if let running = inFlight[source] { return await running.value }
        if let asked = loadedEntries()[source]?.askedAt, now().timeIntervalSince(asked) < Self.askInterval { return }
        let task = Task { await self.refresh(source) }
        inFlight[source] = task
        await task.value
        inFlight[source] = nil
    }

    private func refresh(_ source: Source) async {
        var entry = loadedEntries()[source] ?? Entry()
        let token = source == .phpAdvisories ? await token() : nil
        let fingerprint = GitHubConditionalCache.authFingerprint(token)
        var request = URLRequest(url: source.url, timeoutInterval: 20)
        // This store is the validator: `URLCache` would add its own, or answer
        // from a copy php.net let it keep for 30 days (`max-age=2592000`).
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if source == .phpAdvisories {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        }
        if !entry.pages.isEmpty, source != .phpAdvisories || entry.authFingerprint == fingerprint {
            let validator = GitHubConditionalCache.Validator(
                etag: entry.etag, lastModified: entry.lastModified, body: entry.pages[0])
            for (name, value) in validator.conditionalHeaders { request.setValue(value, forHTTPHeaderField: name) }
        }
        let asked = now()
        do {
            let (data, response) = try await session.countedData(for: request, purpose: .catalog)
            entry.askedAt = asked
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 304, !entry.pages.isEmpty {
                entry.confirmedAt = asked
            } else if http.statusCode == 200 {
                var pages = [data]
                var next = Self.nextPage(http)
                while let url = next, source == .phpAdvisories, pages.count < Self.maxPages {
                    var page = request
                    page.url = url
                    for name in GitHubConditionalCache.Validator.headerNames { page.setValue(nil, forHTTPHeaderField: name) }
                    let (more, moreResponse) = try await session.countedData(for: page, purpose: .catalog)
                    guard let moreHTTP = moreResponse as? HTTPURLResponse, moreHTTP.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    pages.append(more)
                    next = Self.nextPage(moreHTTP)
                }
                // More pages than followed: a partial list is not the list.
                guard next == nil || source != .phpAdvisories, source.parses(pages) else {
                    throw URLError(.cannotParseResponse)
                }
                entry = Entry(
                    pages: pages.map { Data(Array($0)) },
                    etag: http.value(forHTTPHeaderField: "ETag"),
                    lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                    authFingerprint: fingerprint, confirmedAt: asked, askedAt: asked)
            } else {
                Log.source.notice("runtime-security: \(source.rawValue, privacy: .public) answered HTTP \(http.statusCode, privacy: .public)")
            }
        } catch {
            // Held back by the rate-limit gate: nothing was sent, so this is
            // not the day's ask.
            if !GitHubRateLimitGate.isRefusal(error) { entry.askedAt = asked }
            Log.source.notice("runtime-security: \(source.rawValue, privacy: .public) failed — \(error.localizedDescription, privacy: .public)")
        }
        entries?[source] = entry
        write()
    }

    /// The `rel="next"` URL of a GitHub `Link` header.
    static func nextPage(_ response: HTTPURLResponse) -> URL? {
        guard let link = response.value(forHTTPHeaderField: "Link") else { return nil }
        for part in link.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces.dropFirst().contains("rel=\"next\""),
                  pieces[0].hasPrefix("<"), pieces[0].hasSuffix(">"),
                  let url = URL(string: String(pieces[0].dropFirst().dropLast())),
                  url.scheme == "https", url.host == "api.github.com"
            else { continue }
            return url
        }
        return nil
    }

    private func loadedEntries() -> [Source: Entry] {
        if let entries { return entries }
        // A corrupt or missing file is an empty store: every source is asked.
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        let decoded = Dictionary(uniqueKeysWithValues: loaded.compactMap { key, value in
            Source(rawValue: key).map { ($0, value) }
        })
        entries = decoded
        return decoded
    }

    private func write() {
        let encodable = Dictionary(uniqueKeysWithValues: (entries ?? [:]).map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.source.error("runtime-security: could not write \(self.fileURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `yyyy-MM-dd` in the user's calendar day, like `BrewLifecycle`'s dates.
    static func day(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
