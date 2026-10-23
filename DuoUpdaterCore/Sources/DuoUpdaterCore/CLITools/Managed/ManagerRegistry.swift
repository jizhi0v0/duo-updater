import Foundation

/// The one list a new manager is added to. Order = order of the managed groups
/// in the CLI tab, after every standalone kind (D12).
///
/// Empty in P0 (plans/cli-managers-redesign.md §8.1): the plumbing is in, no
/// manager is visible. P1 adds `MiseToolsAdapter()`, P2 uv tool and pipx, P3
/// the version lines, P4 cargo and go.
public enum ManagerRegistry {
    public static let adapters: [any ManagerAdapter] = []

    /// One `ManagedProvider` per adapter, for `CLITools.providers()`.
    public static func providers(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [any CLIToolProvider] {
        adapters.map { ManagedProvider($0, home: home) }
    }

    /// The descriptor of a registered manager; nil for one not registered (a
    /// test's fake, which carries its descriptor on every item instead).
    public static func descriptor(of manager: ManagerID) -> ManagerDescriptor? {
        adapters.first { $0.descriptor.id == manager }?.descriptor
    }
}
