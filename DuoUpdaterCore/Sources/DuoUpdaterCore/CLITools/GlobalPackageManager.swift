import Foundation

/// A pnpm or Yarn on disk that can change a global install of packages, how
/// DuoUpdater would run it, and whether it may.
///
/// The rule, as the user agreed it (2026-10-13): the JavaScript ones run on a
/// trusted node (`NpmRuntime.nodeIsTrusted`) — npm's own install of the package
/// in a node prefix, or the copy corepack cached behind a prefix's shim, which
/// corepack checked against its sha512 when it downloaded it — and Homebrew's
/// formula, trusted as the node Homebrew installs is. pnpm's standalone binary
/// (`~/Library/pnpm`) is ad hoc signed with no Team ID, so nothing says it is
/// pnpm's own build: its packages are reported, with the command to run.
public struct GlobalPackageManager: Sendable, Equatable, Codable {

    public enum Tool: String, Sendable, Codable {
        case pnpm
        case yarn
    }

    public enum Source: String, Sendable, Codable {
        /// `<prefix>/lib/node_modules/<tool>`, from `npm install -g`.
        case npm
        /// corepack's shim in a node prefix (`<prefix>/bin/pnpm` →
        /// `corepack/dist/pnpm.js`), run as the copy corepack cached for the
        /// version it uses outside a project: its "Last Known Good"
        /// (`lastKnownGood.json`).
        case corepack
        /// Homebrew's formula: pnpm's a binary Homebrew built, Yarn's its
        /// `yarn.js` with `PREFIX` set to Homebrew's root (the formula's own env
        /// script).
        case homebrew
        /// pnpm's standalone install in its home: ad hoc signed, never run.
        case standalone
    }

    public let tool: Tool
    /// nil only for pnpm's standalone binary, which is never run to ask.
    public let version: String?
    public let source: Source
    /// What the user's command resolves to: the shim, the link or the binary.
    public let path: String
    /// What is run: a node, with `script`, for the JavaScript ones; the binary
    /// itself for Homebrew's pnpm.
    public let executable: String
    public let script: String?
    /// The node `executable` is, for the JavaScript ones: whether it may run
    /// decides, and its `engines` are held against it.
    public let runtime: NpmRuntime?
    /// `/opt/homebrew/Cellar/pnpm/12.11.2`, for Homebrew's.
    public let homebrewKeg: String?
    /// Homebrew's root, which Yarn's formula passes as `PREFIX`.
    public let homebrewRoot: String?

    public init(
        tool: Tool, version: String?, source: Source, path: String, executable: String, script: String?,
        runtime: NpmRuntime?, homebrewKeg: String? = nil, homebrewRoot: String? = nil
    ) {
        self.tool = tool
        self.version = version
        self.source = source
        self.path = path
        self.executable = executable
        self.script = script
        self.runtime = runtime
        self.homebrewKeg = homebrewKeg
        self.homebrewRoot = homebrewRoot
    }

    public var isTrusted: Bool {
        switch source {
        case .standalone: return false
        case .npm, .corepack: return runtime?.nodeIsTrusted == true
        case .homebrew: return homebrewKeg != nil && (script == nil || runtime?.nodeIsTrusted == true)
        }
    }

    var major: Int? { version.flatMap(NpmVersion.init)?.major }

    /// `<executable> [<script>] <arguments…>`, with the node's `bin` first on
    /// `PATH` for the JavaScript ones.
    public func command(_ arguments: [String]) -> CLIToolCommand {
        CLIToolCommand(
            executable: executable, arguments: (script.map { [$0] } ?? []) + arguments,
            pathPrefix: script == nil ? nil : URL(fileURLWithPath: executable).deletingLastPathComponent().path)
    }

    /// What a user would type, for a command to copy: the manager's own name.
    func typed(_ arguments: [String]) -> CLIToolCommand {
        CLIToolCommand(executable: path, arguments: arguments, pathPrefix: nil)
    }
}

