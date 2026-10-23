import Foundation

/// One install of a manager the adapter found: its data root and the binary
/// that runs its commands.
public struct ManagedRoot: Sendable, Equatable {
    public let manager: ManagerID
    /// "~/.local/share/mise", "~/.nvm", "~/.cargo", "~/go/bin" — spelled whole.
    public let path: String
    /// Nil when the manager is not there (pyenv, rbenv and nvm are directories
    /// that work without their binary; fnm, go and pipx may not be found).
    public let binary: Binary?

    public struct Binary: Sendable, Equatable {
        public let path: String
        public let version: String?
        public let trust: Trust

        public init(path: String, version: String?, trust: Trust) {
            self.path = path
            self.version = version
            self.trust = trust
        }
    }

    /// Whether the binary may be run, by the rule the user agreed on 2026-10-01
    /// (`CLIToolWithheld.unverified`) and the owner's D5: the vendor's Team ID,
    /// a Homebrew keg, a published hash, or an exemption written down.
    public enum Trust: Sendable, Equatable {
        case vendorSigned(team: String)
        case homebrewKeg
        case verifiedHash
        /// Run though nothing verifies it, for a reason the kind's own code
        /// states (nvm's `nvm.sh`, `NvmCheck` rule 4).
        case exempt(reason: String)
        /// Not run. The signature it carries, when one was read.
        case untrusted(CLIToolTrust.Signature?)
        case quarantined

        /// Whether a command of this binary may run.
        public var runnable: Bool {
            switch self {
            case .vendorSigned, .homebrewKeg, .verifiedHash, .exempt: return true
            case .untrusted, .quarantined: return false
            }
        }

        /// What `ManagedCheck` withholds a one-click with when the binary may not
        /// run: another signer's build is `.wrongSigner`; an unsigned, ad hoc or
        /// quarantined one is `.unverified`, which still hands the command out to
        /// copy (`CLIToolStatus.commandToCopy`, D5.2).
        var withheld: CLIToolWithheld? {
            switch self {
            case .vendorSigned, .homebrewKeg, .verifiedHash, .exempt: return nil
            case .untrusted(.otherSigner?): return .wrongSigner
            case .untrusted, .quarantined: return .unverified
            }
        }

        var english: String {
            switch self {
            case .vendorSigned(let team): return "signed by Team \(team)"
            case .homebrewKeg: return "a Homebrew keg"
            case .verifiedHash: return "its published sha256"
            case .exempt(let reason): return "run without a signature: \(reason)"
            case .untrusted(let signature): return "not verified (\(signature?.rawValue ?? "unchecked"))"
            case .quarantined: return "quarantined"
            }
        }
    }

    public init(manager: ManagerID, path: String, binary: Binary?) {
        self.manager = manager
        self.path = path
        self.binary = binary
    }

    /// Whether the manager's commands may run from this root.
    public var runnable: Bool { binary?.trust.runnable ?? false }
}

/// One row's payload: everything the pane shows and the check decided on. The
/// shared fields of its `CLIToolStatus` (versions, state, one-click) are
/// `ManagedCheck`'s; this is what the adapter knew.
public struct ManagedItem: Sendable, Equatable {
    public let manager: ManagerID
    public let descriptor: ManagerDescriptor
    /// The root's path (`ManagedRoot.path`).
    public let root: String
    /// Stable inside the root: "node@20", "npm:prettier@2.0.0", "ruff", "3.12",
    /// "v22", "tokei", "mvdan.cc/gofumpt". Holds no `|`.
    public let key: String
    /// The row's title: "node", "ruff", "Python 3.12", "Node 22", "tokei".
    public let name: String
    /// The directory or file on disk now — moves when a new version lands
    /// beside the old one (a line's newest patch), which is why it is not the
    /// row's identity.
    public let installPath: String
    public let shape: Shape
    /// What the user asked the manager for, when it keeps one, and where.
    public let request: Request?
    public let installed: String?
    /// The newest the manager's own upgrade would move to, within the request.
    public let latestWithinRequest: String?
    /// The newest beyond the request, when known (mise `--bump`, uv
    /// `--outdated`, pipx outdated).
    public let latestOverall: String?
    /// Older patches of a line; mise's purgatory versions.
    public let alsoInstalled: [String]
    /// "aqua:jqlang/jq", "pip", "registry+crates.io", "git+…".
    public let backend: String?
    public let notes: NotesSource?
    /// What the vendor's upgrade does besides moving the version, said before
    /// the click (D6, D7, D8).
    public let effects: [Effect]
    /// What the detail pane lists, worded by the app.
    public let facts: [Fact]
    /// The trust of the root's binary when the row was made (`ManagedCheck`
    /// sets it from the root): what the wording reads to tell a quarantined
    /// binary from one another signer built. Nil before the check, and when
    /// the root has no binary.
    public let binaryTrust: ManagedRoot.Trust?

