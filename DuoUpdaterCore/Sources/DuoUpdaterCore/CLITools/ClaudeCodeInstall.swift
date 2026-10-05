import Foundation
import Security

/// One copy of Claude Code on this Mac, identified by **where it is**.
///
/// Claude Code is the first command-line tool DuoUpdater tracks, and it is not an
/// `.app`: nothing the bundle scanner finds, no Info.plist (`codesign` reports
/// `Info.plist=not bound`). What makes it trackable anyway is that every way of
/// installing it lands the *same* Developer ID binary — Team `Q6L2SF6YDW`,
/// signed identifier `com.anthropic.claude-code` — so the signature is as hard an
/// anchor as it is for an app, and the vendor publishes a per-version manifest
/// (size + sha256 per platform) that pins which release a file is.
///
/// Identity is the path. Two copies under two nvm node versions are two installs,
/// each updated by its own npm; a native install and an npm install are never
/// merged, and an update never moves a copy from one to the other. `method` says
/// who installed it, and so who is allowed to update it.
public struct ClaudeCodeInstall: Sendable, Equatable, Codable {

    /// Who put it there, read from the layout on disk — never from `PATH`, which
    /// a GUI process does not have.
    public enum Method: String, Sendable, Codable {
        /// `curl -fsSL https://claude.ai/install.sh | bash`: `~/.local/bin/claude`
        /// is a symlink into `~/.local/share/claude/versions/<version>`.
        case native
        /// `npm install -g @anthropic-ai/claude-code` under one node prefix.
        case npm
        /// `pnpm add -g`, under pnpm's content-addressed `.pnpm` store.
        case pnpm
        /// `bun add -g`, under `~/.bun/install/global`. Detection only: Anthropic's
        /// docs name no bun update command.
        case bun
        /// A path the user added that matches none of the layouts above.
        case unknown
    }

    public enum Origin: String, Sendable, Codable {
        /// Found by looking where the vendor's installers put it.
        case conventional
        /// Added by hand, for a layout we do not look in by ourselves.
        case userAdded
    }

    /// Whether the executable is Anthropic's, checked against the code seal —
    /// not just what the signature *claims*, which a tampered file still reports.
    public enum Signature: String, Sendable, Codable {
        case anthropic
        /// Signed, and the seal is intact, but not by Anthropic's team — or not
        /// as `com.anthropic.claude-code`.
        case otherSigner
        /// Unsigned, a broken seal, or not code at all.
        case invalid
    }

    public enum Problem: String, Sendable, Codable {
        /// The launcher points at nothing, or at a zero-byte file — what a failed
        /// native install leaves behind in `versions/`.
        case executableMissing
        /// The npm-family package is present but its native binary is not. pnpm
        /// 10.33, 11.28.4 and 12.9.1 skip postinstall by default (measured;
        /// `--allow-build=@anthropic-ai/claude-code` runs it), and then
        /// `bin/claude.exe` is a 500-byte script that prints "claude native
        /// binary not installed". bun 1.4.2 skips it too — not for trust (the
        /// package is on its default trusted list) but by its postinstall
        /// optimizer, which links the shim past that script to the platform
        /// package's binary instead — so a bun install runs (measured).
        case nativeBinaryNotLinked
    }

    /// The identity: the launcher for a native install, the package directory for
    /// the npm family, or whatever the user added.
    public let path: String
    public let method: Method
    public let origin: Origin
    /// The file that actually runs, symlinks resolved.
    public let executable: String?
    /// What the layout says the version is: the `versions/` file name, or the
    /// package's `package.json`. A claim until `ClaudeCodeRelease.confirm` has
    /// held it against the vendor's manifest.
    public let version: String?
    public let signature: Signature?
    public let problem: Problem?
    /// The node prefix an npm install lives in. Its own `bin/node` and `bin/npm`
    /// are the only tools that may update it.
    public let nodePrefix: String?

    public init(
        path: String, method: Method, origin: Origin, executable: String?,
        version: String?, signature: Signature?, problem: Problem?, nodePrefix: String? = nil
    ) {
        self.path = path
        self.method = method
        self.origin = origin
        self.executable = executable
        self.version = version
        self.signature = signature
        self.problem = problem
        self.nodePrefix = nodePrefix
    }
}

