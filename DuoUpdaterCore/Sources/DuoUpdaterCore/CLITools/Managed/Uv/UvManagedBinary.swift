import Foundation

/// The uv that runs a managed group's commands — `uv tool …` and
/// `uv python …` — as opposed to the uv `UvScanner` tracks for its own row and
/// `uv self update`.
///
/// The distinction matters because the two questions have different answers:
///
/// - **Who updates the uv binary?** The standalone installer's copy
///   (`~/.local/bin/uv`, `~/.cargo/bin/uv`) is uv's, and `uv self update` is
///   offered for it. Homebrew's uv belongs to `brew upgrade uv`, so
///   `UvScanner` deliberately does not look at it (`UvInstall`'s note).
/// - **Which uv may run a managed command?** Either one. `uv tool` and
///   `uv python` write only uv's own data (`~/.local/share/uv`), never the
///   binary, so a Homebrew keg is a fine runner. Refusing it left a
///   Homebrew-only Mac with rows it could see but never check or update.
///
/// Preference is unchanged when both exist: a standalone uv that may run is
/// used first (it is the copy `uv self update` owns), and Homebrew's uv is the
/// fallback when there is no runnable standalone copy — absent, untrusted or
/// quarantined. A Homebrew uv is trusted by the keg rule (D5.1), not by
/// Astral's signature: the formula's build is ad hoc signed.
enum UvManagedBinary {

    /// The binary a managed uv group should use. A runnable standalone copy
    /// wins; otherwise a Homebrew keg; otherwise the standalone copy as found,
    /// so its own trust problem is what the row reports.
    static func resolve(standalone: UvInstall?, homebrew: ManagedRoot.Binary?) -> ManagedRoot.Binary? {
        let standalone = UvToolAdapter.binary(standalone)
        if let standalone, standalone.trust.runnable { return standalone }
        if let homebrew { return homebrew }
        return standalone
    }

    /// `/opt/homebrew/bin/uv` or `/usr/local/bin/uv`, when it is the keg's own
    /// `bin/uv` and the keg has its install receipt. Blocking; nil when none.
    static func homebrew(
        roots: [String] = ["/opt/homebrew", "/usr/local"],
        contents: (String) -> Data? = { FileManager.default.contents(atPath: $0) },
        isQuarantined: (String) -> Bool = { CLIToolTrust.hasQuarantine(URL(fileURLWithPath: $0)) }
    ) -> ManagedRoot.Binary? {
        for root in roots {
            let link = root + "/bin/uv"
            let resolved = URL(fileURLWithPath: link).resolvingSymlinksInPath().path
            guard let version = HomebrewKeg.version(
                of: resolved, prefix: root, formula: "uv", paths: [["bin", "uv"]], contents: contents)
            else { continue }
            let trust: ManagedRoot.Trust = isQuarantined(resolved) ? .quarantined : .homebrewKeg
            return ManagedRoot.Binary(path: link, version: version, trust: trust)
        }
        return nil
    }
}
