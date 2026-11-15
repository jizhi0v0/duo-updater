import Foundation
import CryptoKit
import Testing
@testable import DuoUpdaterCore

struct ArtifactInspectionSparkleTests {
    @Test func signatureContinuityUsesTheRecordedKeyAndReportsRotationsWithoutAcceptingThem() throws {
        let key = Curve25519.Signing.PrivateKey()
        let other = Curve25519.Signing.PrivateKey()
        let bytes = Data("archive fixture".utf8)
        let signature = try key.signature(for: bytes).base64EncodedString()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let good = ArtifactInspection.sparkleArchiveSignature(data: bytes, signature: signature, publicKey: publicKey)
        #expect(good.verified && good.warnings.isEmpty)
        let changed = ArtifactInspection.sparkleArchiveSignature(
            data: bytes, signature: try other.signature(for: bytes).base64EncodedString(), publicKey: publicKey)
        #expect(!changed.verified && changed.warnings.count == 1)
        #expect(changed.warnings.first?.hasPrefix("sparkleArchiveSignatureChanged:") == true)
        let tampered = ArtifactInspection.sparkleArchiveSignature(
            data: Data("tampered archive".utf8), signature: signature, publicKey: publicKey)
        #expect(!tampered.verified && !tampered.warnings.isEmpty)
        let unsigned = ArtifactInspection.sparkleArchiveSignature(data: bytes, signature: nil, publicKey: publicKey)
        #expect(!unsigned.verified && !unsigned.warnings.isEmpty)
    }
}
