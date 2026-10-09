import Foundation

/// Download one vendor or GitHub installer and read what it turns out to be,
/// the way the install route reads it, on a machine where the app is not
/// installed.
///
/// This is what `duo verify-install` runs for every recipe that names an
/// installer. `duo verify` stops at the URL (a HEAD at most), so anything only
/// the downloaded bytes can show is invisible to it: WorkBuddy CN shipped every
/// build from 5.5.4 (2026-09-16) under a new bundle id, and the sweep stayed
/// green for three weeks until #1030.
///
/// The steps are production's own — `Downloader`, `VendorInstaller.unpackVerified`
/// (published digests, MyGo signature, `ContentsPayload`, installer stub),
/// `SignatureVerifier.verifyPublishedDigest` and `verifyCodeSignature`. What it
/// cannot run is every gate that compares against an installed copy (Team, bundle
/// id, architecture downgrade); it records what those gates would read instead,
/// in `Identity`, for the caller to compare with what it expects.
public enum ArtifactInspection {

    /// What the identity gates read off a downloaded bundle.
    public struct Identity: Codable, Sendable, Equatable {
        /// `kSecCodeInfoIdentifier` — what gate 4 compares.
        public var signedIdentifier: String?
        /// `CFBundleIdentifier`, which is what recipes are keyed by.
        public var bundleIdentifier: String?
        /// What gate 3 compares. Nil for an ad-hoc signature.
        public var teamIdentifier: String?
        public var shortVersion: String?
        public var bundleVersion: String?
        /// The main executable's slices, as `arm64` / `x86_64`.
        public var architectures: [String]
        public var minimumSystemVersion: String?
        /// `SUPublicEDKey` when the bundle carries one.
        public var sparklePublicKey: String?

        public init(
            signedIdentifier: String?, bundleIdentifier: String?, teamIdentifier: String?,
            shortVersion: String?, bundleVersion: String?, architectures: [String],
            minimumSystemVersion: String?, sparklePublicKey: String?
        ) {
            self.signedIdentifier = signedIdentifier
            self.bundleIdentifier = bundleIdentifier
            self.teamIdentifier = teamIdentifier
            self.shortVersion = shortVersion
            self.bundleVersion = bundleVersion
            self.architectures = architectures
            self.minimumSystemVersion = minimumSystemVersion
            self.sparklePublicKey = sparklePublicKey
        }
    }

    /// Where an inspection stopped.
    public enum Stage: String, Codable, Sendable {
        case download, checksum, unpack, signature
    }

    public struct Failure: Error, Sendable {
        public let stage: Stage
        public let message: String
        /// What came over the network before it stopped; zero before the download
        /// finished.
        public let bytes: Int64
    }

    public struct Inspected: Sendable {
        public let bytes: Int64
        public let finalHost: String?
        public let kind: VendorInstallerKind
        /// The app routes. Nil for a package.
        public let identity: Identity?
        /// The pkg route: the Team of the package's Developer ID Installer
        /// certificate, which is what its gate 3 compares.
        public let packageTeamIdentifier: String?
        /// Things that were not checked, said out loud.
        public let notes: [String]
    }

    /// Download `remote`'s installer into `workDir` (which the caller owns and
    /// removes) and read it. `bundleName` names the bundle a `ContentsPayload`
    /// assembles — production takes it from the installed copy.
    public static func inspect(
        _ remote: RemoteVersion, bundleName: String, workDir: URL
    ) async -> Result<Inspected, Failure> {
        guard let url = remote.downloadURL, let kind = remote.vendorInstallerKind else {
            return .failure(Failure(stage: .download, message: "no installer resolved", bytes: 0))
        }
        let downloader = Downloader(destinationDir: workDir, purpose: .other) { _ in }
        let archive: URL
        do {
            let downloaded = try await downloader.download(url, headers: remote.downloadHeaders)
            archive = try VendorInstaller.normalizedArchive(downloaded, kind: kind, workDir: workDir)
        } catch {
            return .failure(Failure(
                stage: .download, message: error.localizedDescription,
                bytes: downloader.bytesDownloaded))
        }
        let bytes = downloader.bytesDownloaded
        func failure(_ stage: Stage, _ error: Error) -> Result<Inspected, Failure> {
            .failure(Failure(stage: stage, message: error.localizedDescription, bytes: bytes))
        }

        if kind == .pkg {
            return await inspectPackage(
                archive, remote: remote, kind: kind, bytes: bytes,
                finalHost: downloader.finalHost)
        }

        // The digest-only route's proof of origin runs before anything is
        // unpacked, as `VendorInstaller.applyVerified` runs it.
        if remote.installTrust == .publishedDigestOnly {
            let expected = remote.expectedSHA256
            do {
                _ = try await offCooperativePool {
                    try SignatureVerifier.verifyPublishedDigest(of: archive, expected: expected)
                }
            } catch { return failure(.checksum, error) }
        }

        let download = DownloadedUpdate(
            archiveURL: archive, bytesDownloaded: bytes, workDir: workDir,
            finalHost: downloader.finalHost)
        let app: URL
        do {
            app = try await VendorInstaller.unpackVerified(
                remote, download: download, bundleName: bundleName,
                onStage: { _ in }, vetStub: stubSealVerifies)
        } catch VendorInstaller.InstallError.checksumMismatch {
            return failure(.checksum, VendorInstaller.InstallError.checksumMismatch)
        } catch let error as SignatureVerifier.VerifyError {
            // The MyGo signature and an installer stub's seal both land here.
            return failure(.signature, error)
        } catch {
            return failure(.unpack, error)
        }

        do {
            let identity = try await offCooperativePool { () throws -> Identity in
                try SignatureVerifier.verifyCodeSignature(appAt: app)
                return try identity(of: app)
            }
            return .success(Inspected(
                bytes: bytes, finalHost: downloader.finalHost, kind: kind,
                identity: identity, packageTeamIdentifier: nil, notes: []))
        } catch { return failure(.signature, error) }
    }

