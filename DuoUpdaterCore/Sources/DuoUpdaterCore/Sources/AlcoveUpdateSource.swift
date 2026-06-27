import Foundation

/// Authenticated update source for Alcove (`com.henrikruscon.Alcove`).
///
/// Alcove ships a "Reworked update manager" that pushes each new build to its
/// **licensed** API channel (`api.tryalcove.com`) before it reaches any public
/// mirror. Every public surface we previously read lags that channel — verified
/// 2026-06-17, when the app's own updater already offered 1.7.4 while all of:
///   • `update.tryalcove.com` (the old VendorProbe endpoint) → 1.7.3
///   • `download.tryalcove.com/Alcove.dmg` (the public CDN build) → 1.7.3 (194)
///   • the `henrikruscon/alcove-releases` GitHub mirror → 1.7.2
/// still served the previous release. A public-mirror probe therefore structurally
/// misses the window in which updates actually appear (this is the same lag that
/// retired the GitHub mirror — the mistake was assuming `update.tryalcove.com` was
/// authoritative when it is merely another trailing mirror).
///
/// This source replays the app's own authenticated flow, which is the *only*
/// authoritative version surface:
///   1. `POST /license/issue-token  {license_key, instance_id}` → a short-lived
///      Bearer JWT (the app re-issues it roughly daily).
///   2. `GET  /updates/latest`  (Bearer + app/OS headers) → `{tag_name,
///      build_number, assets[], sections[]}`.
///   3. download the chosen asset with the **same** Bearer.
/// `tag_name` is the marketing version and equals `CFBundleShortVersionString`
/// (no build trap — compare marketing-to-marketing). The download is licensed too,
/// so the one-click install carries the Bearer in `downloadHeaders`; the dmg is the
/// unlicensed "trial" build, byte-identical to the licensed one (the license lives
/// outside the bundle), so an in-place swap keeps activation.
///
/// Credentials — the user's permanent `license_key` and this machine's activation
/// `instance_id` — live in OUR Keychain and are seeded once. They cannot be
/// auto-extracted from Alcove: its own copy is a single AES-GCM-sealed blob whose
/// key is not derivable from the hardware UUID (it lives in the Secure Enclave /
/// the app's private Keychain group). When credentials are absent this source
/// returns nil and the public `VendorProbe` recipe still answers (lagging, but
/// better than nothing), so it degrades cleanly rather than blanking detection.
///
/// Wired ahead of `VendorProbeSource` in the stack: the checker takes the first
/// source that yields a version, so the authoritative answer wins whenever
/// credentials are present.
public struct AlcoveUpdateSource: UpdateSource {
    public static let bundleID = "com.henrikruscon.Alcove"

    /// Reported under the same label as the vendor probe it supersedes, so the UI
    /// and traffic stats stay consistent across the credentialed / public paths.
    public let name = "Vendor"

    /// The two stable per-machine secrets the licensed API needs. Stored in our
    /// Keychain; never logged.
    public struct Credentials: Sendable {
        public let licenseKey: String
        public let instanceID: String
        public init(licenseKey: String, instanceID: String) {
            self.licenseKey = licenseKey
            self.instanceID = instanceID
        }
    }

    private static let issueTokenURL = URL(string: "https://api.tryalcove.com/license/issue-token")!
    private static let updatesLatestURL = URL(string: "https://api.tryalcove.com/updates/latest")!

    private let credentials: Credentials
    private let session: URLSession

