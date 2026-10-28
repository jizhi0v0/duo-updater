import Foundation

/// The Pythons pyenv builds (`~/.pyenv/versions/<x.y.z>`) as managed rows,
/// one per minor (D1; free-threaded `t` builds apart), moved by `pyenv
/// install <x.y.z>` (design §4.7).
///
/// What was measured, with pyenv 2.8.14 cloned into an isolated
/// `PYENV_ROOT` (2026-10-27):
/// - **Newest, no network, no spawn**: the file names under
///   `plugins/python-build/share/python-build` (1,161) — pyenv-latest's own
///   rule kept: final releases only, `t` builds their own line (`pyenv latest
///   -k 3.12` → 3.12.16, `3.13t` → 3.13.18t, the same as here). Plugins add
///   theirs under `$PYENV_ROOT/plugins/*/share/python-build`. The answer moves
///   when pyenv itself is updated (`.asKnownBy`).
/// - **The command** (`env -i HOME PYENV_ROOT PATH=/opt/homebrew/bin:<system>
///   pyenv install 3.12.15`): built in 1:58 with Homebrew's openssl, readline
///   and ncurses; `ssl`, `sqlite3`, `lzma` import. A newer patch lands beside
///   the old one; nothing else is rewritten.
/// - **Interrupted** (§13.3, SIGINT/SIGTERM to the process group): while
///   downloading (exit 130) and while configuring (exit 1 / 143) python-build
///   removed `versions/3.12.16`; the old one runs; the next plain run builds
///   it whole. The compile and `make install` stages were not hit apart.
///
/// pyenv is bash. Homebrew's keg is run (D5.1); a git checkout (`~/.pyenv/bin/
/// pyenv`, or a python-build under the root's plugins, which even the keg
/// runs) has nothing to verify and its command is handed out to copy (D5.2).
/// A keg keeps python-build's definitions as the repository does,
/// `<keg>/plugins/python-build/share/python-build` (`brew install pyenv`
/// 2.8.14: `bin/pyenv -> ../libexec/pyenv`, 1,148 definitions).
public struct PyenvAdapter: ManagerAdapter {

