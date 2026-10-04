import Foundation

/// Bun — the JavaScript runtime and package manager — as its installer leaves
/// it, identified by **its path**, `~/.bun/bin/bun`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://bun.sh/install |
/// bash`, read 2026-10-04) and the install on the development Mac (1.3.10, laid
/// down 2026-02-08):
/// - `$BUN_INSTALL/bin/bun` (default `~/.bun`) is one Mach-O executable, ~61 MB,
///   with `bunx` a link to it. The installer unzips
///   `github.com/oven-sh/bun/releases/latest/download/bun-darwin-<aarch64|x64>.zip`
///   there, and appends `$BUN_INSTALL/bin` to the shell's rc file.
/// - It is Developer ID signed by Oven, Team `7FRXF46ZSN` (`codesign -dv` on
///   1.3.10). `bun upgrade` replaces the file with the release's, after only
///   running the new binary's `--version` (no hash), so the Team ID is what the
///   trust rule rests on, before an update and after it.
/// - The version is compiled in: the npm user agent bun sends is the literal
///   `bun/<version>+<revision> npm/? node/v<node>`, once in the file
///   (`bun/1.3.10+30e609e08 npm/? node/v24.3.0`). It is read from the bytes, so
///   nothing is run.
/// - `bun add -g` installs into `$BUN_INSTALL/install/global` — a `package.json`
///   whose `dependencies` are what the user added, a `bun.lock`, and
///   `node_modules` with every dependency flattened in (315 entries for one
///   openclaw) — and links each package's commands into `$BUN_INSTALL/bin`
///   (`BunPackages`).
///
/// A bun from Homebrew (`/opt/homebrew/bin/bun`) is brew's, and the copy npm
/// installs (`npm i -g bun`) the npm group's; neither is looked at here.
public struct BunInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or an empty file.
        case executableMissing
        /// No single `bun/<version> npm/?` literal in the file.
        case versionUnreadable
    }

    /// `~/.bun/bin/bun`: the row's identity.
    public let path: String
    /// The version compiled into the file, without its `+<revision>`.
    public let version: String?
    /// The build's git revision (`30e609e08`), when the literal carries one.
    public let revision: String?
    /// Oven's Team ID on the file, measured by the check (`BunScanner.withSignature`),
    /// nil until then: bun is run at every package update, so its trust decides
    /// the packages' rows too.
    public let signature: CLIToolTrust.Signature?
    public let quarantined: Bool
    public let problem: Problem?

    public init(
        path: String, version: String?, revision: String? = nil, signature: CLIToolTrust.Signature? = .vendor,
        quarantined: Bool = false, problem: Problem? = nil
    ) {
        self.path = path
        self.version = version
        self.revision = revision
        self.signature = signature
        self.quarantined = quarantined
        self.problem = problem
    }

    /// A canary build: `bun upgrade` on one installs the newest canary, which has
    /// no version to compare with.
    public var isCanary: Bool { version?.contains("-canary") == true }

    /// What its packages' rows are installed by.
    public var manager: BunManager { BunManager(path: path, signature: signature, quarantined: quarantined) }

    func with(signature: CLIToolTrust.Signature?) -> BunInstall {
        BunInstall(path: path, version: version, revision: revision, signature: signature, quarantined: quarantined,
                   problem: problem)
    }
}

/// Finds bun at `~/.bun/bin/bun`, and the packages its global install holds.
///
/// Network-free, and nothing is run: the version is read out of the file, the
/// packages out of their `package.json`.
public struct BunScanner: Sendable {

    /// Oven.
    public static let teamIdentifier = "7FRXF46ZSN"

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature
    public typealias QuarantineCheck = @Sendable (URL) -> Bool

