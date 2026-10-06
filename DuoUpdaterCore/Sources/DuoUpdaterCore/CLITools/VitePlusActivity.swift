import Foundation

/// Is something already changing Vite+?
///
/// `vp upgrade` takes no lock (`commands/upgrade/mod.rs` at v1.0.0): it installs
/// the new version's directory, then swaps `current`. Two at once would race on
/// the same directory and the swap. So a running `vp upgrade` (or `vp implode`,
/// which removes everything) is busy, and so is the installer while it
/// downloads from the registry with curl. `vp upgrade --check` changes nothing.
///
/// Not seen: the installer's hand-off, a `vp` in a temporary directory run with
/// no arguments, and `vp`'s own background update check — which only writes its
/// cache and prints a notice; it never installs.
public enum VitePlusActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case command(String, pid_t)
        case installer(pid_t)

        public var description: String {
            switch self {
            case .command(let name, let pid): return "vp \(name) is running (pid \(pid))"
            case .installer(let pid): return "the Vite+ installer is downloading (pid \(pid))"
            }
        }
    }

    public static func busy(processes: [NpmActivity.Process]) -> Busy? {
        for process in processes {
            if let command = changingCommand(process.arguments) { return .command(command, process.pid) }
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains("/@voidzero-dev/vite-plus-cli-") || $0.contains("://vite.plus") })
            else { continue }
            return .installer(process.pid)
        }
        return nil
    }

    /// `upgrade` or `implode` when that is `vp`'s subcommand — the first word
    /// after its options, `-C <dir>` included — so a project task named
    /// `upgrade` (`vp run upgrade`) is not one; nil otherwise.
    static func changingCommand(_ arguments: [String]) -> String? {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "vp" else { return nil }
        var rest = arguments.dropFirst()
        while let word = rest.first {
            rest = rest.dropFirst()
            if word == "-C" {
                rest = rest.dropFirst()
            } else if word.hasPrefix("-") {
                continue
            } else if word == "upgrade" {
                return rest.contains("--check") ? nil : word
            } else {
                return word == "implode" ? word : nil
            }
        }
        return nil
    }
}
