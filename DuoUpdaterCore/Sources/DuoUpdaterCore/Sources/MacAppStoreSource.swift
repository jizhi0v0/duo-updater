import Foundation

/// Resolves updates for Mac App Store apps via the public iTunes lookup API.
/// We can't install MAS updates ourselves (that's the App Store's job, and the
/// binary is DRM-bound to the purchasing Apple ID), so the result carries a
/// product link plus region info for the UI to act on.
public struct MacAppStoreSource: UpdateSource {
    public let name = "App Store"

    private let session: URLSession
    /// The signed-in account's storefront region — what the App Store will
    /// actually let the user install.
    private let homeRegion: String
    /// Extra storefronts to probe only when the app isn't in the home store.
    private let fallbackRegions: [String]

    public init(session: URLSession = .shared, region: String? = nil) {
        self.session = session
        let home = region
            ?? AppStoreStorefront.currentCountry()
            ?? Locale.current.region?.identifier.lowercased()
            ?? "us"
        self.homeRegion = home
        // Probed only for zero-result apps, first match wins, so the common
        // case stays at one request per app.
        let common = ["us", "cn", "hk", "tw", "jp", "sg", "kr", "gb"]
        self.fallbackRegions = common.filter { $0 != home }
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // Only applies to apps actually installed from the Mac App Store.
        guard app.isMASApp, let bundleID = app.bundleID else { return nil }

        // Try the user's own store first (the common case: a single request).
        if let result = try await lookup(bundleID: bundleID, region: homeRegion) {
            // The app is in the user's store. Only trust the version for native
            // Mac apps: iOS apps offered on Apple Silicon ("software") report
            // their iOS track version, which runs ahead of the Mac build the
            // store actually installs — comparing it yields phantom updates
            // (TestFlight, WhatsApp, WeChat…). Skip those rather than nag.
            guard result.isNativeMac else { return nil }
            return remoteVersion(from: result, region: homeRegion)
        }
        // Not in the home store — probe a few storefronts for a native Mac
        // listing so we can show the version and where it lives. First hit wins.
        for region in fallbackRegions {
            if let result = try await lookup(bundleID: bundleID, region: region), result.isNativeMac {
                return remoteVersion(from: result, region: region)
            }
        }
        return nil
    }

    private func remoteVersion(from result: LookupResult, region: String) -> RemoteVersion? {
        guard let version = result.version else { return nil }
        let availability = result.trackId.map {
            AppStoreAvailability(trackID: $0, availableRegion: region, homeRegion: homeRegion)
        }
        return RemoteVersion(
            shortVersion: version,
            version: nil,
            downloadURL: result.trackViewUrl.flatMap { URL(string: $0) },
            sourceName: name,
            appStore: availability
        )
    }

    /// One lookup against a single storefront. Returns nil when the app isn't
    /// listed there (resultCount == 0).
    private func lookup(bundleID: String, region: String) async throws -> LookupResult? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: region),
            URLQueryItem(name: "entity", value: "macSoftware")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MASError.badStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
        return decoded.results.first
    }

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    struct LookupResult: Decodable {
        let version: String?
        let trackViewUrl: String?
        let trackId: Int?
        /// "mac-software" for native Mac apps; "software" for iOS apps offered
        /// on Apple Silicon (whose `version` is the unrelated iOS version).
        let kind: String?

        var isNativeMac: Bool { kind == "mac-software" }
    }

    enum MASError: Error { case badStatus(Int) }
}
