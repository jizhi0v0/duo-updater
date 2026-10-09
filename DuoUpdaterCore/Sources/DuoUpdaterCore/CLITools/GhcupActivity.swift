import Foundation

/// Is something already replacing ghcup?
///
/// `ghcup upgrade` takes no lock on the binary (`GHCup.Command.Upgrade`,
/// v0.2.6.2): it downloads the new binary with `curl` into ghcup's temporary
/// directory, deletes `~/.ghcup/bin/ghcup` and copies the new one in. Two at
/// once would race that delete and copy, so a click does not start one beside a
/// running `ghcup upgrade`. A `curl` fetching a ghcup binary from
/// downloads.haskell.org is busy too — whichever runs it, `ghcup upgrade` or
/// the bootstrap script run by hand.
///
/// Not seen: ghcup installing a toolchain, which does not touch its own binary.
public enum GhcupActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case upgrade(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .upgrade(let pid): return "ghcup upgrade is running (pid \(pid))"
            case .download(let pid): return "a ghcup release is being downloaded (pid \(pid))"
            }
        }
    }

    /// `downloads.haskell.org/~ghcup/<ver>/<arch>-apple-darwin-ghcup-<ver>`.
    static let assetPath = "downloads.haskell.org/~ghcup/"
    static let assetName = "-apple-darwin-ghcup-"

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if isUpgrade(process.arguments) { return .upgrade(process.pid) }
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains(assetPath) && $0.contains(assetName) })
            else { continue }
            return .download(process.pid)
        }
        return nil
    }

    /// `ghcup … upgrade`, however ghcup was named. Any argument, so a global
    /// option with a value before the subcommand (`ghcup --url-source X upgrade`)
    /// is not looked past; a stray match costs one withheld click.
    static func isUpgrade(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "ghcup" else { return false }
        return arguments.dropFirst().contains("upgrade")
    }
}