/// Finds the pnpm and Yarn copies on disk, from the layout alone — never from
/// `PATH`, which a GUI app does not have, and never by running them.
public struct GlobalPackageManagers: Sendable {

    let home: URL
    let prefixes: [NodePrefix]
    let homebrewRoots: [URL]
    let checkSignature: NpmScanner.SignatureCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        prefixes: [NodePrefix]? = nil,
        homebrewRoots: [URL] = [URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local")],
        checkSignature: @escaping NpmScanner.SignatureCheck = {
            CLIToolTrust.signature(of: $0, teamIdentifier: NpmScanner.nodeTeamIdentifier)
        }
    ) {
        self.home = home
        self.prefixes = prefixes ?? NodePrefixes(home: home, systemPrefixes: homebrewRoots).discover()
        self.homebrewRoots = homebrewRoots
        self.checkSignature = checkSignature
    }

    /// corepack's home by its own default, `~/.cache/node/corepack`
    /// (`COREPACK_HOME`, which a GUI app does not have).
    var corepackHome: URL { home.appendingPathComponent(".cache/node/corepack") }

    /// Every copy of `tool` found, each prefix once: npm's and corepack's in the
    /// node prefixes, then Homebrew's, then pnpm's standalone one.
    public func discover(_ tool: GlobalPackageManager.Tool) -> [GlobalPackageManager] {
        let scanner = NpmScanner(home: home, prefixes: [], checkSignature: checkSignature)
        var seen = Set<String>()
        var found: [GlobalPackageManager] = []
        for prefix in prefixes {
            guard seen.insert(prefix.url.resolvingSymlinksInPath().path).inserted else { continue }
            let link = prefix.url.appendingPathComponent("bin/\(tool.rawValue)")
            guard FileManager.default.fileExists(atPath: link.path) else { continue }
            let target = link.resolvingSymlinksInPath()
            if let manager = corepack(tool, link: link, target: target, prefix: prefix, scanner: scanner)
                ?? npm(tool, link: link, prefix: prefix, scanner: scanner) {
                found.append(manager)
            }
        }
        found += homebrewRoots.compactMap { homebrew(tool, root: $0, scanner: scanner) }
        if tool == .pnpm, let standalone = standalonePnpm() { found.append(standalone) }
        return found
    }

