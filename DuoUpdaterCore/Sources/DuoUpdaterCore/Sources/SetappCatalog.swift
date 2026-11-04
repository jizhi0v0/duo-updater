import Foundation

/// One app in Setapp's own catalogue, at the release that channel currently ships.
///
/// **Why this exists.** A Setapp build of an app is not the app the vendor's own
/// feed describes. It carries a `-setapp` bundle identifier (Setapp requires the
/// suffix — docs.setapp.com/docs/set-an-app-bundle-id) and it ships WITHOUT
/// Sparkle: the 1.40.1 AlDente Pro from Setapp has no `Sparkle.framework` and no
/// `SPUUpdater` symbols, while the direct 1.40.1 build has 42 of them. Its
/// `SUFeedURL` is still the vendor's direct feed — dead configuration nothing in
/// the bundle reads, and the one thing `SparkleAppcastSource` DOES read. That is
/// how a Setapp copy came to be offered the vendor's direct DMG and refused at
/// gate 4 with "Bundle identifier mismatch: installed …-setapp vs downloaded
/// …aldente-pro".
///
/// The channel's real answer is Setapp's own catalogue, which the client itself
/// reads at `https://store.setapp.com/store/api/v8/en`. Measured 2026-11-03: a
/// PUBLIC endpoint, no `Authorization` header, JSON:API, ~3 MB, and every app
/// carries its `versions` relationship with `marketing_version`, `build_number`,
/// `release_date`, `min_os_version` and `public_id` (the uuid the client's
/// `setapp://install?app_id=…` deep link takes; the numeric `ZIDENTIFIER` in the
/// client's CoreData store is NOT that id).
public struct SetappVersion: Sendable, Equatable {
    public let shortVersion: String?
    public let build: String?
    public let releaseDate: Date?
    public let minimumSystemVersion: String?
    /// The catalogue's `beta` flag. Only the beta channel carries one (measured
    /// 2026-11-04: 15 of 1076 versions on `/store/api/v8/beta/en`, none on
    /// `/store/api/v8/en`).
    public let isBeta: Bool

    public init(
        shortVersion: String?, build: String?, releaseDate: Date?,
        minimumSystemVersion: String?, isBeta: Bool = false
    ) {
        self.shortVersion = shortVersion
        self.build = build
        self.releaseDate = releaseDate
        self.minimumSystemVersion = minimumSystemVersion
        self.isBeta = isBeta
    }
}

public struct SetappRelease: Sendable, Equatable {
    /// The Setapp edition's signed bundle identifier — always `…-setapp` for an
    /// app Setapp publishes, because Setapp mandates the suffix.
    public let bundleID: String
    public let name: String
    /// The uuid Setapp's deep links address this app by.
    public let publicID: String
    /// Every release the channel publishes for this app, newest first. More than
    /// one matters because Setapp keeps an older branch alive for older macOS:
    /// the newest row can be a major that needs a newer system than this Mac runs.
    public let versions: [SetappVersion]
    /// The human page for this app, when the catalogue names a slug.
    public let pageURL: URL?

    /// The newest release, whatever it requires. For display and for tests; the
    /// source asks `newestCompatible(osVersion:)` before offering anything.
    public var newest: SetappVersion? { versions.first }
    public var shortVersion: String? { newest?.shortVersion }
    public var build: String? { newest?.build }
    public var releaseDate: Date? { newest?.releaseDate }
    public var minimumSystemVersion: String? { newest?.minimumSystemVersion }

    public init(
        bundleID: String, name: String, publicID: String,
        versions: [SetappVersion], pageURL: URL?
    ) {
        self.bundleID = bundleID
        self.name = name
        self.publicID = publicID
        self.versions = versions
        self.pageURL = pageURL
    }

    /// The newest release this Mac can run, by the same OS-window predicate every
    /// other source uses (`OSWindowRefusal`, whose floor is
    /// `SignatureVerifier.canRun` — #640). nil when no published release runs here.
    ///
    /// "Newest" is the VERSION, not the publication date: a maintenance release
    /// on an older branch can be published after a newer major (1.9.1 after 2.1),
    /// and taking the first row by date would shadow the major for a Mac that can
    /// run both. Date is only the tie-break.
    public func newestCompatible(osVersion: String) -> SetappVersion? {
        let compatible = versions.filter { version in
            OSWindowRefusal.evaluate(
                minimum: version.minimumSystemVersion, maximum: nil,
                osVersion: osVersion,
                version: version.shortVersion ?? version.build ?? "") == nil
        }
        return compatible.max { Self.isOlder($0, than: $1) }
    }

    /// Version first (marketing, then build), publication date as the tie-break.
    static func isOlder(_ lhs: SetappVersion, than rhs: SetappVersion) -> Bool {
        if let left = lhs.shortVersion, let right = rhs.shortVersion {
            let order = VersionComparator.compare(left, right)
            if order != .orderedSame { return order == .orderedAscending }
        }
        if let left = lhs.build, let right = rhs.build {
            let order = VersionComparator.compare(left, right)
            if order != .orderedSame { return order == .orderedAscending }
        }
        return (lhs.releaseDate ?? .distantPast) < (rhs.releaseDate ?? .distantPast)
    }
}