    let home: URL
    let checkSignature: SignatureCheck
    let isQuarantined: QuarantineCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = {
            CLIToolTrust.signature(of: $0, teamIdentifier: BunScanner.teamIdentifier)
        },
        isQuarantined: @escaping QuarantineCheck = CLIToolTrust.hasQuarantine
    ) {
        self.home = home
        self.checkSignature = checkSignature
        self.isQuarantined = isQuarantined
    }

    /// `$BUN_INSTALL`'s default. A `BUN_INSTALL` set in the user's shell is not in
    /// a GUI app's environment, so only this one is read.
    var root: URL { home.appendingPathComponent(".bun") }
    var location: URL { root.appendingPathComponent("bin/bun") }

    /// bun, or nothing. Blocking: the file is read (~61 MB searched).
    public func scan() -> BunInstall? {
        let url = location
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return nil }
        let resolved = url.resolvingSymlinksInPath()
        // Read, never mapped (`ExecutableBytes`).
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0,
              let literals = ExecutableBytes.joinedWindows(in: resolved, marker: Self.marker, before: 80, after: 0)
        else {
            return BunInstall(path: url.path, version: nil, signature: nil, problem: .executableMissing)
        }
        let compiled = Self.compiledVersion(in: literals)
        return BunInstall(
            path: url.path, version: compiled?.version, revision: compiled?.revision,
            signature: nil, quarantined: isQuarantined(resolved),
            problem: compiled == nil ? .versionUnreadable : nil)
    }

    /// The install with its signature read: blocking, ~0.4 s for the whole file.
    public func withSignature(_ install: BunInstall) -> BunInstall {
        guard install.problem != .executableMissing else { return install }
        return install.with(signature: checkSignature(URL(fileURLWithPath: install.path).resolvingSymlinksInPath()))
    }

    static let marker = Data(" npm/? node/".utf8)

    /// The version in the file's one `bun/<version>[+<revision>] npm/? node/`
    /// literal; nil when there is none, or several that disagree.
    static func compiledVersion(in data: Data) -> (version: String, revision: String?)? {
        var found: Set<String> = []
        var start = data.startIndex
        while let range = data.range(of: marker, in: start..<data.endIndex) {
            // Back from the marker to `bun/`, at most 80 bytes.
            let floor = max(data.startIndex, range.lowerBound - 80)
            if let slash = data.range(of: Data("bun/".utf8), options: .backwards, in: floor..<range.lowerBound) {
                found.insert(String(decoding: data[slash.upperBound..<range.lowerBound], as: UTF8.self))
            } else {
                found.insert("")
            }
            start = range.upperBound
        }
        guard found.count == 1, let literal = found.first else { return nil }
        let parts = literal.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard BunRelease.isVersion(parts[0]) else { return nil }
        let revision = parts.count == 2 && !parts[1].isEmpty && parts[1].allSatisfy(\.isHexDigit) ? parts[1] : nil
        guard parts.count == 1 || revision != nil else { return nil }
        return (parts[0], revision)
    }
}

/// The packages `bun add -g` installed, read into the npm group's shape
/// (`NpmInstall`) so the same check holds them — see `NpmCheck` for what differs.
///
/// - **Which packages**: the `dependencies` of `~/.bun/install/global/package.json`
///   — what the user added, not the hundreds of dependencies flattened beside them
///   in `node_modules` — each read from `node_modules/<name>` as npm's are, so a
///   library without a `bin` is skipped and Claude Code is left to its own group.
/// - **The node**: a package's commands are `#!/usr/bin/env node` scripts bun
///   links into `~/.bun/bin`, so they run on the user's `PATH` node, which a GUI
///   app cannot see. The node held against `engines` is the one found on disk,
///   Homebrew's first — `/opt/homebrew/bin/node`, then `/usr/local/bin/node` —
///   agreed 2026-10-04 as the closest stand-in; with none, the packages are
///   reported only (`NpmCheck.bunGate`).
/// - **The registry**: bun reads `install.registry` and `install.scopes` from the
///   global `bunfig.toml` (`~/.bunfig.toml`, `~/.config/.bunfig.toml`) and the
///   user's `~/.npmrc`; a registry other than npm's makes a package report-only,
///   as for npm.
public struct BunPackages: Sendable {

    let home: URL
    let systemPrefixes: [URL]
    let checkNodeSignature: NpmScanner.SignatureCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemPrefixes: [URL] = [URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local")],
        checkNodeSignature: @escaping NpmScanner.SignatureCheck = {
            CLIToolTrust.signature(of: $0, teamIdentifier: NpmScanner.nodeTeamIdentifier)
        }
    ) {
        self.home = home
        self.systemPrefixes = systemPrefixes
        self.checkNodeSignature = checkNodeSignature
    }

    var global: URL { home.appendingPathComponent(".bun/install/global") }

