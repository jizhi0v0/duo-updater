import Foundation
import Security

/// The Developer ID team of the **running binary**, read from its own signature.
///
/// The app and the helper each pin the other with a code-signing requirement, and
/// the team OU is the load-bearing clause in both: without it the requirement is
/// satisfied by anything Apple-anchored with the right bundle id, which anyone can
/// produce. Hard-coding one team worked while there was exactly one build of this
/// app; a fork signing with its own Developer ID would build and run fine, then
/// have the helper reject it — silently, since the failure surfaces only as Mac
/// App Store installs never starting.
///
/// Deriving it instead means the requirement always names *this* build's team, so
/// a fork is correct with no source edit, while the guarantee is unchanged: the
/// peer must be signed by the same team as the process doing the checking.
///
/// **Fails closed.** An unsigned or ad-hoc binary has no team identifier, so this
/// returns nil and the caller must refuse the connection rather than fall back to
/// a team-less requirement. (`scripts/install.sh` already refuses to deploy an
/// ad-hoc build, so this is unreachable in a real install.)
enum OwnTeamIdentifier {

    /// Resolved once: the signature cannot change while the process is alive.
    static let current: String? = read()

    private static func read() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return nil }

        // Validate BEFORE reading. Apple's SecCode.h is explicit that
        // `SecCodeCopySigningInformation` does no validation of its own: "If the
        // signing data for the code is corrupt or invalid, this call may fail or it
        // may return partial data. To ensure that only valid data is returned […]
        // you must successfully call one of the CheckValidity functions on the code
        // before calling CopySigningInformation." Since the team identifier we pull
        // out here is the load-bearing clause of a root XPC trust decision, reading
        // it out of unvalidated data would be exactly the wrong shortcut.
        //
        // Validating the *dynamic* code is the part that matters: the same header
        // notes that for Code objects some signing information comes from disk, and
        // CheckValidity is what confirms the on-disk content still matches the
        // running code. Swift's typed API then requires a SecStaticCode to read the
        // information from (the C entry point accepts either), so the static handle
        // below is a language requirement, not a second, weaker source of truth.
        guard SecCodeCheckValidity(selfCode, [], nil) == errSecSuccess else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }

        // Ad-hoc signatures carry no team identifier; treat empty as absent so an
        // empty OU can never be spliced into a requirement string.
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        return (team?.isEmpty == false) ? team : nil
    }

    /// Build `anchor apple generic and identifier "<id>" and certificate
    /// leaf[subject.OU] = "<our team>"`, or nil when our own team is unknown.
    ///
    /// The identifier is a compile-time constant in both call sites, and the team
    /// comes from our own signature, so neither can carry attacker-controlled text
    /// into the requirement string.
    static func requirement(bundleIdentifier: String) -> String? {
        guard let team = current else { return nil }
        return "anchor apple generic and identifier \"\(bundleIdentifier)\" "
            + "and certificate leaf[subject.OU] = \"\(team)\""
    }
}
