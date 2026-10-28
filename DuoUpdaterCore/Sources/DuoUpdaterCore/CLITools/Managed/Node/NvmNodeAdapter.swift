import Foundation

/// The Node versions nvm keeps (`$NVM_DIR/versions/node/v<x.y.z>`) as managed
/// rows, one per major (D1), moved by `nvm install <major>
/// --reinstall-packages-from=<installed>` (D6; design §4.5). nvm itself keeps
/// its own row (`NvmProvider`); this is what it installs.
///
/// What was measured, with Homebrew's nvm 0.40.8 in an isolated `NVM_DIR`
/// (2026-10-27):
/// - **Scan, disk only**: `~/.nvm` and `~/.config/nvm` (the installer's two
///   defaults, `NvmScanner`), each `versions/node/v<x.y.z>` with its
///   `bin/node`; `alias/default` is a text file ("22.21.1", "lts/*").
/// - **Check**: nodejs.org's `index.json` (`NodeDistIndex`) — no nvm run, so
///   no `alias/lts` rewrite (NVM-23) and no `N/A` that means both "none" and
///   "offline" (NVM-24).
/// - **The command** (`env -i HOME NVM_DIR PATH=/usr/bin:/bin /bin/bash -c
///   '. nvm.sh --no-use; nvm install 22 --reinstall-packages-from=22.21.1'`):
///   v22.23.4 lands beside v22.21.1 in 29 s, the old one's global packages
///   (cowsay) reinstalled into it; a literal `default` stays on 22.21.1.
/// - **Interrupted** (§13.3, SIGINT/SIGTERM to the process group): 4 s in,
///   exit 130/143 and nothing new on disk; once the version directory exists
///   (extract, or the packages' reinstall), exit 130/143 with v22.23.4 in
///   place and runnable but without the old globals, and `nvm ls` lists it.
///   The next plain run of the same command reinstalls the packages and
///   completes.
///
/// nvm is shell scripts. Its `nvm.sh` is run when it is the directory's own
/// (the user's exemption, `NvmCheck` rule 4) or a Homebrew keg's (D5.1) —
/// Homebrew's nvm is a link `~/.nvm/nvm.sh -> /opt/homebrew/opt/nvm/libexec/nvm.sh`
/// on this Mac, or no file at all with `NVM_DIR=~/.nvm` in the profile.
public struct NvmNodeAdapter: ManagerAdapter {

