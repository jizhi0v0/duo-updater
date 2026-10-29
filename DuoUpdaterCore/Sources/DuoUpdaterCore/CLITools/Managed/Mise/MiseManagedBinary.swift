import Foundation

/// The mise that runs a managed tool's commands, as `UvManagedBinary` is for
/// uv. `MiseScanner` deliberately tracks only the standalone installer's copy
/// (`~/.local/bin/mise`) because that is the one `mise self-update` owns; a
/// Homebrew keg belongs to `brew upgrade mise`. That ownership rule is right
/// for mise's own row, but it must not stop a Homebrew-only Mac from running
/// `mise ls/outdated/upgrade` for the tools mise installed.
///
/// Preference is unchanged when both exist: a runnable standalone mise wins,
/// and Homebrew's keg is the fallback when there is no runnable standalone copy
/// — absent, untrusted or quarantined. A Homebrew mise is trusted by the keg
/// rule (D5.1); its build is ad hoc signed, not by Jeffrey Dickey's Team.
enum MiseManagedBinary {

    /// The binary a managed mise group should use. A runnable standalone copy
    /// wins; otherwise a Homebrew keg; otherwise the standalone copy as found,
    /// so its own trust problem is what the row reports.
    static func resolve(standalone: MiseInstall?, homebrew: ManagedRoot.Binary?) -> ManagedRoot.Binary? {
        let standalone = MiseToolsAdapter.binary(standalone)
        if let standalone, standalone.trust.runnable { return standalone }
        if let homebrew { return homebrew }
        return standalone
    }

    /// `/opt/homebrew/bin/mise` or `/usr/local/bin/mise`, when it is the keg's
    /// own `bin/mise` and the keg has its install receipt. Blocking; nil when
    /// none.
    static func homebrew(
        roots: [String] = ["/opt/homebrew", "/usr/local"],
        contents: (String) -> Data? = { FileManager.default.contents(atPath: $0) },
        isQuarantined: (String) -> Bool = { CLIToolTrust.hasQuarantine(URL(fileURLWithPath: $0)) }
    ) -> ManagedRoot.Binary? {
        for root in roots {
            let link = root + "/bin/mise"
            let resolved = URL(fileURLWithPath: link).resolvingSymlinksInPath().path
            guard let version = HomebrewKeg.version(
                of: resolved, prefix: root, formula: "mise", paths: [["bin", "mise"]], contents: contents)
            else { continue }
            let trust: ManagedRoot.Trust = isQuarantined(resolved) ? .quarantined : .homebrewKeg
            return ManagedRoot.Binary(path: link, version: version, trust: trust)
        }
        return nil
    }
}
