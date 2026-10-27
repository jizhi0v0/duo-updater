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
/// pyenv`) has nothing to verify and its command is handed out to copy (D5.2).
/// Where a keg keeps its python-build definitions is read from the keg itself
/// (`<keg>/plugins/python-build/share/python-build`, the repository's own
/// layout) — not yet seen on a `brew install pyenv` (§12 item 6).
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
            let items = DefinitionLines.items(
                names: names, root: root, title: "Python", interpreter: "bin/python3",
                definitions: definitions, knownBy: binary?.binary.version.map { "pyenv \($0)" },
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

    /// The pyenv that runs the root's commands, and the repository it reads
    /// python-build from: Homebrew's keg first (it may run), then the
    /// root's own checkout. Blocking.
    func locate() -> (binary: ManagedRoot.Binary, repository: String)? {
        for prefix in homebrewRoots {
            let link = prefix + "/bin/pyenv"
            guard let resolved = host.resolve(link),
                  let version = HomebrewKeg.version(
                    of: resolved, prefix: prefix, formula: "pyenv", paths: [["libexec", "pyenv"], ["bin", "pyenv"]],
                    contents: host.contents)
            else { continue }
            let keg = Self.repository(of: resolved)
            return (ManagedRoot.Binary(path: link, version: version, trust: host.isQuarantined(resolved) ? .quarantined : .homebrewKeg), keg)
        }
        let own = root + "/bin/pyenv"
        guard let resolved = host.resolve(own) else { return nil }
        let repository = Self.repository(of: resolved)
        let version = DefinitionLines.scriptVersion(host.contents(repository + "/libexec/pyenv---version"))
        return (ManagedRoot.Binary(path: own, version: version, trust: host.isQuarantined(resolved) ? .quarantined : .untrusted(nil)),
                repository)
    }

    /// `<repo>/libexec/pyenv` or `<repo>/bin/pyenv` → `<repo>`.
    static func repository(of resolved: String) -> String {
        ((resolved as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    }

    /// python-build's definitions and every plugin's under the root; nil when
    /// there are none. Blocking.
    static func definitions(repository: String, root: String, host: Host) -> [String]? {
        var names = host.directories(repository + "/plugins/python-build/share/python-build") ?? []
        for plugin in host.directories(root + "/plugins") ?? [] {
            names += host.directories(root + "/plugins/\(plugin)/share/python-build") ?? []
        }
        return names.isEmpty ? nil : names
    }
}
