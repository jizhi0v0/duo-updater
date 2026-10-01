import CryptoKit
import Foundation

/// What rust-lang's release server says: rustup's latest version and the hash of
/// each of its builds, and where each toolchain channel points. All of it from
/// `static.rust-lang.org`, the files rustup itself reads.
///
/// **rustup** (rustup 1.29.1's `self_update.rs`, read and fetched 2026-10-02):
/// - `rustup/release-stable.toml` is the latest version —
///   `schema-version = '1'` / `version = '1.29.1'` — which `rustup self update`
///   reads (`get_available_rustup_version`);
/// - `rustup/archive/<version>/<triple>/rustup-init.sha256` is the sha256 of
///   that build, `<hex> *./rustup-init`. `rustup self update` downloads
///   `rustup-init` beside it and copies it over `rustup`, byte for byte, so the
///   installed `rustup` hashes to the same value (1.29.1 arm64:
///   `ec1b9233…696a`, equal on 2026-10-01). A version that was never published
///   answers 404. The directory cannot be listed.
///
/// **Toolchains** (`src/dist/download.rs`): `dist/channel-rust-<channel>.toml`
/// is the channel's manifest, ~900 KB, and `….toml.sha256` its hash
/// (`<hex>  channel-rust-stable.toml`, ~90 bytes). `rustup update` fetches the
/// hash first and stops ("unchanged") when its first 20 digits equal
/// `update-hashes/<toolchain>`; only then does it download the manifest. The
/// check does the same. `X.Y` channels have their own pair
/// (`channel-rust-1.98.toml.sha256`, 200 on 2026-10-02) that follows the last
/// `X.Y.Z`.
///
/// When the hash moved, which version the channel now holds is `[pkg.rust]`'s
/// `version` in the manifest, ~80 KB into it but not at a fixed place, so the
/// whole manifest is read (943,486 bytes for stable on 2026-10-01) — once per
/// manifest: the label is kept by the manifest's own sha256 (`ChannelVersions`),
/// so a channel that stays ahead of an install is not downloaded again on every
/// check. A range read would save most of the bytes when it hits and need the
/// full read anyway when the table moves; a channel moves every six weeks
/// (stable) to once a day (nightly).
public struct RustRelease: Sendable {

