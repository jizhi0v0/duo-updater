import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct SparklePackageInstallTests {
    @Test func signedPackageKeepsSparkleEdDSAGate() throws {
        let bytes = Data("signed package enclosure".utf8)
        let key = Curve25519.Signing.PrivateKey()
        let signature = try key.signature(for: bytes).base64EncodedString()
        let file = try temporaryFile(bytes)
        defer { try? FileManager.default.removeItem(at: file) }

        let result = packageResult(
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            signature: signature)

        let fingerprint = try InstallCoordinator.verifyInstallerDownload(file, for: result) { _ in }
        let expected = try PackageInstaller.contentFingerprint(of: file)
        #expect(fingerprint == expected)
    }

    @Test func tamperedPackageIsRejectedBeforeInstaller() throws {
        let original = Data("original package enclosure".utf8)
        let key = Curve25519.Signing.PrivateKey()
        let signature = try key.signature(for: original).base64EncodedString()
        let file = try temporaryFile(Data("tampered package enclosure".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        let result = packageResult(
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            signature: signature)

        #expect(throws: SignatureVerifier.VerifyError.self) {
            try InstallCoordinator.verifyInstallerDownload(file, for: result) { _ in }
        }
    }

    /// AdGuard 2.20's item, verbatim from its live feed (2026-10-15) apart from
    /// a shortened signature and dropped notes link: a `.dmg` whose root holds
    /// only `AdGuard.pkg`, declared through `sparkle:installationType`.
    private static let adGuardFeed = """
        <?xml version='1.0' encoding='UTF-8'?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>Version 2.20</title>
              <sparkle:version>2626</sparkle:version>
              <sparkle:shortVersionString>2.20</sparkle:shortVersionString>
              <enclosure url="https://static.adtidy.org/mac/release/AdGuard-2.20.0.2626.dmg" type="application/octet-stream" sparkle:edSignature="sig" length="112485149" sparkle:installationType="package"></enclosure>
            </item>
          </channel>
        </rss>
        """

    @Test func installationTypeIsReadFromTheEnclosure() throws {
        let items = SparkleAppcastParser.parse(Data(Self.adGuardFeed.utf8), preferredLanguages: ["en-US"])
        #expect(items.count == 1)
        #expect(items.first?.installationType == "package")
        #expect(items.first?.enclosureURL?.pathExtension == "dmg")
    }

    /// The user-reported failure: AdGuard's `.dmg` went down the in-place swap,
    /// whose `ArchiveExtractor` found only a `.pkg` and threw "No .app bundle was
    /// found inside the archive." A declared package enclosure belongs to the
    /// system installer route whatever its extension.
    @Test func aDeclaredPackageDmgRoutesToTheInstallerNotTheSwap() {
        let signed = dmgResult(publicKey: "key", signature: "sig", declaredPackage: true)
        let env = InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        #expect(UpdatePolicy.requiresInstaller(signed, environment: env))
        #expect(!UpdatePolicy.canAutoInstall(signed, settings: Self.settings, environment: env))

        // Unsigned: no installer route (a package has no bundle-id gate), and
        // still no swap — the swap would fail the same way.
        let unsigned = dmgResult(publicKey: nil, signature: nil, declaredPackage: true)
        #expect(!UpdatePolicy.requiresInstaller(unsigned, environment: env))
        #expect(!UpdatePolicy.canAutoInstall(unsigned, settings: Self.settings, environment: env))

        // An ordinary `.dmg` with no declaration is still the swap.
        let app = dmgResult(publicKey: "key", signature: "sig", declaredPackage: false)
        #expect(!UpdatePolicy.requiresInstaller(app, environment: env))
        #expect(UpdatePolicy.canAutoInstall(app, settings: Self.settings, environment: env))
    }

    private static let settings = UpdateSettings(
        appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning)

    private func dmgResult(publicKey: String?, signature: String?, declaredPackage: Bool) -> UpdateResult {
        let app = InstalledApp(
            name: "AdGuard", bundleID: "com.adguard.mac.adguard",
            shortVersion: "2.19.0.2258", buildVersion: "2258",
            path: URL(fileURLWithPath: "/Applications/AdGuard.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://static.adtidy.org/mac/release/adguard-release-appcast.xml"),
            sparkleEdPublicKey: publicKey)
        let remote = RemoteVersion(
            shortVersion: "2.20", version: "2626",
            downloadURL: URL(string: "https://static.adtidy.org/mac/release/AdGuard-2.20.0.2626.dmg"),
            edSignature: signature, sourceName: "Sparkle",
            sparklePackageEnclosure: declaredPackage)
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "2.20"))
    }

    private func packageResult(publicKey: String, signature: String) -> UpdateResult {
        let app = InstalledApp(
            name: "Fixture", bundleID: "com.example.fixture",
            shortVersion: "1", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/Fixture.app"),
            isMASApp: false, sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
            sparkleEdPublicKey: publicKey)
        let remote = RemoteVersion(
            shortVersion: "2", version: nil,
            downloadURL: URL(string: "https://example.com/Fixture.pkg"),
            edSignature: signature, sourceName: "Sparkle")
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "2"))
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparkle-package-\(UUID().uuidString).pkg")
        try data.write(to: url)
        return url
    }
}
