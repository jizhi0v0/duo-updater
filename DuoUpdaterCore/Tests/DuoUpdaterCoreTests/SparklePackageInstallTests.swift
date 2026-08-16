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