    /// The shim corepack links into a prefix, run as corepack's cached copy of
    /// its Last Known Good version. nil when the link is not corepack's, or that
    /// version is not in the cache (the shim would download it).
    func corepack(
        _ tool: GlobalPackageManager.Tool, link: URL, target: URL, prefix: NodePrefix, scanner: NpmScanner
    ) -> GlobalPackageManager? {
        let components = target.pathComponents
        guard components.suffix(3) == ["corepack", "dist", "\(tool.rawValue).js"],
              let version = Self.lastKnownGood(tool, in: corepackHome.appendingPathComponent("lastKnownGood.json"))
        else { return nil }
        let bin = corepackHome.appendingPathComponent("v1/\(tool.rawValue)/\(version)/bin")
        let names = tool == .pnpm ? ["pnpm.cjs", "pnpm.mjs"] : ["yarn.js"]
        guard let script = names.map({ bin.appendingPathComponent($0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else { return nil }
        let runtime = scanner.runtime(of: prefix)
        guard let node = runtime.node else { return nil }
        return GlobalPackageManager(
            tool: tool, version: version, source: .corepack, path: link.path, executable: node, script: script.path,
            runtime: runtime)
    }

    /// `"pnpm": "10.33.2+sha512.…"` → `10.33.2`.
    static func lastKnownGood(_ tool: GlobalPackageManager.Tool, in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reference = json[tool.rawValue] as? String
        else { return nil }
        let version = String(reference.split(separator: "+", maxSplits: 1).first ?? "")
        return NpmVersion(version) == nil ? nil : version
    }

    /// npm's install of the package in the prefix, run by the prefix's node.
    func npm(
        _ tool: GlobalPackageManager.Tool, link: URL, prefix: NodePrefix, scanner: NpmScanner
    ) -> GlobalPackageManager? {
        let package = prefix.url.appendingPathComponent("lib/node_modules/\(tool.rawValue)")
        guard let data = try? Data(contentsOf: package.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let bin = Self.bin(json, named: tool.rawValue)
        else { return nil }
        let runtime = scanner.runtime(of: prefix)
        guard let node = runtime.node else { return nil }
        return GlobalPackageManager(
            tool: tool, version: version, source: .npm, path: link.path, executable: node,
            script: package.appendingPathComponent(bin).standardizedFileURL.path, runtime: runtime)
    }

    /// `bin` as a map naming `name`, or a single path.
    static func bin(_ json: [String: Any], named name: String) -> String? {
        if let map = json["bin"] as? [String: Any] { return map[name] as? String }
        return json["bin"] as? String
    }

    /// Homebrew's formula: `<root>/opt/<tool>` links into its keg, which holds an
    /// `INSTALL_RECEIPT.json`. pnpm's is a binary; Yarn's is `libexec/bin/yarn.js`,
    /// run by Homebrew's own node.
    func homebrew(_ tool: GlobalPackageManager.Tool, root: URL, scanner: NpmScanner) -> GlobalPackageManager? {
        let keg = root.appendingPathComponent("opt/\(tool.rawValue)").resolvingSymlinksInPath()
        let components = keg.pathComponents
        let rootComponents = root.resolvingSymlinksInPath().pathComponents
        guard components.count == rootComponents.count + 3, Array(components.prefix(rootComponents.count)) == rootComponents,
              components[rootComponents.count] == "Cellar", components[rootComponents.count + 1] == tool.rawValue,
              FileManager.default.fileExists(atPath: keg.appendingPathComponent("INSTALL_RECEIPT.json").path)
        else { return nil }
        let version = Self.kegVersion(components[rootComponents.count + 2])
        let link = root.appendingPathComponent("bin/\(tool.rawValue)").path
        switch tool {
        case .pnpm:
            let binary = keg.appendingPathComponent("bin/pnpm")
            guard FileManager.default.isExecutableFile(atPath: binary.path) else { return nil }
            return GlobalPackageManager(
                tool: .pnpm, version: version, source: .homebrew, path: link,
                executable: binary.resolvingSymlinksInPath().path, script: nil, runtime: nil, homebrewKeg: keg.path,
                homebrewRoot: root.path)
        case .yarn:
            let script = keg.appendingPathComponent("libexec/bin/yarn.js")
            let nodePrefix = NodePrefix(path: root.path, source: .system, layoutNodeVersion: NodePrefixes.kegVersion(ofNodeIn: root))
            let full = scanner.runtime(of: nodePrefix)
            guard FileManager.default.fileExists(atPath: script.path), let node = full.node else { return nil }
            let runtime = NpmRuntime(
                node: node, npm: nil, npmVersion: nil, nodeSignature: full.nodeSignature,
                nodeQuarantined: full.nodeQuarantined, nodeVersion: full.nodeVersion,
                homebrewKeg: NodePrefixes.homebrewKeg(
                    ofNode: URL(fileURLWithPath: node).resolvingSymlinksInPath(), prefix: root,
                    homebrewRoots: homebrewRoots.map(\.path)))
            return GlobalPackageManager(
                tool: .yarn, version: version, source: .homebrew, path: link, executable: node, script: script.path,
                runtime: runtime, homebrewKeg: keg.path, homebrewRoot: root.path)
        }
    }

    /// `12.11.2_1` → `12.11.2`: the `_1` is Homebrew's rebuild counter.
    static func kegVersion(_ name: String) -> String? {
        var version = name
        if let underscore = version.lastIndex(of: "_"), version[version.index(after: underscore)...].allSatisfy(\.isNumber) {
            version = String(version[..<underscore])
        }
        return NpmVersion(version) == nil ? nil : version
    }

    /// pnpm's standalone binary in its home: `pnpm` there (pnpm 10's layout) or
    /// in `bin` (11's), a file rather than a link. Its version is not read: that
    /// would mean running a binary nothing vouches for.
    func standalonePnpm() -> GlobalPackageManager? {
        let pnpmHome = GlobalPackageHomes.pnpm(home: home)
        for candidate in [pnpmHome.appendingPathComponent("pnpm"), pnpmHome.appendingPathComponent("bin/pnpm")] {
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) == nil,
                  FileManager.default.isExecutableFile(atPath: candidate.path)
            else { continue }
            return GlobalPackageManager(
                tool: .pnpm, version: nil, source: .standalone, path: candidate.path, executable: candidate.path,
                script: nil, runtime: nil)
        }
        return nil
    }

    /// The copy to run for a global install that needs `fits`' versions: the
    /// trusted one with the highest version, else the first that fits, which is
    /// reported with the command to run. nil when none fits.
    static func pick(
        _ managers: [GlobalPackageManager], fits: (GlobalPackageManager) -> Bool
    ) -> GlobalPackageManager? {
        let fitting = managers.filter(fits)
        let trusted = fitting.filter(\.isTrusted).sorted {
            ($0.version.flatMap(NpmVersion.init) ?? NpmVersion(major: 0, minor: 0, patch: 0))
                > ($1.version.flatMap(NpmVersion.init) ?? NpmVersion(major: 0, minor: 0, patch: 0))
        }
        return trusted.first ?? fitting.first
    }
}

/// Is a pnpm or Yarn already changing its global packages right now? Neither
/// documents a lock for them; two at once race on the global `package.json`, its
/// lockfile and `node_modules`, as bun's do (`BunActivity`).
///
/// Told by argv alone, whichever copy runs it: the tool's file — its binary,
/// corepack's shim, `pnpm.cjs`, `yarn.js` — as the program or the script a node
/// runs, then a changing command with `-g` (pnpm) or after `global` (Yarn). As
/// coarse as bun's rule: any such command holds back every package of that tool.
public enum GlobalPackageActivity {

    static let pnpmFiles: Set<String> = ["pnpm", "pnpm.cjs", "pnpm.mjs", "pnpm.js"]
    static let yarnFiles: Set<String> = ["yarn", "yarn.js", "yarn.cjs", "yarnpkg"]
    /// pnpm's commands that write a global install, with their aliases (`pnpm
    /// help`, 10.33.2).
    static let pnpmChanging: Set<String> = [
        "add", "install", "i", "update", "up", "upgrade", "remove", "rm", "uninstall", "un", "link", "ln", "unlink",
    ]
    /// `yarn global`'s commands that write it (`yarn global --help`, 1.22.22).
    static let yarnChanging: Set<String> = ["add", "upgrade", "upgrade-interactive", "remove"]

    public static func busy(_ install: NpmInstall, processes: [NpmActivity.Process]) -> NpmActivity.Busy? {
        guard let tool = install.global?.tool else { return nil }
        for process in processes {
            let arguments = process.arguments
            // The program, or the script right after a node.
            guard let index = arguments.prefix(2).firstIndex(where: {
                (tool == .pnpm ? pnpmFiles : yarnFiles).contains(URL(fileURLWithPath: $0).lastPathComponent)
            }) else { continue }
            let rest = Array(arguments[(index + 1)...])
            switch tool {
            case .pnpm:
                guard let command = rest.first(where: { !$0.hasPrefix("-") }), pnpmChanging.contains(command),
                      rest.contains(where: { $0 == "-g" || $0 == "--global" })
                else { continue }
                return .ownUpdater("pnpm \(command) -g", pid: process.pid)
            case .yarn:
                let words = rest.filter { !$0.hasPrefix("-") }
                guard words.count >= 2, words[0] == "global", yarnChanging.contains(words[1]) else { continue }
                return .ownUpdater("yarn global \(words[1])", pid: process.pid)
            }
        }
        return nil
    }
}