    /// The packages of the global install, each managed by `bun`. Blocking.
    public func scan(bun: BunInstall) -> [NpmInstall] {
        let names = Self.dependencies(in: global.appendingPathComponent("package.json"))
        guard !names.isEmpty else { return [] }
        let node = knownNode()
        let prefix = NodePrefix(path: global.path, source: .bun, layoutNodeVersion: node?.version)
        let runtime = node?.runtime ?? NpmRuntime(
            node: nil, npm: nil, npmVersion: nil, nodeSignature: nil, nodeQuarantined: false, nodeVersion: nil)
        let scanner = NpmScanner(home: home, prefixes: [], checkSignature: checkNodeSignature)
        let modules = global.appendingPathComponent("node_modules")
        let registries = Self.registryConfig(home: home)
        return names.compactMap {
            scanner.package($0, in: modules, prefix: prefix, runtime: runtime, registries: registries,
                            npmrcPrefixElsewhere: nil, bun: bun.manager)
        }
    }

    /// The names under `dependencies`, sorted; an unreadable file has none.
    static func dependencies(in manifest: URL) -> [String] {
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = json["dependencies"] as? [String: Any]
        else { return [] }
        return dependencies.keys.filter { !$0.isEmpty && !$0.contains("..") }.sorted()
    }

    /// The first system prefix with an executable `bin/node`: its runtime, without
    /// npm (bun installs these), and its version from the Homebrew keg it links
    /// into. nil when there is none.
    func knownNode() -> (runtime: NpmRuntime, version: String?)? {
        let scanner = NpmScanner(home: home, prefixes: [], checkSignature: checkNodeSignature)
        for root in systemPrefixes {
            guard FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/node").path) else {
                continue
            }
            let version = NodePrefixes.kegVersion(ofNodeIn: root)
            let full = scanner.runtime(of: NodePrefix(path: root.path, source: .system, layoutNodeVersion: version))
            // The roots searched are Homebrew's, so a keg is asked of them.
            let keg = NodePrefixes.homebrewKeg(
                ofNode: root.appendingPathComponent("bin/node").resolvingSymlinksInPath(), prefix: root,
                homebrewRoots: systemPrefixes.map(\.path))
            let runtime = NpmRuntime(
                node: full.node, npm: nil, npmVersion: nil, nodeSignature: full.nodeSignature,
                nodeQuarantined: full.nodeQuarantined, nodeVersion: version, homebrewKeg: keg)
            return (runtime, version)
        }
        return nil
    }

    // MARK: - Registry configuration

    /// The registry keys bun reads for a global install, in its precedence: the
    /// global `bunfig.toml` files, then `~/.npmrc` — shaped as `NpmScanner`'s
    /// (`registry`, `@scope:registry`) so `NpmScanner.customRegistry` decides.
    static func registryConfig(home: URL) -> [(key: String, value: String, file: String)] {
        let bunfigs = [home.appendingPathComponent(".bunfig.toml"), home.appendingPathComponent(".config/.bunfig.toml")]
        let npmrc = home.appendingPathComponent(".npmrc")
        return bunfigs.flatMap(bunfigRegistries)
            + NodePrefixes.npmrcEntries(in: npmrc)
                .filter { $0.key == "registry" || ($0.key.hasPrefix("@") && $0.key.hasSuffix(":registry")) }
                .reversed()
                .map { ($0.key, $0.value, npmrc.path) }
    }

    /// `[install] registry = "<url>"` and each `[install.scopes] "<scope>" =
    /// "<url>"` of a bunfig. A registry written as a table (`{ url = …, token =
    /// … }`) is read for its `url` only — never a token; one whose url cannot be
    /// read stands as `(a table)`, so it still counts as another registry.
    static func bunfigRegistries(_ file: URL) -> [(key: String, value: String, file: String)] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var table = ""
        var found: [(key: String, value: String, file: String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if line.hasPrefix("[") {
                table = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = registryURL(String(line[line.index(after: equals)...]))
            switch table {
            case "install" where key == "registry":
                found.append(("registry", value, file.path))
            case "install.scopes":
                let scope = key.hasPrefix("@") ? key : "@" + key
                found.append(("\(scope):registry", value, file.path))
            default:
                break
            }
        }
        return found.reversed()  // the last one in a file wins
    }

    static func registryURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
        if value.hasPrefix("{") {
            guard let url = value.range(of: #"url\s*=\s*["']([^"']+)["']"#, options: .regularExpression) else {
                return "(a table)"
            }
            value = String(value[url]).split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
            value = value.trimmingCharacters(in: .whitespaces)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
