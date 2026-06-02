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
            // Native Mac listings, and wrapped iPhone/iPad apps (whose installed
            // binary IS the iOS build), both take the lookup `version` directly.
            if result.isNativeMac || app.isiOSAppOnMac {
                return try await remoteVersion(from: result, region: homeRegion, checkMacCompat: app.isiOSAppOnMac)
            }
            // iOS-on-Mac apps (kind == "software"): the lookup API reports the
            // iOS version track, which is a different release line from the Mac
            // build. Scrape the App Store Mac product page to get the
            // platform-specific version instead.
            if let trackId = result.trackId {
                return try await iosOnMacVersion(trackId: trackId, lookupResult: result, region: homeRegion)
            }
            return nil
        }
        // Not in the home store — probe fallback storefronts; first hit wins.
        for region in fallbackRegions {
            if let result = try await lookup(bundleID: bundleID, region: region) {
                if result.isNativeMac || app.isiOSAppOnMac {
                    return try await remoteVersion(from: result, region: region, checkMacCompat: app.isiOSAppOnMac)
                }
                if let trackId = result.trackId {
                    return try await iosOnMacVersion(trackId: trackId, lookupResult: result, region: region)
                }
            }
        }
        return nil
    }

    // MARK: - iOS-on-Mac page scrape

    /// Fetch the App Store Mac product page and extract the Mac-specific version.
    /// Returns nil when the page has no Mac section or the scrape fails — callers
    /// treat nil as "no source" and fall through to `appStoreManaged`.
    private func iosOnMacVersion(
        trackId: Int,
        lookupResult: LookupResult,
        region: String
    ) async throws -> RemoteVersion? {
        guard let version = try await scrapeVersion(trackId: trackId, region: region) else {
            return nil
        }
        let availability = AppStoreAvailability(trackID: trackId, availableRegion: region, homeRegion: homeRegion)
        // Link to the Mac-specific product page so the changelog window can embed
        // it; inline release notes are omitted (vendors like WhatsApp publish
        // boilerplate text that carries no real information).
        let pageURL = URL(string: "https://apps.apple.com/\(region)/app/-/id\(trackId)?platform=mac")
        return RemoteVersion(
            shortVersion: version,
            version: nil,
            downloadURL: lookupResult.trackViewUrl.flatMap { URL(string: $0) },
            sourceName: name,
            appStore: availability,
            changelogURL: pageURL
        )
    }

    /// Fetches the App Store Mac page and extracts the current Mac version from
    /// the embedded amp-api JSON. The version lives at:
    ///   data[0].data.shelfMapping.mostRecentVersion.items[0].primarySubtitle
    /// formatted as "Version X.Y.Z".
    private func scrapeVersion(trackId: Int, region: String) async throws -> String? {
        guard let url = URL(string: "https://apps.apple.com/\(region)/app/-/id\(trackId)?platform=mac") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Apple's servers gate the full JSON blobs behind a browser UA.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return extractVersion(from: html)
    }

    /// Parses `<script type="application/json">` blobs in the HTML, looking for
    /// the `mostRecentVersion` shelf that Apple's amp-api inlines into the page.
    private func extractVersion(from html: String) -> String? {
        // Lightweight scan: find JSON blobs without a full HTML parser.
        var searchRange = html.startIndex..<html.endIndex
        let open = "<script type=\"application/json\""
        let close = "</script>"

        while let tagStart = html.range(of: open, range: searchRange) {
            guard let bodyStart = html.range(of: ">", range: tagStart.upperBound..<html.endIndex),
                  let bodyEnd   = html.range(of: close, range: bodyStart.upperBound..<html.endIndex) else { break }

            let jsonSlice = html[bodyStart.upperBound..<bodyEnd.lowerBound]
            if let jsonData = jsonSlice.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let version = parseMostRecentVersion(from: root) {
                return version
            }
            searchRange = bodyEnd.upperBound..<html.endIndex
        }
        return nil
    }

    private func parseMostRecentVersion(from root: [String: Any]) -> String? {
        guard let dataArr  = root["data"] as? [[String: Any]],
              let first    = dataArr.first,
              let inner    = first["data"] as? [String: Any],
              let shelves  = inner["shelfMapping"] as? [String: Any],
              let mrv      = shelves["mostRecentVersion"] as? [String: Any],
              let items    = mrv["items"] as? [[String: Any]],
              let subtitle = items.first?["primarySubtitle"] as? String else { return nil }

        // Subtitle is "Version 26.21.73" — drop the label, keep the number.
        let version = subtitle.hasPrefix("Version ") ? String(subtitle.dropFirst(8)) : subtitle
        return version.isEmpty ? nil : version
    }

    // MARK: - Mac compatibility (wrapped iOS apps)

    /// Reads Apple's `isIOSBinaryMacOSCompatible` flag for the latest build from
    /// the product page's inline amp-api JSON. nil when the page/flag can't be
    /// read — callers treat nil as "assume compatible" so a scrape failure never
    /// hides a real update.
    private func scrapeMacCompatibility(trackId: Int, region: String) async throws -> Bool? {
        guard let url = URL(string: "https://apps.apple.com/\(region)/app/id\(trackId)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return extractMacCompatible(from: html)
    }

    /// Finds `data[0].data.lockup.isIOSBinaryMacOSCompatible` in the page's
    /// `<script type="application/json">` blobs. Internal for offline tests.
    func extractMacCompatible(from html: String) -> Bool? {
        var searchRange = html.startIndex..<html.endIndex
        let open = "<script type=\"application/json\""
        let close = "</script>"

        while let tagStart = html.range(of: open, range: searchRange) {
            guard let bodyStart = html.range(of: ">", range: tagStart.upperBound..<html.endIndex),
                  let bodyEnd   = html.range(of: close, range: bodyStart.upperBound..<html.endIndex) else { break }

            let jsonSlice = html[bodyStart.upperBound..<bodyEnd.lowerBound]
            if let jsonData = jsonSlice.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let dataArr = root["data"] as? [[String: Any]],
               let inner   = dataArr.first?["data"] as? [String: Any],
               let lockup  = inner["lockup"] as? [String: Any],
               let compat  = lockup["isIOSBinaryMacOSCompatible"] as? Bool {
                return compat
            }
            searchRange = bodyEnd.upperBound..<html.endIndex
        }
        return nil
    }

    // MARK: -

    /// Build a `RemoteVersion` from a lookup hit. For wrapped iPhone/iPad apps
    /// (`checkMacCompat`), also fetch the product page once to learn whether the
    /// newest build still runs on Macs — a newer version can exist yet be
    /// uninstallable here ("Not compatible with this device").
    private func remoteVersion(from result: LookupResult, region: String, checkMacCompat: Bool) async throws -> RemoteVersion? {
        guard let version = result.version else { return nil }
        var macCompatible: Bool?
        if checkMacCompat, let trackId = result.trackId {
            macCompatible = try await scrapeMacCompatibility(trackId: trackId, region: region)
        }
        let availability = result.trackId.map {
            AppStoreAvailability(trackID: $0, availableRegion: region, homeRegion: homeRegion, latestMacCompatible: macCompatible)
        }
        // `releaseNotes` is the "What's New" text for the latest version. Safe to
        // trust here: we only reach this for native Mac listings or wrapped iOS
        // apps (guarded upstream), where the notes match the actual installed
        // build — not an unrelated track. Plain text (newline-delimited).
        let notes = result.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteVersion(
            shortVersion: version,
            version: nil,
            downloadURL: result.trackViewUrl.flatMap { URL(string: $0) },
            sourceName: name,
            appStore: availability,
            releaseNotesHTML: (notes?.isEmpty == false) ? notes : nil
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
        /// "What's New in Version X" text for the latest release. Plain text with
        /// embedded newlines (no markup). nil/absent for some listings.
        let releaseNotes: String?
        /// "mac-software" for native Mac apps; "software" for iOS apps offered
        /// on Apple Silicon (whose `version` is the unrelated iOS version).
        let kind: String?

        var isNativeMac: Bool { kind == "mac-software" }
    }

    enum MASError: Error { case badStatus(Int) }
}