    public static let id = ManagerID("pyenv")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "pyenv", signer: nil, logo: nil, tint: .label, lane: "pyenv",
        deadline: DefinitionLines.deadline, versionOrder: .generic)

    public var descriptor: ManagerDescriptor { Self.descriptor }

    /// Everything the adapter reads from the Mac, injected so tests never
    /// touch the host (`DefinitionLinesTests`). Disk only.
    public struct Host: Sendable {
        public var contents: @Sendable (String) -> Data?
        public var directories: @Sendable (String) -> [String]?
        public var exists: @Sendable (String) -> Bool
        /// The path with every link followed; nil when nothing is there.
        public var resolve: @Sendable (String) -> String?
        public var isQuarantined: @Sendable (String) -> Bool

        public init(
            contents: @escaping @Sendable (String) -> Data?,
            directories: @escaping @Sendable (String) -> [String]?,
            exists: @escaping @Sendable (String) -> Bool,
            resolve: @escaping @Sendable (String) -> String?,
            isQuarantined: @escaping @Sendable (String) -> Bool
        ) {
            self.contents = contents
            self.directories = directories
            self.exists = exists
            self.resolve = resolve
            self.isQuarantined = isQuarantined
        }

        public static let live = Host(
            contents: NvmNodeAdapter.Host.live.contents, directories: NvmNodeAdapter.Host.live.directories,
            exists: NvmNodeAdapter.Host.live.exists, resolve: NvmNodeAdapter.Host.live.resolve,
            isQuarantined: NvmNodeAdapter.Host.live.isQuarantined)
    }

    let home: URL
    let host: Host
    let homebrewRoots: [String]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, host: .live)
    }

    public init(home: URL, host: Host, homebrewRoots: [String] = ["/opt/homebrew", "/usr/local"]) {
        self.home = home
        self.host = host
        self.homebrewRoots = homebrewRoots
    }

    /// `PYENV_ROOT`'s default: what a GUI process sees.
    var root: String { home.path + "/.pyenv" }

    /// Homebrew's libraries on `PATH`, as python-build looks for them (PY-17).
    static let pathPrefix = "/opt/homebrew/bin:/usr/local/bin"

    // MARK: - ManagerAdapter

    public func scan() async -> ManagedScan {
        let host = self.host
        let root = self.root
        let descriptor = self.descriptor
        return await offCooperativePool {
            let binary = locate()
            guard let names = host.directories(root + "/versions") else { return .empty }
            let definitions = binary.map { Self.definitions(repository: $0.repository, root: root, host: host) } ?? nil
            // CPython 2.x installs `python` and `python2`, never `python3`.
            let items = DefinitionLines.items(
                names: names, root: root, title: "Python", interpreters: ["bin/python3", "bin/python"],
                definitions: definitions, knownBy: binary?.knownBy.map { "pyenv \($0)" },
                global: DefinitionLines.global(host.contents(root + "/version")), descriptor: descriptor,
                exists: host.exists)
            guard !items.isEmpty else { return .empty }
            var states: [String: String] = [:]
            for item in items {
                states[item.identity] = ([item.installed ?? "-", item.latestOverall ?? "-"] + item.alsoInstalled).joined(separator: ",")
            }
            return ManagedScan(
                roots: [ManagedRoot(manager: Self.id, path: root, binary: binary?.binary)], items: items, states: states)
        }
    }

    public func check(_ scan: ManagedScan) async -> [ManagedVerdict] {
        DefinitionLines.verdicts(
            scan.items, definitionsFound: scan.items.contains { $0.latestOverall != nil }, plugin: "python-build")
    }

    /// The new version's directory, the shims (with `.pyenv-shim`, the
    /// rehash lock, which pyenv clears after 2 min) and the global
    /// `version` file (§13.4). The build's own trap removes a half-built
    /// version on SIGINT; a stop during the closing rehash deletes even a
    /// finished one, which is still "not updated".
    public func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption? {
        ManagedInterruption(
            paths: [root.path + "/shims", root.path + "/version"],
            created: [ManagedSnapshot.NewEntries(directory: root.path + "/versions", any: true)])
    }

    /// `pyenv install <newest of the line>`, `PYENV_ROOT` the root.
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary, let latest = item.latestOverall else { return nil }
        return (CLIToolCommand(
            executable: binary.path, arguments: ["install", latest], pathPrefix: Self.pathPrefix,
            shellLine: "pyenv install \(latest)"), ["PYENV_ROOT": root.path])
    }

    public func reread(_ item: ManagedItem) async -> String? {
        await scan().items.first { $0.identity == item.identity }?.installed
    }

    // MARK: - The parts

    /// The pyenv that runs the root's commands, the repository it reads
    /// python-build from (nil: only the root's plugins), and the version that
    /// knows the definitions: Homebrew's keg first (it may run), then the
    /// root's own checkout. Blocking.
    ///
    /// A `pyenv-install` among the root's plugins (a git install kept as the
    /// root beside `brew install pyenv`) is what even the keg runs — pyenv
    /// puts `$PYENV_ROOT/plugins/*/bin` first on `PATH` — and it reads only
    /// its own definitions and the root's plugins'. The keg's are then not the
    /// ones that count, and the code that runs is a checkout: handed out (D5.2).
    func locate() -> (binary: ManagedRoot.Binary, repository: String?, knownBy: String?)? {
        let checkoutInstalls = (host.directories(root + "/plugins") ?? []).contains {
            host.exists(root + "/plugins/\($0)/bin/pyenv-install")
        }
        let checkoutVersion = DefinitionLines.scriptVersion(host.contents(root + "/libexec/pyenv---version"))
        for prefix in homebrewRoots {
            let link = prefix + "/bin/pyenv"
            guard let resolved = host.resolve(link),
                  let version = HomebrewKeg.version(
                    of: resolved, prefix: prefix, formula: "pyenv", paths: [["libexec", "pyenv"], ["bin", "pyenv"]],
                    contents: host.contents)
            else { continue }
            let trust: ManagedRoot.Trust
            if host.isQuarantined(resolved) {
                trust = .quarantined
            } else {
                trust = checkoutInstalls ? .untrusted(nil) : .homebrewKeg
            }
            let binary = ManagedRoot.Binary(path: link, version: version, trust: trust)
            return checkoutInstalls ? (binary, nil, checkoutVersion) : (binary, Self.repository(of: resolved), version)
        }
        let own = root + "/bin/pyenv"
        guard let resolved = host.resolve(own) else { return nil }
        let repository = Self.repository(of: resolved)
        let version = DefinitionLines.scriptVersion(host.contents(repository + "/libexec/pyenv---version"))
        return (ManagedRoot.Binary(path: own, version: version, trust: host.isQuarantined(resolved) ? .quarantined : .untrusted(nil)),
                repository, version)
    }

    /// `<repo>/libexec/pyenv` or `<repo>/bin/pyenv` → `<repo>`.
    static func repository(of resolved: String) -> String {
        ((resolved as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    }

    /// python-build's definitions in `repository` and every plugin's under
    /// the root; nil when there are none. Blocking.
    static func definitions(repository: String?, root: String, host: Host) -> [String]? {
        var names = repository.flatMap { host.directories($0 + "/plugins/python-build/share/python-build") } ?? []
        for plugin in host.directories(root + "/plugins") ?? [] {
            names += host.directories(root + "/plugins/\(plugin)/share/python-build") ?? []
        }
        return names.isEmpty ? nil : names
    }
}