/// Finds Claude Code installs: convention first — the places each vendor-documented
/// installer writes to — plus any paths the user added by hand.
///
/// Network-free and does not run the binary: every fact comes from the layout, the
/// package metadata and the code signature.
public struct ClaudeCodeScanner: Sendable {

    public static let teamIdentifier = "Q6L2SF6YDW"
    public static let signingIdentifier = "com.anthropic.claude-code"
    static let packagePath = "node_modules/@anthropic-ai/claude-code"

    /// Checks a file's signature. Injected so tests can build fake installs out of
    /// plain files without depending on what is signed on the host.
    public typealias SignatureCheck = @Sendable (URL) -> ClaudeCodeInstall.Signature

    let home: URL
    let systemPrefixes: [URL]
    let checkSignature: SignatureCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemPrefixes: [URL] = [URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local")],
        checkSignature: @escaping SignatureCheck = ClaudeCodeScanner.verifyAnthropicSignature
    ) {
        self.home = home
        self.systemPrefixes = systemPrefixes
        self.checkSignature = checkSignature
    }

    /// Every install found, conventional ones first, each path at most once.
    /// Blocking file-system and Security work: keep it off the cooperative pool.
    public func scan(userPaths: [String] = []) -> [ClaudeCodeInstall] {
        var found: [ClaudeCodeInstall] = []
        if let native = nativeInstall() { found.append(native) }
        for prefix in nodePrefixes() {
            if let npm = packageInstall(
                at: prefix.appendingPathComponent("lib").appendingPathComponent(Self.packagePath),
                method: .npm, origin: .conventional, nodePrefix: prefix
            ) {
                found.append(npm)
            }
        }
        found.append(contentsOf: pnpmInstalls())
        if let bun = packageInstall(
            at: home.appendingPathComponent(".bun/install/global").appendingPathComponent(Self.packagePath),
            method: .bun, origin: .conventional, launcher: home.appendingPathComponent(".bun/bin/claude")
        ) {
            found.append(bun)
        }
        var seen = Set(found.map(\.path))
        for raw in userPaths {
            guard let install = userInstall(at: raw), seen.insert(install.path).inserted else { continue }
            found.append(install)
        }
        return found.filter {
            Self.owningApp(of: $0.path) == nil && Self.owningApp(of: $0.executable) == nil
                && Self.homebrewCask(of: $0.path) == nil
        }
    }

    /// The Homebrew cask a path belongs to (`claude-code` or `claude-code@latest`),
    /// as given or once symlinks are resolved, or nil.
    ///
    /// Such a copy is Homebrew's: the cask name picks its channel, `brew upgrade`
    /// updates it, and DuoUpdater's Homebrew list already shows it — an app-less
    /// cask has a row there. Reporting it here too would offer the same update
    /// twice, from two installers.
    public static func homebrewCask(of path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        for candidate in [url, url.resolvingSymlinksInPath()] {
            let components = candidate.pathComponents
            if let index = components.firstIndex(of: "Caskroom"), index + 1 < components.count {
                return components[index + 1]
            }
        }
        return nil
    }

    /// The `.app` a path lives inside — as given, or once symlinks are resolved —
    /// or nil.
    ///
    /// A copy inside an app bundle belongs to that app: it ships and updates with
    /// it (Claude.app runs its own `…/claude-code/<v>/claude.app/Contents/MacOS/claude`;
    /// `~/.local/bin/cua-driver` links into `CuaDriver.app`). Detecting it would
    /// report an "update" the app is about to deliver itself, and updating it would
    /// break the bundle's seal — so such a path is neither checked nor updated,
    /// even when the user adds it by hand.
    public static func owningApp(of path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        for candidate in [url, url.resolvingSymlinksInPath()] {
            var directory = candidate
            while directory.path != "/" {
                if directory.pathExtension.lowercased() == "app" { return directory }
                directory.deleteLastPathComponent()
            }
        }
        return nil
    }

    // MARK: - Native

    var nativeLauncher: URL { home.appendingPathComponent(".local/bin/claude") }
    var nativeVersions: URL { home.appendingPathComponent(".local/share/claude/versions") }

