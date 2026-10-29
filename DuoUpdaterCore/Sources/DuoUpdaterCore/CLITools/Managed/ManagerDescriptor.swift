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
    /// How the manager's versions are ordered by the shared rules
    /// (`ManagedCheck`): Python packages by PEP 440, where `1.0.post1` is
    /// newer than `1.0` — `VersionComparator` reads it as older.
    public let versionOrder: VersionOrder

    public enum VersionOrder: Sendable, Equatable {
        case generic
        case pep440

        func compare(_ a: String, _ b: String) -> ComparisonResult {
            if self == .pep440, let x = PythonVersion(a), let y = PythonVersion(b) { return PythonVersion.compare(x, y) }
            return VersionComparator.compare(a, b)
        }

        func isNewer(_ candidate: String, than current: String) -> Bool {
            compare(candidate, current) == .orderedDescending
        }
    }

    public enum Tint: Sendable, Equatable {
        /// The label colour: a black brand, which would sink into a dark sidebar.
        case label
        /// The brand's own colour, 0…1 per channel.
        case rgb(red: Double, green: Double, blue: Double)
    }

    public init(
        id: ManagerID, displayName: String, signer: String?, logo: String?, tint: Tint, lane: String,
        updaterSpendsGitHubAPI: CLIToolKind.UpdaterGitHubAPI? = nil,
        deadline: ChildProcess.Deadline = ManagerDescriptor.defaultDeadline, versionOrder: VersionOrder = .generic
    ) {
        self.id = id
        self.displayName = displayName
        self.signer = signer
        self.logo = logo
        self.tint = tint
        self.lane = lane
        self.updaterSpendsGitHubAPI = updaterSpendsGitHubAPI
        self.deadline = deadline
        self.versionOrder = versionOrder
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

    /// "uv 0.13.4", or "fnm 1.39.0 · ~/.local/share/fnm" when the manager has
    /// more than one root: the binary's name and version, `home` written as `~`.
    ///
    /// The binary's path and the data root are in ``headerTooltip(home:root:)``
    /// instead. A path in the header buried the one thing the header is for —
    /// which manager and version — and the rows below already name their own
    /// install paths. The root stays on a multi-root manager's line (pipx, fnm,
    /// nvm), because two groups of the same binary would otherwise read
    /// identically and the root is what tells them apart. A group with no binary
    /// has only its root to name.
    public func headerSummary(home: String, root: String? = nil) -> String? {
        let roots = root.map { path in self.roots.filter { $0.path == path } } ?? self.roots
        let severalRoots = self.roots.count > 1
        var seen: Set<String> = []
        var parts: [String] = []
        for root in roots {
            let line: String
            if let binary = root.binary {
                var summary = binary.version.map {
                    "\((binary.path as NSString).lastPathComponent) \($0)"
                } ?? (binary.path as NSString).lastPathComponent
                if severalRoots { summary += " · " + ManagedItem.abbreviate(root.path, home: home) }
                line = summary
            } else {
                line = ManagedItem.abbreviate(root.path, home: home)
            }
            if seen.insert(line).inserted { parts.append(line) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The hover text behind a managed group's info icon: the binary that runs
    /// the group and the data root it reads, `home` written as `~` — the one at
    /// `root` when given, else every root one after another.
    public func headerTooltip(home: String, root: String? = nil) -> String? {
        let roots = root.map { path in self.roots.filter { $0.path == path } } ?? self.roots
        var seen: Set<String> = []
        var parts: [String] = []
        for root in roots {
            var lines: [String] = []
            if let binary = root.binary {
                lines.append("Binary: " + ManagedItem.abbreviate(binary.path, home: home))
            }
            lines.append("Data: " + ManagedItem.abbreviate(root.path, home: home))
            let text = lines.joined(separator: "\n")
            if seen.insert(text).inserted { parts.append(text) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// One root's real paths, unabbreviated: what the info popover puts on the
    /// pasteboard. The tooltip abbreviates `home`; a copied path must work as
    /// typed, so this keeps it whole.
    public struct Paths: Sendable, Equatable {
        public let binary: String?
        public let data: String

        public init(binary: String?, data: String) {
            self.binary = binary
            self.data = data
        }
    }

    /// The roots' real paths, the one at `root` when given, else every root one
    /// after another; identical roots are listed once.
    public func headerPaths(root: String? = nil) -> [Paths] {
        let roots = root.map { path in self.roots.filter { $0.path == path } } ?? self.roots
        var seen: Set<String> = []
        var paths: [Paths] = []
        for root in roots {
            let key = (root.binary?.path ?? "") + "\u{0}" + root.path
            guard seen.insert(key).inserted else { continue }
            paths.append(Paths(binary: root.binary?.path, data: root.path))
        }
        return paths
    }
}
