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

    public init(shortVersion: String?, build: String?, releaseDate: Date?, minimumSystemVersion: String?) {
        self.shortVersion = shortVersion
        self.build = build
        self.releaseDate = releaseDate
        self.minimumSystemVersion = minimumSystemVersion
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
    public func newestCompatible(osVersion: String) -> SetappVersion? {
        versions.first { version in
            OSWindowRefusal.evaluate(
                minimum: version.minimumSystemVersion, maximum: nil,
                osVersion: osVersion,
                version: version.shortVersion ?? version.build ?? "") == nil
        }
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

    public static let catalogURL = URL(string: "https://store.setapp.com/store/api/v8/en")!

    /// How long a parsed catalogue is reused. The endpoint honours an ETag
    /// (measured 304), so revalidation costs headers rather than 3 MB; hours is
    /// the right order for a catalogue Setapp publishes a few times a week.
    static let defaultTTL: TimeInterval = 6 * 60 * 60

    /// The app's own request shape: `application/vnd.api+json`, no credentials.
    static func request(etag: String? = nil) -> URLRequest {
        var request = URLRequest(url: catalogURL)
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
        session: URLSession = .updates, now: Date = Date()
    ) async throws -> [String: SetappRelease] {
        try await cache.releases(session: session, now: now)
    }

    private static let cache = Cache()

    /// One in-memory copy shared by every row of a check. `UpdateChecker` fans out
    /// across apps, so without this a scan of N Setapp apps would fetch 3 MB N
    /// times.
    actor Cache {
        private var value: [String: SetappRelease]?
        private var fetchedAt: Date?
        private var etag: String?
        private var inFlight: Task<(Data?, String?, Int), Error>?

        func releases(session: URLSession, now: Date) async throws -> [String: SetappRelease] {
            if let value, let fetchedAt, now.timeIntervalSince(fetchedAt) < SetappCatalog.defaultTTL {
                return value
            }
            let task: Task<(Data?, String?, Int), Error>
            if let inFlight {
                task = inFlight
            } else {
                let request = SetappCatalog.request(etag: etag)
                task = Task {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw SetappCatalogError.notAFeed
                    }
                    return (data, http.value(forHTTPHeaderField: "ETag"), http.statusCode)
                }
                inFlight = task
            }
            defer { inFlight = nil }
            let (data, responseETag, status) = try await task.value
            // Not modified: the copy this process already holds is still current.
            if status == 304, let value {
                fetchedAt = now
                return value
            }
            guard status == 200, let data else {
                throw SetappCatalogError.httpStatus(status)
            }
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
                minimumSystemVersion: attributes["min_os_version"] as? String)
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