    /// `vetStub` with no installed Team to hold an installer stub to: its seal
    /// must still verify, and the payload is then read like any other. Outside
    /// any `async` body because it only runs in `unpackVerified`'s off-pool hop.
    private static func stubSealVerifies(_ stub: URL) throws {
        try SignatureVerifier.verifyCodeSignature(appAt: stub)
    }

    /// Read the identity of a bundle on disk. Blocking; callers stay off the pool.
    static func identity(of app: URL) throws -> Identity {
        let plistURL = BundleLayout.infoPlistURL(for: app, fileManager: .default)
        let plist = (try? Data(contentsOf: plistURL)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        } ?? [:]
        let archs = SignatureVerifier.executableArchitectures(ofAppAt: app).map { arch -> String in
            switch arch {
            case NSBundleExecutableArchitectureARM64: return "arm64"
            case NSBundleExecutableArchitectureX86_64: return "x86_64"
            default: return String(arch)
            }
        }.sorted()
        return Identity(
            signedIdentifier: try SignatureVerifier.signingIdentifier(at: app),
            bundleIdentifier: plist["CFBundleIdentifier"] as? String,
            teamIdentifier: try SignatureVerifier.teamIdentifier(at: app),
            shortVersion: plist["CFBundleShortVersionString"] as? String,
            bundleVersion: plist["CFBundleVersion"] as? String,
            architectures: archs,
            minimumSystemVersion: SignatureVerifier.declaredMinimumSystemVersion(ofAppAt: app),
            sparklePublicKey: SignatureVerifier.embeddedEdPublicKey(at: app))
    }

    /// The pkg route's own gates, as far as they go without an installed copy:
    /// the published digests over the download, then `pkgutil --check-signature`.
    /// A package inside a disk image (Sunlogin) is `PackageInstaller`'s to find
    /// by the installed app's name, so it is reported as not opened rather than
    /// guessed at.
    private static func inspectPackage(
        _ archive: URL, remote: RemoteVersion, kind: VendorInstallerKind,
        bytes: Int64, finalHost: String?
    ) async -> Result<Inspected, Failure> {
        do {
            if let expected = remote.expectedSHA512 {
                try await offCooperativePool {
                    try VendorInstaller.verifyChecksum(archive, expectedBase64: expected)
                }
            }
            if let expected = remote.expectedSHA256 {
                try await offCooperativePool {
                    try VendorInstaller.verifySHA256(archive, expectedHex: expected)
                }
            }
        } catch {
            return .failure(Failure(stage: .checksum, message: error.localizedDescription, bytes: bytes))
        }
        guard isFlatPackage(archive) else {
            return .success(Inspected(
                bytes: bytes, finalHost: finalHost, kind: kind, identity: nil,
                packageTeamIdentifier: nil,
                notes: ["not a flat package — the package inside it was not opened"]))
        }
        let signature = await PackageInstaller.packageSignature(of: archive)
        guard signature.isValid else {
            return .failure(Failure(
                stage: .signature, message: "pkgutil --check-signature rejected the package",
                bytes: bytes))
        }
        return .success(Inspected(
            bytes: bytes, finalHost: finalHost, kind: kind, identity: nil,
            packageTeamIdentifier: signature.teamIdentifier, notes: []))
    }

    /// A flat package is a xar archive, which starts with `xar!`.
    private static func isFlatPackage(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data("xar!".utf8)
    }
}