/// Reads Setapp's public catalogue: the channel's answer to "which version does
/// Setapp ship for this app right now".
///
/// Deliberately independent of whether the Setapp client is running. The client
/// only refreshes the catalogue when IT checks — measured 2026-11-03: with Setapp
/// quit, a relabelled 1.39.4 copy sat untouched for six minutes and no update
/// check was logged; relaunching the client triggered one at once — so the local
/// CoreData copy (`Apps.sqlite`) is exactly as fresh as the last time the user
/// opened Setapp. This endpoint is not.
public enum SetappCatalog {

    /// Which catalogue to read. The beta one is public and unauthenticated —
    /// measured 2026-11-04: `GET /store/api/v8/beta/en` with only the JSON:API
    /// `Accept` header returns 3.06 MB and 15 versions flagged `beta: true`
    /// (Bartender 7.1.0/700013 among them), the same rows the client showed after
    /// its beta switch went on.
    ///
    /// **Not a superset.** Measured the same day against `/store/api/v8/en`:
    /// 1074 versions stable against 1076 beta — 14 beta-only rows, but also **12
    /// stable-only** rows. For an app with a beta, the beta catalogue lists the
    /// beta INSTEAD of that app's current stable row (WiFi Signal 4.4.8 → 4.4.9
    /// beta, Dropshare 6.15 → 6.16 beta, KeyKey 3.0 → 3.0.3 beta). So a stable
    /// reader cannot just read the beta catalogue and filter; it would lose those
    /// stable versions. Each switch position reads its own channel, and the beta
    /// catalogue is consulted on the side only to name a copy that is already
    /// ahead of stable.
    public enum Channel: Sendable, Hashable {
        case stable
        case beta

        var path: String { self == .beta ? "beta/en" : "en" }

        public var catalogURL: URL {
            URL(string: "https://store.setapp.com/store/api/v8/\(path)")!
        }
    }

    public static let catalogURL = Channel.stable.catalogURL

    /// How long a parsed catalogue is reused. The endpoint honours an ETag
    /// (measured 304), so revalidation costs headers rather than 3 MB; hours is
    /// the right order for a catalogue Setapp publishes a few times a week.
    static let defaultTTL: TimeInterval = 6 * 60 * 60

    /// The app's own request shape: `application/vnd.api+json`, no credentials.
    static func request(channel: Channel = .stable, etag: String? = nil) -> URLRequest {
        var request = URLRequest(url: channel.catalogURL)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return request
    }

    /// The whole catalogue, newest release per app, keyed by lowercased bundle id.
    ///
    /// Throws on a real failure (network, non-200, unparseable). Callers decide
    /// whether that is a row the user sees.
    public static func releases(
        channel: Channel = .stable, session: URLSession = .updates, now: Date = Date()
    ) async throws -> [String: SetappRelease] {
        try await cache(for: channel).releases(session: session, now: now)
    }

    private static func cache(for channel: Channel) -> Cache {
        channel == .beta ? betaCache : stableCache
    }

    /// Make the next `releases()` ask Setapp again. Backs `invalidateMemo`, so a
    /// per-row recheck can see a release published inside the TTL.
    public static func revalidate() async {
        await stableCache.revalidate()
        await betaCache.revalidate()
    }

    private static let stableCache = Cache(channel: .stable)
    private static let betaCache = Cache(channel: .beta)

    /// One in-memory copy shared by every row of a check. `UpdateChecker` fans out
    /// across apps, so without this a scan of N Setapp apps would fetch 3 MB N
    /// times.
    actor Cache {
        let channel: Channel
        init(channel: Channel) { self.channel = channel }

        private var value: [String: SetappRelease]?
        private var fetchedAt: Date?
        private var etag: String?
        private var inFlight: Task<[String: SetappRelease], Error>?
        private var inFlightToken: UUID?

        /// Expire the TTL but keep the parsed copy and its ETag, so the next
        /// check revalidates (304 costs headers) instead of waiting out six
        /// hours. This is what an explicit recheck means.
        func revalidate() {
            fetchedAt = nil
        }

        func releases(session: URLSession, now: Date) async throws -> [String: SetappRelease] {
            if let value, let fetchedAt, now.timeIntervalSince(fetchedAt) < SetappCatalog.defaultTTL {
                return value
            }
            // Join the fetch already under way, if any. A joiner does not own the
            // slot: only the caller that created the task clears it, and only
            // while the slot still holds that task (the token). A joiner that
            // cleared it after a failure could otherwise free the slot of the
            // replacement somebody else started.
            if let inFlight { return try await inFlight.value }

            let request = SetappCatalog.request(channel: channel, etag: etag)
            let token = UUID()
            let task = Task<[String: SetappRelease], Error> {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw SetappCatalogError.notAFeed
                }
                if http.statusCode == 304 {
                    return try await self.unchanged(now: now)
                }
                guard http.statusCode == 200 else {
                    throw SetappCatalogError.httpStatus(http.statusCode)
                }
                return try await self.commit(
                    data: data, responseETag: http.value(forHTTPHeaderField: "ETag"), now: now)
            }
            inFlight = task
            inFlightToken = token
            defer {
                if inFlightToken == token {
                    inFlight = nil
                    inFlightToken = nil
                }
            }
            return try await task.value
        }