    /// The launcher is the install; the `versions/` entry it points at is which
    /// release it runs. Older entries beside it are the native installer's own
    /// rollback copies, not further installs.
    func nativeInstall() -> ClaudeCodeInstall? {
        let fm = FileManager.default
        let launcher = nativeLauncher
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: launcher.path) else {
            // A regular file here is a custom launcher, which the docs allow (it
            // "decides which version runs"). We cannot tell which version that is
            // without running it, so it is not reported as a native install.
            return nil
        }
        let target = URL(fileURLWithPath: destination, relativeTo: launcher.deletingLastPathComponent())
            .standardizedFileURL
        guard target.deletingLastPathComponent().path == nativeVersions.standardizedFileURL.path else {
            return nil
        }
        return ClaudeCodeInstall(
            path: launcher.path, method: .native, origin: .conventional,
            executable: target.path, version: target.lastPathComponent,
            signature: nonEmptyFile(target) ? checkSignature(target) : nil,
            problem: nonEmptyFile(target) ? nil : .executableMissing)
    }

    // MARK: - npm family

    /// Node prefixes whose `lib/node_modules` is a global npm root: Homebrew's and
    /// `/usr/local`'s node, each node version nvm and fnm manage, and
    /// `~/.npm-global` (`NodePrefixes`, shared with the npm packages group).
    func nodePrefixes() -> [URL] {
        NodePrefixes(home: home, systemPrefixes: systemPrefixes).discover(NodePrefixes.claudeCodeSources).map(\.url)
    }

    /// Every pnpm project under pnpm's home (`GlobalPackageHomes.pnpmProjects`):
    /// pnpm 10's `global/<layout version>`, whose `node_modules/@anthropic-ai/claude-code`
    /// links into `.pnpm/…`, and pnpm 11's and later's `global/v11/<hash>` group
    /// links, whose package links into `store/v11/links/…`. The path keeps the
    /// hash link, which is the group's identity across updates.
    func pnpmInstalls() -> [ClaudeCodeInstall] {
        GlobalPackageHomes.pnpmProjects(in: GlobalPackageHomes.pnpm(home: home)).compactMap {
            packageInstall(
                at: $0.project.appendingPathComponent(Self.packagePath),
                method: .pnpm, origin: .conventional)
        }
    }

    /// The package directory is the install. Its `bin/claude.exe` is what the
    /// package manager's shim runs; postinstall hard-links the platform package's
    /// binary there, and when postinstall was skipped it is a placeholder script.
    ///
    /// A `launcher` that links somewhere under the same `node_modules` is what
    /// runs instead — bun's `~/.bun/bin/claude` points straight at
    /// `@anthropic-ai/claude-code-darwin-<arch>/claude`.
    func packageInstall(
        at package: URL, method: ClaudeCodeInstall.Method, origin: ClaudeCodeInstall.Origin,
        nodePrefix: URL? = nil, launcher: URL? = nil
    ) -> ClaudeCodeInstall? {
        let manifest = package.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["name"] as? String == "@anthropic-ai/claude-code"
        else { return nil }
        let modules = package.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        let linked = launcher.flatMap { launcher -> URL? in
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: launcher.path)) != nil else { return nil }
            let target = launcher.resolvingSymlinksInPath()
            return target.path.hasPrefix(modules.path + "/") ? target : nil
        }
        let executable = linked ?? package.appendingPathComponent("bin/claude.exe").resolvingSymlinksInPath()
        let isBinary = Self.isMachO(executable)
        return ClaudeCodeInstall(
            path: package.path, method: method, origin: origin,
            executable: executable.path, version: json["version"] as? String,
            signature: isBinary ? checkSignature(executable) : nil,
            problem: isBinary ? nil : .nativeBinaryNotLinked,
            nodePrefix: nodePrefix?.path)
    }

    // MARK: - User-added

    /// A path the user pointed at: a launcher, a binary, or a package directory.
    ///
    /// Only an npm-family package gets the same reading as a conventional one:
    /// its prefix's own npm updates it where it is. A native binary outside
    /// `~/.local/share/claude` stays `.unknown` — detection only — because
    /// `claude update` always writes to that fixed location, so offering it here
    /// would update a different place than the row shows.
    func userInstall(at raw: String) -> ClaudeCodeInstall? {
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        if url.path.hasSuffix("/" + Self.packagePath) {
            return userPackage(url)
        }
        if let range = resolved.path.range(of: "/" + Self.packagePath + "/") {
            return userPackage(URL(fileURLWithPath: String(resolved.path[..<range.lowerBound]) + "/" + Self.packagePath))
        }
        guard nonEmptyFile(resolved) else { return nil }
        let signature = checkSignature(resolved)
        // Nothing to say it is Claude Code but the signature — so a file that is
        // not Anthropic's is not reported at all, rather than as a broken install.
        guard signature == .anthropic else { return nil }
        let version = resolved.deletingLastPathComponent().lastPathComponent == "versions"
            ? resolved.lastPathComponent : nil
        return ClaudeCodeInstall(
            path: url.path, method: .unknown, origin: .userAdded,
            executable: resolved.path, version: version, signature: signature, problem: nil)
    }

    /// A package directory outside the conventional roots, classified by the same
    /// layout rules: in pnpm 11's `store/v11/links` it is the pnpm group that
    /// uses it (`pnpmStoreInstall`); inside a `.pnpm` store it is pnpm's; under `<root>/install/global`
    /// it is bun's; directly under a node
    /// prefix (`<prefix>/lib/node_modules/…`) with that prefix's own `bin/npm`, it
    /// is npm's and is updated by that npm.
    func userPackage(_ package: URL) -> ClaudeCodeInstall? {
        let path = package.resolvingSymlinksInPath().path
        if let store = path.range(of: #"/store/v[0-9]+/links/"#, options: .regularExpression) {
            return pnpmStoreInstall(resolved: path, pnpmHome: URL(fileURLWithPath: String(path[..<store.lowerBound])))
        }
        if path.contains("/.pnpm/") {
            return packageInstall(at: package, method: .pnpm, origin: .userAdded)
        }
        // bun's global directory under a custom `BUN_INSTALL`: `<root>/install/global`,
        // with the shim at `<root>/bin/claude`.
        let bunSuffix = "/install/global/" + Self.packagePath
        if package.path.hasSuffix(bunSuffix) {
            let root = URL(fileURLWithPath: String(package.path.dropLast(bunSuffix.count)))
            return packageInstall(
                at: package, method: .bun, origin: .userAdded,
                launcher: root.appendingPathComponent("bin/claude"))
        }
        let suffix = "/lib/" + Self.packagePath
        if package.path.hasSuffix(suffix) {
            let prefix = URL(fileURLWithPath: String(package.path.dropLast(suffix.count)))
            if FileManager.default.fileExists(atPath: prefix.appendingPathComponent("bin/npm").path) {
                return packageInstall(at: package, method: .npm, origin: .userAdded, nodePrefix: prefix)
            }
        }
        return packageInstall(at: package, method: .unknown, origin: .userAdded)
    }

    /// A package in pnpm 11's shared store, `<pnpm home>/store/v11/links/…/<version>/…`,
    /// is one version's copy: the next `pnpm add -g` moves the group's link to a
    /// new copy and leaves this one until `pnpm store prune` (both measured with
    /// 11.28.4, 2026-10-06). So the install is
    /// the group whose package resolves to it, read at its `global/v11/<hash>`
    /// link like a conventional one (and so listed once beside it); a copy no
    /// group uses is a leftover, not an install.
    func pnpmStoreInstall(resolved path: String, pnpmHome: URL) -> ClaudeCodeInstall? {
        // pnpm's default home spelled as the scan spells it, so the group's path
        // matches the conventional install's.
        let defaultHome = GlobalPackageHomes.pnpm(home: home)
        let pnpmHome = defaultHome.resolvingSymlinksInPath().path == pnpmHome.path ? defaultHome : pnpmHome
        let group = GlobalPackageHomes.pnpmProjects(in: pnpmHome)
            .filter(\.isolated)
            .map { $0.project.appendingPathComponent(Self.packagePath) }
            .first { $0.resolvingSymlinksInPath().path == path }
        return group.flatMap { packageInstall(at: $0, method: .pnpm, origin: .userAdded) }
    }

    // MARK: - Files

    func nonEmptyFile(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return size > 0
    }

    /// A Mach-O (thin or fat) header, as opposed to the placeholder shell script
    /// the npm package ships at `bin/claude.exe` until postinstall replaces it.
    static func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let magic = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xFEEDFACF, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(magic)
    }

    /// The code seal must be intact **and** satisfy Anthropic's designated
    /// requirement — a Developer ID leaf for team `Q6L2SF6YDW` with identifier
    /// `com.anthropic.claude-code` — before anything about the file is believed.
    public static func verifyAnthropicSignature(_ url: URL) -> ClaudeCodeInstall.Signature {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return .invalid
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { return .invalid }
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
            + " and identifier \"\(signingIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return .invalid }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess ? .anthropic : .otherSigner
    }
}