    public enum Shape: String, Sendable, Codable {
        /// One version at a time (uv tool, pipx, cargo, go).
        case package
        /// Patches side by side; one row per line (Node by major, Python and
        /// Ruby by minor), the newest installed on the row (D1).
        case line
        /// One row per request in the manager's config (mise).
        case request
    }

    public struct Request: Sendable, Equatable {
        public enum Kind: String, Sendable, Codable {
            /// "1.6", "==0.6.0": held where it is; `.pinned` when newer exists.
            case exact
            /// "20", ">=23,<24": follows releases inside the range.
            case range
            /// "lts/*", "latest": follows whatever the alias resolves to.
            case alias
        }
        public let kind: Kind
        /// As the user wrote it.
        public let spelled: String
        /// The config file it came from, when known.
        public let source: String?

        public init(kind: Kind, spelled: String, source: String? = nil) {
            self.kind = kind
            self.spelled = spelled
            self.source = source
        }
    }

    public enum NotesSource: Sendable, Equatable {
        case gitHubReleases(owner: String, repo: String)
        /// A raw Markdown document with one heading per version (Node's
        /// `CHANGELOG_V<major>.md`).
        case rawMarkdown(URL)
        case pypiProject(String)
        case crate(String)
    }

    public enum Effect: Sendable, Equatable {
        /// The old version stays beside the new one, for `for` when the
        /// manager removes it later ("24h", mise's purgatory).
        case oldKept(for: String?)
        case oldRemoved
        /// The manager rewrites the recorded specifier (pipx drops `==`).
        case dropsSpecifier(String)
        /// A `default` alias stays on this old version (nvm, fnm).
        case defaultStays(String)
        /// Global packages of the old version are not carried over (fnm).
        case packagesNotCarried
        case compilesFromSource
        /// The manager's config is rewritten (`mise upgrade --bump`).
        case configRewritten
        /// Once the vendor's command started it runs to the end (§13.1).
        case cannotBeCancelledOnceStarted

        /// `duo`'s line, and the key the app localizes by.
        public var english: String {
            switch self {
            case .oldKept(let period?): return "keeps the old version for \(period)"
            case .oldKept(nil): return "keeps the old version beside the new one"
            case .oldRemoved: return "removes the old version"
            case .dropsSpecifier(let specifier): return "drops the recorded specifier \(specifier)"
            case .defaultStays(let version): return "leaves `default` on \(version)"
            case .packagesNotCarried: return "does not carry global packages over"
            case .compilesFromSource: return "compiles from source"
            case .configRewritten: return "rewrites the manager's config"
            case .cannotBeCancelledOnceStarted: return "can't be cancelled once it has started"
            }
        }
    }

    public enum Fact: Sendable, Equatable {
        /// The config file the request came from.
        case source(String)
        case backend(String)
        case request(String)
        case alsoInstalled([String])
        /// A `default` alias and what it resolves to.
        case defaultAlias(String)
        case python(String)
        case target(String)
        /// Whose frozen list the latest comes from ("uv 0.13.4", "pyenv 2.8.13").
        case asKnownBy(String)
        /// Newer than the request allows, with the command that lifts it.
        case beyondRequest(latest: String, command: CLIToolCommand?)
        /// Anything else, already in English.
        case note(String)