    public static let id = ManagerID("nvm-node")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "nvm Node", signer: nil, logo: "cli-nvm", tint: .label,
        // nvm's own update rewrites the `nvm.sh` these rows' commands source.
        lane: "nvm")

    public var descriptor: ManagerDescriptor { Self.descriptor }

    /// Everything the adapter reads from the Mac, injected so tests never
    /// touch the host (`NodeAdapterTests`).
    public struct Host: Sendable {
        /// A file's bytes, nil when there is none. Blocking.
        public var contents: @Sendable (String) -> Data?
        /// The names in a directory, nil when it cannot be listed. Blocking.
        public var directories: @Sendable (String) -> [String]?
        public var exists: @Sendable (String) -> Bool
        /// The path with every link followed; nil when nothing is there. Blocking.
        public var resolve: @Sendable (String) -> String?
        public var isQuarantined: @Sendable (String) -> Bool
        /// nodejs.org's `index.json`; throws when it did not answer.
        public var index: @Sendable () async throws -> Data

        public init(
            contents: @escaping @Sendable (String) -> Data?,
            directories: @escaping @Sendable (String) -> [String]?,
            exists: @escaping @Sendable (String) -> Bool,
            resolve: @escaping @Sendable (String) -> String?,
            isQuarantined: @escaping @Sendable (String) -> Bool,
            index: @escaping @Sendable () async throws -> Data
        ) {
            self.contents = contents
            self.directories = directories
            self.exists = exists
            self.resolve = resolve
            self.isQuarantined = isQuarantined
            self.index = index
        }

        public static let live = Host(
            contents: { FileManager.default.contents(atPath: $0) },
            directories: { try? FileManager.default.contentsOfDirectory(atPath: $0) },
            exists: { FileManager.default.fileExists(atPath: $0) },
            resolve: { path in
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            },
            isQuarantined: { CLIToolTrust.hasQuarantine(URL(fileURLWithPath: $0)) },
            index: { try await NodeDistIndex.fetch() })
    }

    let home: URL
    let host: Host
    let homebrewRoots: [String]
    let platform: String

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, host: .live)
    }

    public init(
        home: URL, host: Host, homebrewRoots: [String] = ["/opt/homebrew", "/usr/local"],
        platform: String = NodeDistIndex.platformFile
    ) {
        self.home = home
        self.host = host
        self.homebrewRoots = homebrewRoots
        self.platform = platform
    }

    /// The reason `nvm.sh` of the directory's own runs unverified.
    static let exemption = "nvm is shell scripts with nothing to verify, run by the user's decision of 2026-10-09"

    /// The command, given its arguments: `nvm.sh`, the major, the version
    /// whose global packages are carried over. `;`, as measured: what sourcing
    /// `nvm.sh` returns is not the command's to judge (NVM-05).
    static let script = #". "$1" --no-use; nvm install "$2" --reinstall-packages-from="$3""#

    // MARK: - ManagerAdapter

    /// Disk only: each `NVM_DIR` holding versions, once (a link to the other
    /// is the same one).
    public func scan() async -> ManagedScan {
        let host = self.host
        let directories = [home.path + "/.nvm", home.path + "/.config/nvm"]
        let descriptor = self.descriptor
        return await offCooperativePool {
            var roots: [ManagedRoot] = []
            var items: [ManagedItem] = []
            var states: [String: String] = [:]
            var seen: Set<String> = []
            for directory in directories {
                guard let canonical = host.resolve(directory), seen.insert(canonical).inserted else { continue }
                let versions = directory + "/versions/node"
                guard let names = host.directories(versions) else { continue }
                let defaultPatch = Self.literalDefault(host.contents(directory + "/alias/default"))
                let found = NodeLines.items(
                    names: names, versions: versions, root: directory, node: "bin/node", default: defaultPatch,
                    descriptor: descriptor, extraEffects: [], exists: host.exists)
                guard !found.isEmpty else { continue }
                roots.append(ManagedRoot(manager: Self.id, path: directory, binary: script(directory, canonical: canonical)))
                for item in found {
                    states[item.identity] = ([item.installed ?? "-"] + item.alsoInstalled + [defaultPatch ?? "-"])
                        .joined(separator: ",")
                }
                items += found
            }
            return ManagedScan(roots: roots, items: items, states: states)
        }
    }

    public func check(_ scan: ManagedScan) async -> [ManagedVerdict] {
        var releases: [NodeDistIndex.Release]?
        var failure: String?
        do {
            releases = NodeDistIndex.parse(try await host.index())
            if releases == nil { failure = "its list could not be read" }
        } catch {
            failure = "\(error)"
        }
        return NodeLines.verdicts(
            scan.items, releases: releases, failure: failure, platform: platform,
            moveDefault: { "nvm alias default \($0)" })
    }

    /// `/bin/bash -c '. nvm.sh --no-use; nvm install <major>
    /// --reinstall-packages-from=<installed>'`, `NVM_DIR` the root: no `--save`
    /// (it writes `.nvmrc`), no mirror variable (D6, NVM-70). The words a user
    /// pastes into their own shell are the `nvm` line.
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary, let installed = item.installed else { return nil }
        let major = String(item.key.dropFirst())
        return (CLIToolCommand(
            executable: "/bin/bash", arguments: ["-c", Self.script, "nvm", binary.path, major, installed],
            pathPrefix: nil, shellLine: "nvm install \(major) --reinstall-packages-from=\(installed)"),
            ["NVM_DIR": root.path])
    }

    /// The new version's directory (nvm names it), the aliases (`lts/*`
    /// rewritten), and nvm's install locks — §13.4: a lock left by a stop
    /// makes the next `nvm install` wait 600 s ("Waiting for another install
    /// of v22.23.4 to finish…"); nvm never takes a stale one. A stop while
    /// npm reinstalls the globals exits 0 with them missing.
    public func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption? {
        ManagedInterruption(
            paths: [root.path + "/alias", root.path + "/.cache/locks"],
            created: [ManagedSnapshot.NewEntries(directory: root.path + "/versions/node", any: true)])
    }

    /// The major's newest patch after the command.
    public func reread(_ item: ManagedItem) async -> String? {
        await scan().items.first { $0.identity == item.identity }?.installed
    }

    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog {
        try await ManagedNotes.fetch(item.notes, force: force)
    }

    // MARK: - The parts

    /// The `nvm.sh` the root's commands source, and whether it may run: the
    /// directory's own file (exempt), a link into Homebrew's nvm keg, or —
    /// with none in the directory — Homebrew's `opt/nvm/nvm.sh`. Blocking.
    func script(_ directory: String, canonical: String) -> ManagedRoot.Binary? {
        let own = directory + "/nvm.sh"
        if let resolved = host.resolve(own) {
            if resolved == canonical + "/nvm.sh" {
                let version = host.contents(resolved).flatMap { NvmScanner.version(in: String(decoding: $0, as: UTF8.self)) }
                let trust: ManagedRoot.Trust = host.isQuarantined(resolved) ? .quarantined : .exempt(reason: Self.exemption)
                return ManagedRoot.Binary(path: own, version: version, trust: trust)
            }
            if let binary = keg(own, resolved: resolved) { return binary }
            return ManagedRoot.Binary(path: own, version: nil, trust: host.isQuarantined(resolved) ? .quarantined : .untrusted(nil))
        }
        for prefix in homebrewRoots {
            let link = prefix + "/opt/nvm/nvm.sh"
            if let resolved = host.resolve(link), let binary = keg(link, resolved: resolved) { return binary }
        }
        return nil
    }

    /// Homebrew's nvm: `Cellar/nvm/<v>/nvm.sh` or `libexec/nvm.sh`, measured
    /// in 0.40.8.
    func keg(_ path: String, resolved: String) -> ManagedRoot.Binary? {
        for prefix in homebrewRoots {
            guard let version = HomebrewKeg.version(
                of: resolved, prefix: prefix, formula: "nvm", paths: [["nvm.sh"], ["libexec", "nvm.sh"]],
                contents: host.contents)
            else { continue }
            return ManagedRoot.Binary(path: path, version: version, trust: host.isQuarantined(resolved) ? .quarantined : .homebrewKeg)
        }
        return nil
    }

    /// `alias/default` when it names one version exactly ("22.21.1",
    /// "v22.21.1"): the one the update leaves it on. An alias ("lts/*",
    /// "22", "node") follows by nvm's own rules.
    static func literalDefault(_ data: Data?) -> String? {
        guard let data else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else { return nil }
        return bare
    }
}
