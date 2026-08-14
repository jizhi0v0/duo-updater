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

    public init(session: URLSession = .updates, region: String? = nil) {
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

        // Try the user's own store first (the common case).
        if let result = try await lookup(bundleID: bundleID, region: homeRegion) {
            return try await resolve(result: result, app: app, region: homeRegion)
        }
        // Not in the home store — probe fallback storefronts; first hit wins.
        for region in fallbackRegions {
            if let result = try await lookup(bundleID: bundleID, region: region),
               let resolved = try await resolve(result: result, app: app, region: region) {
                return resolved
            }
        }
        return nil
    }

    /// Turn a lookup hit into a `RemoteVersion`, routing by listing kind. Shared
    /// by the home-store and fallback-store paths.
    private func resolve(result: LookupResult, app: InstalledApp, region: String) async throws -> RemoteVersion? {
        // Native Mac listing: trust the lookup version, but cross-check the
        // product page and keep whichever is newer. Apple's per-storefront lookup
        // cache can lag a freshly-shipped build that the page already shows
        // (observed: Excel 16.109.3 live on the cn page while the cn lookup still
        // returned 16.109.2), which silently hid real updates.
        if result.isNativeMac {
            return try await nativeMacVersion(from: result, region: region)
        }
        // Wrapped iPhone/iPad app: the installed binary IS the iOS build, so the
        // lookup `version` is the right track — take it directly (with a Mac-compat
        // check, since a newer build can drop Mac support).
        if app.isiOSAppOnMac {
            return try await remoteVersion(from: result, region: region, checkMacCompat: true)
        }
        // iOS-on-Mac (kind == "software") whose Mac build is a separate release
        // line from the iOS track the lookup reports: scrape the Mac product page
        // for the platform-specific version instead.
        if let trackId = result.trackId {
            return try await iosOnMacVersion(trackId: trackId, lookupResult: result, region: region)
        }
        return nil
    }

    /// Resolve a native Mac app's latest version, cross-checking the lookup API
    /// against the product page (often fresher per storefront) and keeping the
    /// newer of the two. A page-scrape failure just leaves us on the lookup value.
    private func nativeMacVersion(from result: LookupResult, region: String) async throws -> RemoteVersion? {
        let lookupVersion = result.version
        var pageInfo: MacVersionInfo?
        if let trackId = result.trackId {
            pageInfo = try? await scrapeMacVersion(trackId: trackId, region: region)
        }

        // The page wins only when it's strictly newer (or the lookup gave nothing).
        let usePage: Bool
        if let pageVersion = pageInfo?.version {
            usePage = lookupVersion.map { VersionComparator.isNewer(pageVersion, than: $0) } ?? true
        } else {
            usePage = false
        }

        let version: String
        let notes: String?
        var changelogURL: URL?
        if usePage, let pageInfo {
            version = pageInfo.version
            // The page's own "What's New" describes this newer build — surface it,
            // and link the page as the changelog (matching the iOS-on-Mac path).
            notes = pageInfo.notes
            changelogURL = result.trackId.flatMap {
                URL(string: "https://apps.apple.com/\(region)/app/-/id\($0)?platform=mac")
            }
        } else if let lookupVersion {
            version = lookupVersion
            notes = result.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil  // neither source produced a version
        }

        let availability = result.trackId.map {
            AppStoreAvailability(trackID: $0, availableRegion: region, homeRegion: homeRegion)
        }
        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteVersion(
            shortVersion: version,
            version: nil,
            downloadURL: result.trackViewUrl.flatMap { URL(string: $0) },
            // The App Store product page — for MAS the "download URL" already is
            // a page, so both fields point at it.
            pageURL: result.trackViewUrl.flatMap { URL(string: $0) },
            sourceName: name,
            appStore: availability,
            releaseNotesHTML: (cleanNotes?.isEmpty == false) ? cleanNotes : nil,
            changelogURL: changelogURL
        )
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
        guard let info = try await scrapeMacVersion(trackId: trackId, region: region) else {
            return nil
        }
        let availability = AppStoreAvailability(trackID: trackId, availableRegion: region, homeRegion: homeRegion)
        // The Mac-specific product page, both as the inline web fallback and the
        // "Open page" link. The lookup API's `releaseNotes` here describes the iOS
        // track, not the Mac build, so we instead surface the Mac page's own
        // "What's New" text (scraped in the same pass as the version) inline —
        // exactly what the App Store shows for this app, rather than a web view.
        let pageURL = URL(string: "https://apps.apple.com/\(region)/app/-/id\(trackId)?platform=mac")
        let notes = info.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteVersion(
            shortVersion: info.version,
            version: nil,
            downloadURL: lookupResult.trackViewUrl.flatMap { URL(string: $0) },
            // Prefer the Mac-specific product page over the lookup's generic
            // trackViewUrl, which lands on the iOS listing for wrapped apps.
            pageURL: pageURL ?? lookupResult.trackViewUrl.flatMap { URL(string: $0) },
            sourceName: name,
            appStore: availability,
            releaseNotesHTML: (notes?.isEmpty == false) ? notes : nil,
            changelogURL: pageURL
        )
    }

    /// The newest Mac build's version string plus its "What's New" notes, both
    /// read from the product page's `mostRecentVersion` shelf in a single scrape.
    struct MacVersionInfo: Equatable {
        let version: String
        /// The latest version's release-notes text, verbatim (newline-delimited,
        /// no markup — rendered as plain text). Nil when the shelf carries none.
        let notes: String?
    }

    /// Fetches the App Store Mac page and extracts the current Mac version (and
    /// its "What's New" notes) from the embedded amp-api JSON. Both live in the
    /// same shelf item at:
    ///   data[0].data.shelfMapping.mostRecentVersion.items[0]
    /// with `primarySubtitle` = "Version X.Y.Z" and `text` = the release notes.
    private func scrapeMacVersion(trackId: Int, region: String) async throws -> MacVersionInfo? {
        guard let url = URL(string: "https://apps.apple.com/\(region)/app/-/id\(trackId)?platform=mac") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        // Apple's servers gate the full JSON blobs behind a browser UA.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return extractMacVersionInfo(from: html)
    }

    /// Parses `<script type="application/json">` blobs in the HTML, looking for
    /// the `mostRecentVersion` shelf that Apple's amp-api inlines into the page.
    /// Internal for offline tests.
    func extractMacVersionInfo(from html: String) -> MacVersionInfo? {
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
               let info = parseMostRecentVersion(from: root) {
                return info
            }
            searchRange = bodyEnd.upperBound..<html.endIndex
        }
        return nil
    }

    private func parseMostRecentVersion(from root: [String: Any]) -> MacVersionInfo? {
        guard let dataArr  = root["data"] as? [[String: Any]],
              let first    = dataArr.first,
              let inner    = first["data"] as? [String: Any],
              let shelves  = inner["shelfMapping"] as? [String: Any],
              let mrv      = shelves["mostRecentVersion"] as? [String: Any],
              let items    = mrv["items"] as? [[String: Any]],
              let item     = items.first,
              let subtitle = item["primarySubtitle"] as? String else { return nil }

        // The label is localized ("Version 26.21.73", "版本 16.109.3", "버전 …") —
        // pull the numeric version out directly rather than stripping an English
        // prefix, which left non-English subtitles unparsed.
        guard let version = Self.versionNumber(in: subtitle) else { return nil }
        let notes = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MacVersionInfo(version: version, notes: (notes?.isEmpty == false) ? notes : nil)
    }

    /// Extract the first dotted-numeric version run from a (possibly localized)
    /// "Version X.Y.Z" subtitle. Falls back to a bare integer for single-component
    /// versions. Internal for offline tests.
    static func versionNumber(in text: String) -> String? {
        let range = text.range(of: #"\d+(\.\d+)+"#, options: .regularExpression)
            ?? text.range(of: #"\d+"#, options: .regularExpression)
        return range.map { String(text[$0]) }
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
        request.cachePolicy = URLRequest.versionFeedCachePolicy
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
            // The App Store product page — for MAS the "download URL" already is
            // a page, so both fields point at it.
            pageURL: result.trackViewUrl.flatMap { URL(string: $0) },
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
        request.cachePolicy = URLRequest.versionFeedCachePolicy

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