        /// `duo`'s "label: value".
        public var english: (label: String, value: String) {
            switch self {
            case .source(let path): return ("source", path)
            case .backend(let backend): return ("backend", backend)
            case .request(let request): return ("request", request)
            case .alsoInstalled(let versions): return ("also installed", versions.joined(separator: ", "))
            case .defaultAlias(let value): return ("default", value)
            case .python(let version): return ("python", version)
            case .target(let target): return ("target", target)
            case .asKnownBy(let tool): return ("as known by", tool)
            case .beyondRequest(let latest, let command):
                return ("beyond the request", command.map { "\(latest) — \($0.display)" } ?? latest)
            case .note(let text): return ("note", text)
            }
        }
    }

    public init(
        descriptor: ManagerDescriptor, root: String, key: String, name: String, installPath: String,
        shape: Shape, request: Request? = nil, installed: String?, latestWithinRequest: String? = nil,
        latestOverall: String? = nil, alsoInstalled: [String] = [], backend: String? = nil,
        notes: NotesSource? = nil, effects: [Effect] = [], facts: [Fact] = [], binaryTrust: ManagedRoot.Trust? = nil
    ) {
        precondition(!key.contains(ManagerID.identitySeparator), "an item key is part of an identity split on |")
        self.manager = descriptor.id
        self.descriptor = descriptor
        self.root = root
        self.key = key
        self.name = name
        self.installPath = installPath
        self.shape = shape
        self.request = request
        self.installed = installed
        self.latestWithinRequest = latestWithinRequest
        self.latestOverall = latestOverall
        self.alsoInstalled = alsoInstalled
        self.backend = backend
        self.notes = notes
        self.effects = effects
        self.facts = facts
        self.binaryTrust = binaryTrust
    }

    /// This item with the root's binary trust recorded on it.
    func with(binaryTrust: ManagedRoot.Trust?) -> ManagedItem {
        ManagedItem(
            descriptor: descriptor, root: root, key: key, name: name, installPath: installPath, shape: shape,
            request: request, installed: installed, latestWithinRequest: latestWithinRequest,
            latestOverall: latestOverall, alsoInstalled: alsoInstalled, backend: backend, notes: notes,
            effects: effects, facts: facts, binaryTrust: binaryTrust)
    }

    /// What names this row across checks, whatever directory it sits in now:
    /// "<manager>|<root>|<key>" (`CLIToolStatus.identity`).
    public var identity: String { Self.identity(manager: manager, root: root, key: key) }

    public static func identity(manager: ManagerID, root: String, key: String) -> String {
        let separator = String(ManagerID.identitySeparator)
        return manager.rawValue + separator + root + separator + key
    }

    /// The parts of a managed identity, nil for a string that is not one.
    public static func parse(identity: String) -> (manager: ManagerID, root: String, key: String)? {
        let parts = identity.split(separator: ManagerID.identitySeparator, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty else { return nil }
        return (ManagerID(rawValue: String(parts[0])), String(parts[1]), String(parts[2]))
    }

    /// `path` with `home` written as `~` (`ClaudeCodePresentation.abbreviate`'s rule, here for Core).
    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

/// What an adapter's disk-only look found: every root, every item with its
/// installed version and request, and per item the rest of what its verdict
/// rests on (`CLIToolSighting.state`), keyed by identity.
public struct ManagedScan: Sendable, Equatable {
    public let roots: [ManagedRoot]
    public let items: [ManagedItem]
    public let states: [String: String]

    public init(roots: [ManagedRoot], items: [ManagedItem], states: [String: String] = [:]) {
        self.roots = roots
        self.items = items
        self.states = states
    }

    public static let empty = ManagedScan(roots: [], items: [])

    public func root(of item: ManagedItem) -> ManagedRoot? {
        roots.first { $0.manager == item.manager && $0.path == item.root }
    }

    /// The sightings the popover reserves rows from, one per item, by identity.
    public func sightings() -> [CLIToolSighting] {
        items.map { item in
            CLIToolSighting(
                kind: .managed, path: item.installPath, version: item.installed,
                state: states[item.identity] ?? "", identity: item.identity, name: item.name)
        }
    }
}
