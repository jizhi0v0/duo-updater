import Foundation

/// Is the manager already moving its items right now? A process is told by
/// what it executes and its argv, as bun's and mise's are (`BunActivity`,
/// `MiseActivity`): no manager here documents a lock the app could read.
public enum ManagedActivity {

    /// The first running `binary <subcommand>` whose subcommand is in
    /// `subcommands` — "install", "upgrade", "use" for mise — as the English
    /// line the row's `.busy` carries; nil when none runs. A global option with
    /// a value before the subcommand (`mise -C dir upgrade`) is looked past by
    /// finding the subcommand anywhere after the executable.
    public static func running(
        binary: String, subcommands: Set<String>, processes: [NpmActivity.Process]
    ) -> String? {
        let name = (binary as NSString).lastPathComponent
        for process in processes where BunActivity.isBun(process, bun: binary) {
            if let subcommand = process.arguments.dropFirst().first(where: { subcommands.contains($0) }) {
                return "\(name) \(subcommand) is running (pid \(process.pid))"
            }
        }
        return nil
    }
}
