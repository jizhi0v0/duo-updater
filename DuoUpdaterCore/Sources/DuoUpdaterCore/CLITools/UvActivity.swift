import Foundation

/// Is something already updating uv right now?
///
/// `uv self update` takes no lock. It downloads the target version's installer
/// into a temporary directory and runs it, and waits for it; the installer
/// downloads the archive, checks its sha256, and moves `uv` and `uvx` into place
/// one after the other, then rewrites the receipt. Two at once would interleave
/// those moves and receipt writes.
///
/// What the process table shows meanwhile: the `<dir>/uv self update` that
/// started it, alive until the installer has finished — sampled every 0.2 s
/// through a 0.9.18 → 0.12.21 update in a scratch HOME on 2026-10-02, it was
/// there throughout (6 s). Its child is the installer, run by path under its
/// `#!/bin/sh` line: uv 0.12 saves it as `uv-installer.sh`
/// (`installer_filename`, `self_update.rs`); older uv goes through axoupdater,
/// which saves it as plain `installer.sh` — too common a name to read as uv's,
/// and the parent covers it. The sampling did not catch either child.
///
/// uv keeps one receipt per user, so a `self update` of *any* uv is a change to
/// the install the receipt names: every copy reads as busy while one runs. The
/// installer run by hand (`curl … | sh`) has no file name in its argv and is not
/// seen.
public enum UvActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        /// `uv self update` is running (pid).
        case selfUpdate(pid_t)
        /// uv's standalone installer is running (pid).
        case installer(pid_t)

        public var description: String {
            switch self {
            case .selfUpdate(let pid): return "uv self update is running (pid \(pid))"
            case .installer(let pid): return "the uv installer is running (pid \(pid))"
            }
        }
    }

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if isSelfUpdate(process.arguments) { return .selfUpdate(process.pid) }
            if isInstaller(process.arguments) { return .installer(process.pid) }
        }
        return nil
    }

    /// `uv … self update …`, however uv was named on the command line. `self`
    /// then `update` anywhere after argv[0], so a global option before the
    /// subcommand (`uv --verbose self update`) is not looked past; a stray match
    /// costs one withheld click.
    static func isSelfUpdate(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "uv" else { return false }
        let rest = Array(arguments.dropFirst())
        return zip(rest, rest.dropFirst()).contains { $0 == "self" && $1 == "update" }
    }

    /// A shell running a file named `uv-installer.sh` — the name `uv self update`
    /// saves the installer under.
    static func isInstaller(_ arguments: [String]) -> Bool {
        arguments.prefix(3).contains { ($0 as NSString).lastPathComponent == "uv-installer.sh" }
    }
}
