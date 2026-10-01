import Foundation
import Security

/// Whether a command-line tool's binary may be run, by the rule the user agreed
/// on 2026-10-01: a binary DuoUpdater runs — to read its version, or to have it
/// update itself — must either carry its vendor's Developer ID (the Team ID), or
/// be byte for byte the build the vendor published for its version (its sha256
/// equals the vendor's own). Anything else is reported and never run.
///
/// The two answer different questions. A Developer ID signature says who made the
/// file, and its key is not on the download server, so a server that is taken
/// over cannot forge it; it does not say which version the file is. A matching
/// sha256 says the file is exactly what the vendor's server publishes for that
/// version, and nothing about who put it there. An ad hoc signature says neither:
/// anyone can ad hoc sign anything. So a tool that is only ever ad hoc signed
/// (rustup) can be trusted through a published hash alone, and a tool that moved
/// to Developer ID (uv from 0.12.12, Junie's newer builds) through its Team ID.
///
/// The same rule is asked again of the file an update leaves behind: an update
/// that ends in a file passing neither check is a failure, not "updated".
public enum CLIToolTrust {

    public enum Signature: String, Sendable, Codable {
        /// A valid Developer ID signature with the vendor's Team ID.
        case vendor
        /// Validly signed, by someone else — or not with a Developer ID.
        case otherSigner
        /// Ad hoc signed: no identity at all. Only a published hash can vouch for it.
        case adHoc
        /// No signature. Intel builds of rustup ship this way.
        case unsigned
        /// A signature that does not validate: the file changed after signing.
        case invalid
    }

    /// The file's signature, measured against `teamIdentifier`.
    ///
    /// Ad hoc is told apart before validity is asked: Junie 1543.24 shipped ad hoc
    /// with a seal that no longer validates (`codesign --verify` on the published
    /// build, 2026-10-01), and what decides an ad hoc file is its hash, not its
    /// seal. A Developer ID file whose seal fails is `invalid`, never trusted.
    public static func signature(of url: URL, teamIdentifier: String) -> Signature {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return .invalid
        }
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard status == errSecSuccess, let info = info as? [String: Any] else { return .invalid }
        // No identifier at all means no signature (the call succeeds on unsigned
        // code with next to nothing in it).
        guard info[kSecCodeInfoIdentifier as String] != nil else { return .unsigned }
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if flags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return .adHoc }
        let strict = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, strict, nil) == errSecSuccess else { return .invalid }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            developerIDRequirement(teamIdentifier: teamIdentifier) as CFString, [], &requirement
        ) == errSecSuccess, let requirement
        else { return .invalid }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess ? .vendor : .otherSigner
    }

    /// Developer ID and the Team ID, and nothing about the identifier: uv's arm64
    /// identifier is derived by the linker and changes every release
    /// (`uv-924a20a6cc8daa66` in 0.12.12, `uv-1dcedb59c92e2a84` in 0.12.21).
    /// Same certificate markers as fx's requirement (`FxInstall`).
    static func developerIDRequirement(teamIdentifier: String) -> String {
        "anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */"
            + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    /// The file's sha256, lowercase hex; nil when it cannot be read.
    public static func sha256(of url: URL) -> String? {
        try? BundleArchive.sha256(of: url)
    }

    /// Whether `actual` is the digest `published` names. Vendors publish digests
    /// in several shapes — bare hex, `<hex>  <name>`, `<hex> *./rustup-init`,
    /// `sha256:<hex>` — so the first hex run of 64 is taken, case-insensitively.
    /// Never true for a missing or malformed digest.
    public static func matches(_ actual: String?, published: String?) -> Bool {
        guard let actual = actual?.lowercased(), actual.count == 64,
              let published = published.flatMap(firstDigest)
        else { return false }
        return actual == published
    }

    static func firstDigest(in text: String) -> String? {
        let lower = text.lowercased()
        var run = ""
        for character in lower {
            if character.isHexDigit {
                run.append(character)
            } else {
                if run.count == 64 { return run }
                run = ""
            }
        }
        return run.count == 64 ? run : nil
    }

    /// A quarantined file is never run: launching one can put a Gatekeeper dialog
    /// on the user's screen from a background check. The tools' own installers and
    /// updaters fetch without quarantine (only `com.apple.provenance` on every
    /// file the 2026-10-01 measurements looked at); a binary dragged out of a
    /// browser download would carry it.
    public static func hasQuarantine(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }
}
