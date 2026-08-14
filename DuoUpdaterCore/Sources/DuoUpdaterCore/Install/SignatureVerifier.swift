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
        case noBundleIdentifier(which: String)
        case bundleIdentifierMismatch(installed: String, downloaded: String)

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
            case .noBundleIdentifier(let which):
                return "Could not read a signed bundle identifier from the \(which) app."
            case .bundleIdentifierMismatch(let installed, let downloaded):
                return "Bundle identifier mismatch: installed “\(installed)” vs downloaded “\(downloaded)”. Refusing to install."
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

    // MARK: Gate 1b — vendor rotated its Sparkle signing key

    /// True when an `edSignatureInvalid` failure is explained by the vendor
    /// having rotated its Sparkle key: the downloaded bundle ships a DIFFERENT
    /// `SUPublicEDKey` than the installed one, and the feed's signature verifies
    /// against that new key.
    ///
    /// This happens when a vendor generates a fresh Ed25519 keypair without
    /// shipping a transition release signed by the old key — the installed app's
    /// own Sparkle rejects the update just as we do, so the update chain is
    /// broken until the user installs by hand. (Observed 2026-08: Mirage Beacon
    /// 1.2.0 → 1.3.0.)
    ///
    /// Verifying against a key that came out of the same download is
    /// deliberately NOT a trust claim — it is circular, and proves only that the
    /// appcast entry and the bundle were minted by the same key holder (so a
    /// stale or mismatched feed entry still fails). ALL of the trust in this path
    /// comes from Gates 2/3/4 running afterwards — valid Developer ID code
    /// signature, same Team ID, same signed bundle id as installed — exactly the
    /// gate the Vendor/GitHub paths carry on their own, and it fails closed.
    /// Callers must therefore treat a `true` here as "keep going and let Gates
    /// 2/3/4 decide", never as "this download is verified".
    public static func isEdKeyRotation(
        fileData: Data,
        signatureBase64: String?,
        installedKeyBase64: String,
        downloadedApp: URL
    ) -> Bool {
        guard
            let newKey = embeddedEdPublicKey(at: downloadedApp),
            newKey != installedKeyBase64
        else { return false }
        do {
            try verifyEdSignature(
                fileData: fileData,
                signatureBase64: signatureBase64,
                publicKeyBase64: newKey
            )
            return true
        } catch {
            return false
        }
    }

    /// The `SUPublicEDKey` an app bundle ships in its `Info.plist`, or nil when
    /// it has none (an unsigned Sparkle feed).
    public static func embeddedEdPublicKey(at appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any],
            let key = (plist["SUPublicEDKey"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else { return nil }
        return key
    }

    // MARK: Gate 2 — code signature validity of the extracted app

    /// Run the equivalent of `codesign --verify --deep --strict` against the app
    /// bundle. `kSecCSCheckNestedCode` is essential: without it only the top-level
    /// seal is checked, so a tampered framework/helper/XPC service embedded in the
    /// bundle would pass. `kSecCSStrictValidate` rejects bundles with extra
    /// unsigned files or resource-rule tricks. This is the central code-trust gate
    /// for the Vendor/GitHub paths (no EdDSA there), so it must be deep.
    public static func verifyCodeSignature(appAt url: URL) throws {
        let code = try staticCode(at: url)
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures
            | kSecCSCheckNestedCode | kSecCSStrictValidate)
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
        try signingInfo(at: url)[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: Gate 4 — signed bundle identifier must match the installed app

    /// Belt-and-suspenders on top of the Team ID gate: the downloaded build must
    /// carry the SAME signed identifier as the app it's replacing. Team ID alone
    /// permits any app from the same vendor (Google's Chrome vs Earth); this pins
    /// the swap to the exact product. We read the *signed* identifier
    /// (`kSecCodeInfoIdentifier`), not the raw Info.plist, so it's covered by the
    /// code seal already verified in Gate 2 and can't be spoofed.
    public static func verifyBundleIdentifierMatch(
        installedApp: URL,
        downloadedApp: URL
    ) throws {
        guard let installedID = try signingIdentifier(at: installedApp) else {
            throw VerifyError.noBundleIdentifier(which: "installed")
        }
        guard let downloadedID = try signingIdentifier(at: downloadedApp) else {
            throw VerifyError.noBundleIdentifier(which: "downloaded")
        }
        guard installedID == downloadedID else {
            throw VerifyError.bundleIdentifierMismatch(
                installed: installedID, downloaded: downloadedID
            )
        }
    }

    public static func signingIdentifier(at url: URL) throws -> String? {
        try signingInfo(at: url)[kSecCodeInfoIdentifier as String] as? String
    }

    private static func signingInfo(at url: URL) throws -> [String: Any] {
        let code = try staticCode(at: url)
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        let status = SecCodeCopySigningInformation(code, flags, &info)
        guard status == errSecSuccess, let dict = info as? [String: Any] else {
            throw VerifyError.codeSignatureInvalid(status)
        }
        return dict
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