    public static let root = URL(string: "https://static.rust-lang.org")!

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable(String)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable(let what): return "\(what) is not in the expected shape"
            }
        }
    }

    /// GETs a URL; any status but 200 throws `Failure.http`. Injected so tests
    /// never reach the network.
    typealias Fetch = @Sendable (URL) async throws -> Data

    let fetch: Fetch
    let versions: ChannelVersions

    public init(session: URLSession = .updates) {
        self.init(fetch: { url in
            var request = URLRequest(url: url)
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw Failure.http(status) }
            return data
        })
    }

    init(fetch: @escaping Fetch, versions: ChannelVersions = ChannelVersions()) {
        self.fetch = fetch
        self.versions = versions
    }

    // MARK: - rustup

    public func latestRustup() async throws -> String {
        let text = String(decoding: try await fetch(Self.root.appendingPathComponent("rustup/release-stable.toml")),
                          as: UTF8.self)
        guard let version = Self.releaseVersion(text) else { throw Failure.unreadable("release-stable.toml") }
        return version
    }

    /// The published sha256 of rustup `version` for `triple`; nil when that
    /// build does not exist (404, or 403 as S3 answers for a missing key without
    /// list rights).
    public func publishedRustupHash(version: String, triple: String) async throws -> String? {
        let url = Self.root.appendingPathComponent("rustup/archive")
            .appendingPathComponent(version).appendingPathComponent(triple)
            .appendingPathComponent("rustup-init.sha256")
        do {
            let text = String(decoding: try await fetch(url), as: UTF8.self)
            guard let digest = CLIToolTrust.firstDigest(in: text) else {
                throw Failure.unreadable("rustup-init.sha256 for \(version)")
            }
            return digest
        } catch Failure.http(let status) where status == 404 || status == 403 {
            return nil
        }
    }

    /// `version = '1.29.1'` (either quote) in `release-stable.toml`.
    static func releaseVersion(_ toml: String) -> String? {
        for raw in toml.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let match = line.range(of: #"^version\s*=\s*['"]([0-9]+\.[0-9]+\.[0-9]+)['"]$"#,
                                         options: .regularExpression) else { continue }
            return line[match].split(separator: "=")[1]
                .trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
        }
        return nil
    }

    /// Which rustup a binary is, decided by its bytes alone.
    public struct Identity: Sendable, Equatable {
        /// What `release-stable.toml` names.
        public let latest: String
        /// The version whose published hash the binary's sha256 equals; nil when
        /// none of the candidates did.
        public let verified: String?
    }

    /// Hash-matches `rustup` against rust-lang's builds without running it.
    ///
    /// Two candidates, as the archive cannot be listed: the latest, which is what
    /// an up-to-date install is; else the version the binary's user-agent string
    /// names (`RustScanner.claimedVersion`). The claim only picks which published
    /// hash to fetch — the verdict is the hash. Throws when the server cannot be
    /// read, so "could not check" is never mistaken for "not rust-lang's".
    func identify(sha256: String?, triple: String?, claimed: String?) async throws -> Identity {
        let latest = try await latestRustup()
        guard let sha256, let triple else { return Identity(latest: latest, verified: nil) }
        if CLIToolTrust.matches(sha256, published: try await publishedRustupHash(version: latest, triple: triple)) {
            return Identity(latest: latest, verified: latest)
        }
        guard let claimed, claimed != latest,
              CLIToolTrust.matches(sha256, published: try await publishedRustupHash(version: claimed, triple: triple))
        else { return Identity(latest: latest, verified: nil) }
        return Identity(latest: latest, verified: claimed)
    }

    // MARK: - Toolchain channels

    func channelURL(_ channel: String, suffix: String = "") -> URL {
        Self.root.appendingPathComponent("dist/channel-rust-\(channel).toml\(suffix)")
    }

    /// The full sha256 of `channel`'s current manifest.
    public func channelHash(_ channel: String) async throws -> String {
        let text = String(decoding: try await fetch(channelURL(channel, suffix: ".sha256")), as: UTF8.self)
        guard let digest = CLIToolTrust.firstDigest(in: text) else {
            throw Failure.unreadable("channel-rust-\(channel).toml.sha256")
        }
        return digest
    }

    /// The Rust version the manifest whose sha256 is `hash` holds.
    public func channelVersion(_ channel: String, hash: String) async throws -> RustToolchainVersion {
        if let known = versions[hash] { return known }
        let data = try await fetch(channelURL(channel))
        guard let version = Self.packageVersion(in: data) else {
            throw Failure.unreadable("channel-rust-\(channel).toml")
        }
        // Kept only when the manifest is the one `hash` names: between the two
        // requests the channel can move, and a label filed under the wrong hash
        // would outlive that.
        if SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash.lowercased() {
            versions[hash] = version
        }
        return version
    }

    /// `[pkg.rust]`'s `version = "…"` in a channel manifest — the downloaded one
    /// or a toolchain's own copy, which rustup writes in the same shape. `data`
    /// may be the start of the file only (`RustScanner.manifestVersion`): nil
    /// then means "not in what was read".
    static func packageVersion(in data: Data) -> RustToolchainVersion? {
        let marker = Data("[pkg.rust]\n".utf8)
        var from = data.startIndex
        while let found = data.range(of: marker, in: from..<data.endIndex) {
            from = found.upperBound
            // A table header starts its line.
            guard found.lowerBound == data.startIndex || data[found.lowerBound - 1] == 0x0A else { continue }
            let window = data[found.upperBound...].prefix(8 * 1024)
            // A line cut off by the end of a partial read lacks its closing
            // quote, so the pattern below passes over it.
            for line in String(decoding: window, as: UTF8.self).split(separator: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("[") { return nil }
                guard text.hasPrefix("version") else { continue }
                guard let match = text.range(of: #"^version\s*=\s*"([^"]*)"$"#, options: .regularExpression) else {
                    continue
                }
                let label = text[match].drop { $0 != "\"" }.dropFirst().dropLast()
                return RustToolchainVersion(label: String(label))
            }
            return nil
        }
        return nil
    }

    /// Manifest labels by the manifest's sha256: a hash names one file forever,
    /// so nothing here goes stale. One per provider, for the app's session.
    final class ChannelVersions: @unchecked Sendable {
        private let lock = NSLock()
        private var known: [String: RustToolchainVersion] = [:]

        init() {}

        subscript(hash: String) -> RustToolchainVersion? {
            get { lock.withLock { known[hash.lowercased()] } }
            set { lock.withLock { known[hash.lowercased()] = newValue } }
        }
    }
}
