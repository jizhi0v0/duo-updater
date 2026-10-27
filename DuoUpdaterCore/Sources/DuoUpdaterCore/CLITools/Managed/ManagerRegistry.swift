import Foundation

/// The one list a new manager is added to. Order = order of the managed groups
/// in the CLI tab, after every standalone kind (D12).
///
/// P1 (plans/cli-managers-redesign.md §8.1) registered mise's tools, P2 uv's
/// tools and pipx; P3 adds the version lines, P4 cargo and go.
public enum ManagerRegistry {
    /// Every manager, reading `home`.
    public static func all(home: URL) -> [any ManagerAdapter] {
        [MiseToolsAdapter(home: home), UvToolAdapter(home: home), UvPythonAdapter(home: home), PipxAdapter(home: home)]
    }

    /// Every manager, reading this user's home.
    public static let adapters: [any ManagerAdapter] = all(home: FileManager.default.homeDirectoryForCurrentUser)

    /// One `ManagedProvider` per adapter, for `CLITools.providers()`: adapter
    /// and provider read the same home.
    public static func providers(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [any CLIToolProvider] {
        all(home: home).map { ManagedProvider($0, home: home) }
    }

    /// The descriptor of a registered manager; nil for one not registered (a
    /// test's fake, which carries its descriptor on every item instead).
    public static func descriptor(of manager: ManagerID) -> ManagerDescriptor? {
        adapters.first { $0.descriptor.id == manager }?.descriptor
    }
}
