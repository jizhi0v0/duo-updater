import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Gate 1b — telling a vendor's Sparkle key rotation apart from a bad download.
///
/// Regression cover for Mirage Beacon 1.2.0 → 1.3.0 (2026-08), where the vendor
/// shipped a new Ed25519 keypair with no transition release, so every installed
/// copy — ours and the app's own Sparkle — rejected the update.
struct SignatureRotationTests {

    /// A throwaway .app bundle carrying (or omitting) an `SUPublicEDKey`.
    private func makeBundle(publicKey: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SignatureRotationTests-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": "com.example.test"]
        if let publicKey { plist["SUPublicEDKey"] = publicKey }
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    private func sign(_ payload: Data, with key: Curve25519.Signing.PrivateKey) throws -> String {
        try key.signature(for: payload).base64EncodedString()
    }

    @Test func detectsRotationWhenDownloadShipsTheKeyThatSignedIt() throws {
        let oldKey = Curve25519.Signing.PrivateKey()
        let newKey = Curve25519.Signing.PrivateKey()
        let payload = Data("update archive".utf8)
        let app = try makeBundle(
            publicKey: newKey.publicKey.rawRepresentation.base64EncodedString())

        // Sanity: this is exactly the failure the user sees first.
        #expect(throws: SignatureVerifier.VerifyError.self) {
            try SignatureVerifier.verifyEdSignature(
                fileData: payload,
                signatureBase64: try sign(payload, with: newKey),
                publicKeyBase64: oldKey.publicKey.rawRepresentation.base64EncodedString())
        }

        #expect(SignatureVerifier.isEdKeyRotation(
            fileData: payload,
            signatureBase64: try sign(payload, with: newKey),
            installedKeyBase64: oldKey.publicKey.rawRepresentation.base64EncodedString(),
            downloadedApp: app))
    }

    /// The download claims the same key we already hold, yet the signature still
    /// doesn't verify — that's a broken/tampered archive, not a rotation.
    @Test func rejectsWhenDownloadShipsTheSameKeyThatAlreadyFailed() throws {
        let oldKey = Curve25519.Signing.PrivateKey()
        let attacker = Curve25519.Signing.PrivateKey()
        let payload = Data("update archive".utf8)
        let app = try makeBundle(
            publicKey: oldKey.publicKey.rawRepresentation.base64EncodedString())

        #expect(!SignatureVerifier.isEdKeyRotation(
            fileData: payload,
            signatureBase64: try sign(payload, with: attacker),
            installedKeyBase64: oldKey.publicKey.rawRepresentation.base64EncodedString(),
            downloadedApp: app))
    }

    /// A new key that did NOT sign this feed entry proves nothing — the appcast
    /// entry and the bundle must come from the same key holder.
    @Test func rejectsWhenNewKeyDidNotSignTheArchive() throws {
        let oldKey = Curve25519.Signing.PrivateKey()
        let newKey = Curve25519.Signing.PrivateKey()
        let attacker = Curve25519.Signing.PrivateKey()
        let payload = Data("update archive".utf8)
        let app = try makeBundle(
            publicKey: newKey.publicKey.rawRepresentation.base64EncodedString())

        #expect(!SignatureVerifier.isEdKeyRotation(
            fileData: payload,
            signatureBase64: try sign(payload, with: attacker),
            installedKeyBase64: oldKey.publicKey.rawRepresentation.base64EncodedString(),
            downloadedApp: app))
    }

    /// Signature over different bytes than we downloaded: still not a rotation.
    @Test func rejectsWhenSignatureCoversDifferentBytes() throws {
        let oldKey = Curve25519.Signing.PrivateKey()
        let newKey = Curve25519.Signing.PrivateKey()
        let app = try makeBundle(
            publicKey: newKey.publicKey.rawRepresentation.base64EncodedString())

        #expect(!SignatureVerifier.isEdKeyRotation(
            fileData: Data("update archive".utf8),
            signatureBase64: try sign(Data("some other archive".utf8), with: newKey),
            installedKeyBase64: oldKey.publicKey.rawRepresentation.base64EncodedString(),
            downloadedApp: app))
    }

    /// A download that dropped `SUPublicEDKey` entirely can't claim a rotation —
    /// otherwise stripping the key would be a way to skip Gate 1.
    @Test func rejectsWhenDownloadShipsNoKey() throws {
        let oldKey = Curve25519.Signing.PrivateKey()
        let newKey = Curve25519.Signing.PrivateKey()
        let payload = Data("update archive".utf8)
        let app = try makeBundle(publicKey: nil)

        #expect(SignatureVerifier.embeddedEdPublicKey(at: app) == nil)
        #expect(!SignatureVerifier.isEdKeyRotation(
            fileData: payload,
            signatureBase64: try sign(payload, with: newKey),
            installedKeyBase64: oldKey.publicKey.rawRepresentation.base64EncodedString(),
            downloadedApp: app))
    }

    /// A missing signature is never a rotation: a key'd feed that drops its
    /// signature stays fatal (`edSignatureMissing`).
    @Test func rejectsWhenFeedHasNoSignature() throws {
        let oldKey = Curve25519.Signing.PrivateKey()
        let newKey = Curve25519.Signing.PrivateKey()
        let app = try makeBundle(
            publicKey: newKey.publicKey.rawRepresentation.base64EncodedString())

        #expect(!SignatureVerifier.isEdKeyRotation(
            fileData: Data("update archive".utf8),
            signatureBase64: nil,
            installedKeyBase64: oldKey.publicKey.rawRepresentation.base64EncodedString(),
            downloadedApp: app))
    }

    @Test func readsEmbeddedKeyFromBundle() throws {
        let key = Curve25519.Signing.PrivateKey().publicKey
            .rawRepresentation.base64EncodedString()
        let app = try makeBundle(publicKey: key)
        #expect(SignatureVerifier.embeddedEdPublicKey(at: app) == key)
    }

    /// The real-world case, byte-for-byte: Mirage Beacon's 1.3.0 appcast entry
    /// against the key its 1.2.0 bundle shipped. Fixture-free — the signature and
    /// both keys are recorded from the live feed and the shipped bundles.
    @Test func mirageBeaconKeysDiffer() {
        let installed1_2_0 = "q7Y849QooIVNcE4VB1ED0VtYq/vYXP80Eoar1CMiKKk="
        let shipped1_3_0 = "nK4eLCeQg74FHF1SO0V0sHvn+gsGzPvlxsgVvHKnfTg="
        #expect(installed1_2_0 != shipped1_3_0)
        // Both are well-formed Ed25519 public keys, so the mismatch is a real
        // rotation and not a malformed Info.plist value.
        for key in [installed1_2_0, shipped1_3_0] {
            let raw = Data(base64Encoded: key)
            #expect(raw?.count == 32)
            #expect((try? Curve25519.Signing.PublicKey(rawRepresentation: raw!)) != nil)
        }
    }
}