        private func unchanged(now: Date) throws -> [String: SetappRelease] {
            guard let value else { throw SetappCatalogError.unparseable }
            fetchedAt = now
            return value
        }

        private func commit(
            data: Data, responseETag: String?, now: Date
        ) throws -> [String: SetappRelease] {
            let releases = try SetappCatalog.parse(data)
            value = releases
            fetchedAt = now
            etag = responseETag
            return releases
        }
    }

    enum SetappCatalogError: LocalizedError {
        case httpStatus(Int)
        case notAFeed
        case unparseable

        var errorDescription: String? {
            switch self {
            case .httpStatus(let status):
                return "Setapp's catalogue answered HTTP \(status)"
            case .notAFeed:
                return "Setapp's catalogue answered something that is not HTTP"
            case .unparseable:
                return "Setapp's catalogue could not be parsed"
            }
        }
    }

    // MARK: - Parsing

    /// The catalogue as `[bundleID: release]`, keeping only the newest version row
    /// of each app. Every id in the payload is indexed — not just the `-setapp`
    /// ones: the suffix is a convention Setapp mandates today (all 468 entries on
    /// 2026-11-03 carry it), and matching must not fall over the day one does not.
    ///
    /// Shape (JSON:API, trimmed to what is used):
    ///
    ///     data.relationships.vendors[].relationships.applications[]
    ///       attributes: bundle_id, name, public_id, slugs[]
    ///       relationships.versions[]: marketing_version, build_number,
    ///                                 release_date (epoch), min_os_version
    ///
    /// JSON:API booleans arrive as `true`/`false` (`NSNumber` once parsed); accept
    /// a numeric 1/0 too, since that is what a hand-written fixture tends to use.
    static func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let bool = value as? Bool { return bool }
        return false
    }

    /// Newest is `release_date` descending, the only ordering field the payload
    /// carries; a row without one sorts last, never first.
    public static func parse(_ data: Data) throws -> [String: SetappRelease] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let relationships = payload["relationships"] as? [String: Any],
              let vendors = relationships["vendors"] as? [String: Any],
              let vendorRows = vendors["data"] as? [[String: Any]]
        else { throw SetappCatalogError.unparseable }

        var releases: [String: SetappRelease] = [:]
        for vendor in vendorRows {
            guard let vendorRelationships = vendor["relationships"] as? [String: Any],
                  let applications = vendorRelationships["applications"] as? [String: Any],
                  let appRows = applications["data"] as? [[String: Any]]
            else { continue }

            for app in appRows {
                guard let attributes = app["attributes"] as? [String: Any],
                      let bundleID = attributes["bundle_id"] as? String,
                      let release = release(from: app, attributes: attributes, bundleID: bundleID)
                else { continue }
                releases[bundleID.lowercased()] = release
            }
        }
        return releases
    }

    private static func release(
        from app: [String: Any], attributes: [String: Any], bundleID: String
    ) -> SetappRelease? {
        guard let publicID = attributes["public_id"] as? String, publicID.isEmpty == false else {
            return nil
        }
        let name = attributes["name"] as? String ?? bundleID
        let relationships = app["relationships"] as? [String: Any]
        let versions = (relationships?["versions"] as? [String: Any])?["data"] as? [[String: Any]] ?? []

        let rows: [SetappVersion] = versions.compactMap { row in
            guard let attributes = row["attributes"] as? [String: Any] else { return nil }
            let epoch = (attributes["release_date"] as? NSNumber)?.doubleValue
            return SetappVersion(
                shortVersion: attributes["marketing_version"] as? String,
                build: attributes["build_number"] as? String,
                releaseDate: epoch.map { Date(timeIntervalSince1970: $0) },
                minimumSystemVersion: attributes["min_os_version"] as? String,
                isBeta: Self.flag(attributes["beta"]))
        }
        let ordered = rows.sorted { lhs, rhs in
            let l = lhs.releaseDate ?? .distantPast
            let r = rhs.releaseDate ?? .distantPast
            if l != r { return l > r }
            return VersionComparator.compare(lhs.shortVersion ?? "", rhs.shortVersion ?? "") == .orderedDescending
        }

        let slugs = attributes["slugs"] as? [[String: Any]] ?? []
        let slug = slugs.first { ($0["primary"] as? Bool) == true }?["slug"] as? String
            ?? slugs.first?["slug"] as? String

        return SetappRelease(
            bundleID: bundleID,
            name: name,
            publicID: publicID,
            versions: ordered,
            pageURL: slug.flatMap { URL(string: "https://setapp.com/apps/\($0)") })
    }
}
