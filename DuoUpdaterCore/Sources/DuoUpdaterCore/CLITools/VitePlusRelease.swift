import CryptoKit
import Foundation

/// What Vite+ publishes, from the npm registry — the one channel its installer
/// and `vp upgrade` read:
/// - `registry.npmjs.org/vite-plus/latest` is the version `vp upgrade` installs
///   (1.0.0 on 2026-10-06; the `alpha` tag has stood at 0.1.21-alpha.7 since
///   May, and `test` is for preview builds). Nothing on disk records another
///   tag, so `latest` is the channel.
/// - `@voidzero-dev/vite-plus-cli-darwin-<arm64|x64>/<version>` is the package
///   holding that version's `vp`: `dist.tarball`, its `dist.integrity`
///   (`sha512-<base64>`), and `dist.attestations.provenance` — the installer
///   refuses a release without SLSA provenance, and so does this.
public struct VitePlusRelease: Sendable {

    public static let registry = URL(string: "https://registry.npmjs.org")!
    static let channel = registry.appendingPathComponent("vite-plus/latest")

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable(String)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable(let what): return what
            }
        }
    }

    /// A URL's body and status. Injected so tests never reach the network.
    typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url in
            var request = URLRequest(url: url)
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public func latest() async throws -> String {
        let json = try await document(Self.channel)
        guard let version = json["version"] as? String, Self.isVersion(version) else {
            throw Failure.unreadable("vite-plus@latest names no version")
        }
        return version
    }

    /// Where `vp` of `version` for `platform` is published, and its digest.
    struct Package: Sendable, Equatable {
        let tarball: URL
        /// The raw SHA-512 the registry's `integrity` names.
        let sha512: Data
    }

    func package(version: String, platform: String) async throws -> Package {
        guard Self.isVersion(version), Self.platforms.contains(platform) else {
            throw Failure.unreadable("no package for vite-plus \(version) on \(platform)")
        }
        // `@voidzero-dev%2fvite-plus-cli-…`, as the installer asks it.
        let url = URL(string: "\(Self.registry.absoluteString)/@voidzero-dev%2Fvite-plus-cli-\(platform)/\(version)")!
        return try Self.package(in: try await document(url), version: version)
    }

    static let platforms: Set<String> = ["darwin-arm64", "darwin-x64"]

    /// The package from its version document: a tarball on the registry itself,
    /// a SHA-512 integrity, and SLSA provenance (v1 or v0.2, the installer's two).
    static func package(in json: [String: Any], version: String) throws -> Package {
        guard json["version"] as? String == version, let dist = json["dist"] as? [String: Any] else {
            throw Failure.unreadable("the registry has no vite-plus \(version) package document")
        }
        let provenance = ((dist["attestations"] as? [String: Any])?["provenance"] as? [String: Any])?["predicateType"] as? String
        guard provenance == "https://slsa.dev/provenance/v1" || provenance == "https://slsa.dev/provenance/v0.2" else {
            throw Failure.unreadable("vite-plus \(version) has no npm provenance")
        }
        guard let tarball = (dist["tarball"] as? String).flatMap(URL.init(string:)),
              tarball.scheme == "https", tarball.host == registry.host
        else { throw Failure.unreadable("vite-plus \(version)'s tarball is not on registry.npmjs.org") }
        guard let integrity = dist["integrity"] as? String, integrity.hasPrefix("sha512-"),
              let sha512 = Data(base64Encoded: String(integrity.dropFirst("sha512-".count))), sha512.count == 64
        else { throw Failure.unreadable("vite-plus \(version) has no sha512 integrity") }
        return Package(tarball: tarball, sha512: sha512)
    }

    private func document(_ url: URL) async throws -> [String: Any] {
        let (data, status) = try await fetch(url)
        guard status == 200 else { throw Failure.http(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable("\(url.absoluteString) is not a package document")
        }
        return json
    }

    /// A release version, semver as npm reads it — also what keeps it safe as a
    /// command-line argument and in a URL path.
    static func isVersion(_ s: String) -> Bool {
        s.count <= 64 && NpmVersion(s) != nil && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }
}

/// Whether a `vp` is byte for byte the build VoidZero published for its version —
/// the second arm of the trust rule (`CLIToolTrust`), for a binary that is only
/// ever ad hoc signed.
///
/// VoidZero publishes no digest for the bare executable, only the npm package's
/// integrity (and the GitHub release archives' sha256, which wrap the same file).
/// So the check is the package's, as uv's is its archive's (`UvVerifier`):
/// download the version's platform package, check it against the registry's
/// SHA-512, unpack it, and compare its `package/vp` with the file on disk.
/// Measured 2026-10-06: the 1.0.0 arm64 package is 4,462,436 bytes, matched its
/// integrity, and its `vp` hashed `d787c0a8…`, the same as the `vp` both a fresh
/// install and `vp upgrade` left.
///
/// ~4.5 MB is not for every background check: it runs when the user clicks the
/// update, and its answer is remembered for the file (`UvVerifiedFiles.vitePlus`).
struct VitePlusVerifier: Sendable {

    typealias Download = @Sendable (URL) async throws -> Data
    typealias Extract = @Sendable (URL, URL) async throws -> Void

    let release: VitePlusRelease
    let download: Download
    let extract: Extract
    let verified: UvVerifiedFiles

    init(
        release: VitePlusRelease = VitePlusRelease(),
        download: @escaping Download = VitePlusVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        verified: UvVerifiedFiles = .vitePlus
    ) {
        self.release = release
        self.download = download
        self.extract = extract
        self.verified = verified
    }

    /// Checks `binary` against VoidZero's `version` for `platform`, and
    /// remembers a definite answer for the file as it was when read.
    func verify(binary: String, version: String, platform: String) async -> UvVerifier.Result {
        // Who the file is now, taken before it is read: a file replaced while
        // this runs is remembered under the old identity, which then matches nothing.
        let identity = await offCooperativePool { UvVerifiedFiles.identity(of: binary, uvx: nil) }
        let result = await compare(binary: binary, version: version, platform: platform)
        let verdict: UvInstall.HashVerdict?
        switch result {
        case .matches: verdict = .matches
        case .differs: verdict = .differs
        case .couldNotVerify: verdict = nil
        }
        if let verdict, let identity {
            let verified = self.verified
            await offCooperativePool { verified.remember(verdict, for: binary, identity: identity) }
        }
        return result
    }

    private func compare(binary: String, version: String, platform: String) async -> UvVerifier.Result {
        let archive: Data
        do {
            let package = try await release.package(version: version, platform: platform)
            archive = try await download(package.tarball)
            guard Data(SHA512.hash(data: archive)) == package.sha512 else {
                return .couldNotVerify("the vite-plus \(version) package did not match the integrity npm publishes for it")
            }
        } catch {
            return .couldNotVerify("could not download vite-plus \(version) to compare: \(error)")
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-vite-plus-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent("package.tgz")
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .couldNotVerify("could not unpack vite-plus \(version): \(error)")
        }
        let published = scratch.appendingPathComponent("package/vp")
        return await offCooperativePool {
            guard let expected = CLIToolTrust.sha256(of: published) else {
                return .couldNotVerify("the vite-plus \(version) package has no vp")
            }
            let actual = CLIToolTrust.sha256(of: URL(fileURLWithPath: binary))
            return CLIToolTrust.matches(actual, published: expected)
                ? .matches
                : .differs("\(binary) is not the vp VoidZero published for \(version)")
        }
    }

    /// A registry tarball, counted as an install.
    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .install)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw VitePlusRelease.Failure.http(status) }
        return data
    }
}
