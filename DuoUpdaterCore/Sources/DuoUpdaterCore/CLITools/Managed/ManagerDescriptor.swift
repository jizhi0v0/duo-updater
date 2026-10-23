import Foundation

/// What the app needs to draw and schedule a manager: data, not code. One per
/// adapter; carried on every item the manager keeps (`ManagedItem.descriptor`),
/// so a status answers its lane, logo and pause rule without a lookup.
public struct ManagerDescriptor: Sendable, Equatable {
    public let id: ManagerID
    /// The group's title in the CLI tab: "mise tools", "uv tools", "uv Python",
    /// "pipx", "nvm Node", … Untranslated, like a tool's own name.
    public let displayName: String
    /// Who signs the manager's binary, as `wrongSigner` names them
    /// (`CLIToolWording.vendor(of:)`'s equivalent); nil when there is nothing to
    /// sign (a bash script, a Python package).
    public let signer: String?
    /// The asset the app draws the group's rows with ("cli-mise", "cli-uv",
    /// "cli-nvm", …); nil falls back to the terminal glyph.
    public let logo: String?
    public let tint: Tint
    /// `CLIToolsModel.lane(of:)`'s key: copies in one lane never update at once.
    /// A manager shares its own kind's lane when its command runs the same
    /// files — "uv" for uv tools and uv Python (`uv self update` replaces the
    /// binary they run), "mise", "nvm", "rust" for cargo (the toolchain's cargo
    /// compiles), else its own name.
    public let lane: String
    /// Whose GitHub API budget the manager's upgrade command spends from its own
    /// process (`CLIToolKind.updaterSpendsGitHubAPI`): mise's → `.ourTokenIfAny`;
    /// nil for a manager whose upgrade never asks api.github.com.
    public let updaterSpendsGitHubAPI: CLIToolKind.UpdaterGitHubAPI?
    /// How long one upgrade may run before it is stopped: minutes for a manager
    /// that compiles (pyenv, rbenv, cargo), `MiseUpdater.defaultDeadline`'s ten
    /// for the others.
    public let deadline: ChildProcess.Deadline

    public enum Tint: Sendable, Equatable {
        /// The label colour: a black brand, which would sink into a dark sidebar.
        case label
        /// The brand's own colour, 0…1 per channel.
        case rgb(red: Double, green: Double, blue: Double)
    }

    public init(
        id: ManagerID, displayName: String, signer: String?, logo: String?, tint: Tint, lane: String,
        updaterSpendsGitHubAPI: CLIToolKind.UpdaterGitHubAPI? = nil,
        deadline: ChildProcess.Deadline = ManagerDescriptor.defaultDeadline
    ) {
        self.id = id
        self.displayName = displayName
        self.signer = signer
        self.logo = logo
        self.tint = tint
        self.lane = lane
        self.updaterSpendsGitHubAPI = updaterSpendsGitHubAPI
        self.deadline = deadline
    }

    /// `MiseUpdater.defaultDeadline`'s: ten minutes, half a minute's grace.
    public static let defaultDeadline = ChildProcess.Deadline(
        terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// The provider id of this manager's `ManagedProvider`
    /// (`CLIToolProvider.id`): "managed:<manager>".
    public var providerID: String { Self.providerID(of: id) }

    public static func providerID(of manager: ManagerID) -> String { "managed:" + manager.rawValue }
}

/// The tool-wide facts a managed group's header reads (`CLIToolReport.Context
/// .managed`): the manager, and each install of it the check found.
public struct ManagerContext: Sendable, Equatable {
    public let descriptor: ManagerDescriptor
    public let roots: [ManagedRoot]

    public init(descriptor: ManagerDescriptor, roots: [ManagedRoot]) {
        self.descriptor = descriptor
        self.roots = roots
    }

    /// "mise 2026.10.7 · ~/.local/share/mise": the binary's version and the
    /// root, `home` written as `~` — the one at `root` when given (a group is
    /// one root), else every root one after another. Tool names, versions and
    /// paths: the same in every language.
    public func headerSummary(home: String, root: String? = nil) -> String? {
        let roots = root.map { path in self.roots.filter { $0.path == path } } ?? self.roots
        let parts = roots.map { root -> String in
            var line = ManagedItem.abbreviate(root.path, home: home)
            if let binary = root.binary, let version = binary.version {
                line = "\((binary.path as NSString).lastPathComponent) \(version) · " + line
            }
            return line
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
