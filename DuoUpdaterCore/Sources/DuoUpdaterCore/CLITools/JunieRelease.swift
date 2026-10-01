import Foundation

/// What each Junie channel points at: the `update-info*.jsonl` files the vendor's
/// installer reads (`install.sh`'s `UPDATE_INFO_URL`, read 2026-10-02).
///
/// - `https://raw.githubusercontent.com/jetbrains-junie/junie/main/update-info<suffix>.jsonl`,
///   suffix `""` for `release`, `-eap`, `-nightly`, `-experimental`;
/// - one JSON object per line: `version` (the build, `3419.26`), `platform`
///   (`macos-aarch64`, `macos-amd64`, and Linux and Windows ones), `downloadUrl`,
///   `sha256` of the zip, `size`, and on newer lines `marketing` (`26.9.22`);
/// - line order is not version order (`update-info.jsonl` on 2026-10-02 is not
///   sorted), so the installer's own rule is used: the greatest build, compared
///   numerically part by part, among the lines for this Mac's platform
///   (`fetch_latest_version`'s `sort -t. -k1,1n -k2,2n | tail -1`).
///
/// On 2026-10-02 the heads for `macos-aarch64` were release 3419.26, EAP 3579.2,
/// nightly 3612.1 and experimental 3336.1; `cache-control: max-age=300` and an
/// `ETag` on the response, so the version-feed cache policy revalidates.
///
/// Installers exist for `release`, `eap` and `nightly` only
/// (`https://junie.jetbrains.com/install.sh`, `install-eap.sh`,
/// `install-nightly.sh`; `install-experimental.sh` answered 404 on 2026-10-02).
public struct JunieRelease: Sendable {

    public struct Build: Sendable, Equatable {
        public let version: String
        /// The marketing version (`26.9.22`), on the lines that carry one.
        public let marketing: String?
        public let platform: String
        public let downloadURL: String
        public let sha256: String?
    }

    public enum Failure: Error, Equatable {
        case http(Int)
        case unreadable
        /// The feed has no build for this Mac's platform.
        case noBuild
    }

    static let feedBase = "https://raw.githubusercontent.com/jetbrains-junie/junie/main/update-info"
    static let knownChannels = ["release", "eap", "nightly", "experimental"]

    /// The channel's feed; nil for a channel Junie does not name.
    public static func feed(channel: String) -> URL? {
        guard knownChannels.contains(channel) else { return nil }
        return URL(string: feedBase + (channel == "release" ? "" : "-\(channel)") + ".jsonl")
    }

    /// The channel's installer, as the shim builds it (`installer_url_for_channel`):
    /// nil for `experimental`, which has none, and for a channel Junie does not name.
    public static func installer(channel: String) -> URL? {
        switch channel {
        case "release": return URL(string: "https://junie.jetbrains.com/install.sh")
        case "eap", "nightly": return URL(string: "https://junie.jetbrains.com/install-\(channel).sh")
        default: return nil
        }
    }

    /// `macos-aarch64` or `macos-amd64`: the installer's `${OS_NAME}-${ARCH_NAME}`.
    public static func platform(_ arch: HostArch = .current) -> String {
        arch == .arm64 ? "macos-aarch64" : "macos-amd64"
    }

    let session: URLSession
    let platform: String

    public init(session: URLSession = .updates, platform: String = JunieRelease.platform()) {
        self.session = session
        self.platform = platform
    }

    /// Every build the channel's feed lists for this Mac, newest first.
    public func builds(channel: String, force: Bool = false) async throws -> [Build] {
        guard let url = Self.feed(channel: channel) else { throw Failure.unreadable }
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        let platform = self.platform
        let builds = await offCooperativePool { Self.parse(data, platform: platform) }
        guard !builds.isEmpty else { throw Failure.noBuild }
        return builds
    }

    public func latest(channel: String) async throws -> Build {
        guard let newest = try await builds(channel: channel).first else { throw Failure.noBuild }
        return newest
    }

    /// The lines for `platform` that are builds, newest first, one per build. A
    /// line that does not parse is skipped, as the installer's `grep` would.
    static func parse(_ data: Data, platform: String) -> [Build] {
        var seen = Set<String>()
        var builds: [Build] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  json["platform"] as? String == platform,
                  let version = json["version"] as? String, JunieScanner.isBuild(version),
                  let url = json["downloadUrl"] as? String,
                  seen.insert(version).inserted
            else { continue }
            builds.append(Build(
                version: version, marketing: json["marketing"] as? String, platform: platform,
                downloadURL: url, sha256: json["sha256"] as? String))
        }
        return builds.sorted { compare($0.version, $1.version) == .orderedDescending }
    }

    /// Part by part, numerically; a missing part is 0.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(x.count, y.count) {
            let (l, r) = (index < x.count ? x[index] : 0, index < y.count ? y[index] : 0)
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
