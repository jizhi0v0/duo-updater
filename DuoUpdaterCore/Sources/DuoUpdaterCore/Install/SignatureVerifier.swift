import Foundation
import CryptoKit
import Security

/// The three security gates a downloaded Sparkle update must pass before we
/// will install it. Any failure aborts the install.
public enum SignatureVerifier {

    public enum VerifyError: LocalizedError {
        case edSignatureMissing
        case edSignatureInvalid
        case codeSignatureInvalid(OSStatus)
        case noTeamIdentifier(which: String)
        case teamIdentifierMismatch(installed: String, downloaded: String)

        public var errorDescription: String? {
            switch self {
            case .edSignatureMissing:
                return "The update feed provided no EdDSA signature."
            case .edSignatureInvalid:
                return "The download's EdDSA signature did not match the app's public key."
            case .codeSignatureInvalid(let status):
                return "The downloaded app's code signature is invalid (OSStatus \(status))."
            case .noTeamIdentifier(let which):
                return "Could not read a Team Identifier from the \(which) app."
            case .teamIdentifierMismatch(let installed, let downloaded):
                return "Team Identifier mismatch: installed “\(installed)” vs downloaded “\(downloaded)”. Refusing to install."
            }
        }
    }

    // MARK: Gate 1 — EdDSA signature over the downloaded file

    /// Verify the Sparkle Ed25519 signature of `fileData` against the app's
    /// `SUPublicEDKey`. Both signature and key are base64.
    public static func verifyEdSignature(
        fileData: Data,
        signatureBase64: String?,
        publicKeyBase64: String
    ) throws {
        guard let signatureBase64, !signatureBase64.isEmpty else {
            throw VerifyError.edSignatureMissing
        }
        guard
            let signature = Data(base64Encoded: signatureBase64),
            let publicKeyRaw = Data(base64Encoded: publicKeyBase64),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw)
        else {
            throw VerifyError.edSignatureInvalid
        }
        guard publicKey.isValidSignature(signature, for: fileData) else {
            throw VerifyError.edSignatureInvalid
        }
    }

    // MARK: Gate 2 — code signature validity of the extracted app

    /// Run the equivalent of `codesign --verify --deep` against the app bundle.
    public static func verifyCodeSignature(appAt url: URL) throws {
        let code = try staticCode(at: url)
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        let status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else {
            throw VerifyError.codeSignatureInvalid(status)
        }
    }

    // MARK: Gate 3 — Team Identifier must match the installed app

    /// The single most important gate: the new build must be signed by the
    /// same developer team as what's already installed, so a hijacked feed
    /// can't swap in a different vendor's (or malicious) binary.
    public static func verifyTeamIdentifierMatch(
        installedApp: URL,
        downloadedApp: URL
    ) throws {
        guard let installedTeam = try teamIdentifier(at: installedApp) else {
            throw VerifyError.noTeamIdentifier(which: "installed")
        }
        guard let downloadedTeam = try teamIdentifier(at: downloadedApp) else {
            throw VerifyError.noTeamIdentifier(which: "downloaded")
        }
        guard installedTeam == downloadedTeam else {
            throw VerifyError.teamIdentifierMismatch(
                installed: installedTeam, downloaded: downloadedTeam
            )
        }
    }

    public static func teamIdentifier(at url: URL) throws -> String? {
        let code = try staticCode(at: url)
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        let status = SecCodeCopySigningInformation(code, flags, &info)
        guard status == errSecSuccess, let dict = info as? [String: Any] else {
            throw VerifyError.codeSignatureInvalid(status)
        }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw VerifyError.codeSignatureInvalid(status)
        }
        return staticCode
    }
}