    public init(credentials: Credentials, session: URLSession = .updates) {
        self.credentials = credentials
        self.session = session
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard app.bundleID == Self.bundleID else { return nil }

        // Best-effort like the vendor probe: a failed token exchange or fetch must
        // look like "this source didn't apply" (→ fall through to the public probe),
        // not a hard error, so swallow and return nil.
        guard let token = try? await issueToken() else { return nil }
        guard let latest = try? await fetchLatest(token: token, app: app) else { return nil }

        let dmg = latest.assets.first { $0.name == "Alcove.dmg" }?.url
        return RemoteVersion(
            // tag_name is the marketing version (== CFBundleShortVersionString).
            shortVersion: latest.tagName,
            version: nil,
            downloadURL: dmg,
            minimumSystemVersion: latest.minimumSystemVersion,
            sourceName: name,
            // dmg → in-place swap (not a pkg handed to the system installer).
            requiresManualInstaller: false,
            vendorInstallerKind: dmg == nil ? nil : .dmg,
            // The licensed download needs the same Bearer the probe used.
            downloadHeaders: ["Authorization": "Bearer \(token)"],
            structuredChangelog: Self.changelog(from: latest),
            publishedAt: ReleaseDate.parse(latest.publishedAt)
        )
    }

    // MARK: - Authenticated flow

    /// Exchange the stored license + instance for a short-lived Bearer.
    private func issueToken() async throws -> String? {
        var request = URLRequest(url: Self.issueTokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            IssueTokenRequest(license_key: credentials.licenseKey, instance_id: credentials.instanceID))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let token = (try? JSONDecoder().decode(IssueTokenResponse.self, from: data))?.token
        return (token?.isEmpty == false) ? token : nil
    }

    /// Read the authoritative latest release with the issued Bearer.
    private func fetchLatest(token: String, app: InstalledApp) async throws -> UpdatesLatest? {
        var request = URLRequest(url: Self.updatesLatestURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        // The API varies its response by these (the public Vary header lists
        // X-Channel); sending the installed identity mirrors the app and keeps us on
        // the same (stable, no X-Channel) track the user is already on.
        if let v = app.shortVersion { request.setValue(v, forHTTPHeaderField: "x-app-version") }
        if let b = app.buildVersion { request.setValue(b, forHTTPHeaderField: "x-app-build") }
        request.setValue(Self.osVersion, forHTTPHeaderField: "x-macos-version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(UpdatesLatest.self, from: data)
    }

    // MARK: - Changelog

    /// Map the response's emoji-keyed `sections` into a single-entry changelog for
    /// the latest version. Each item keeps its section's marker inline (✨/🐞 …), the
    /// same convention the other structured changelogs use.
    static func changelog(from latest: UpdatesLatest) -> Changelog? {
        var items: [String] = []
        for section in latest.sections ?? [] {
            let prefix = section.marker.map { "\($0) " } ?? ""
            items += section.items.map { prefix + $0 }
        }
        guard !items.isEmpty else { return nil }
        let date = latest.publishedAt.map { String($0.prefix(10)) }   // ISO date prefix
        return Changelog(entries: [
            Changelog.Entry(version: latest.tagName, date: date, items: items)
        ])
    }

    // MARK: - Headers

    /// Mirror the app's own client identity. The endpoint doesn't pin a build, but
    /// a recognizable agent keeps us indistinguishable from the real client.
    private static let userAgent =
        "Alcove/194 CFNetwork/3886.100.1 Darwin/\(osVersion)"

    private static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
}

// MARK: - Wire types

private struct IssueTokenRequest: Encodable {
    let license_key: String
    let instance_id: String
}

private struct IssueTokenResponse: Decodable {
    let token: String
}

/// The `/updates/latest` payload (GitHub-release-shaped, plus Alcove's structured
/// `sections`). Only the fields we consume are decoded.
struct UpdatesLatest: Decodable {
    let tagName: String
    let buildNumber: Int?
    let publishedAt: String?
    let minimumSystemVersion: String?
    let assets: [Asset]
    let sections: [Section]?

    struct Asset: Decodable {
        let name: String
        let url: URL   // JSONDecoder unescapes the `\/`-escaped slashes
    }

    struct Section: Decodable {
        let marker: String?
        let items: [String]
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case buildNumber = "build_number"
        case publishedAt = "published_at"
        case minimumSystemVersion = "minimum_system_version"
        case assets, sections
    }
}
