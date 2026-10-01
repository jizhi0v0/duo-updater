import Foundation

/// One package installed with `npm install -g`, identified by **where it is**:
/// `<prefix>/lib/node_modules/<name>` (or `@scope/name`). The same package under
/// two node versions is two installs, each updated by its own prefix's npm.
///
/// Only packages that put a command on `PATH` — a `bin` in their `package.json`
/// — are listed: a global library (`docx`, 2026-10-01 on this Mac) is nothing a
/// user runs, and npm's own `npm` and `corepack` ship with node itself.
/// `@anthropic-ai/claude-code` has its own group (`ClaudeCode*`).
public struct NpmInstall: Sendable, Equatable, Codable {

    /// The package directory.
    public let path: String
    /// The name npm installed it under: the directory's, `@scope/name` for a
    /// scoped package. What `npm install -g <name>@<version>` would replace.
    public let name: String
    /// `package.json`'s `version`.
    public let version: String?
    /// `package.json`'s `name`. Differs from `name` only for an alias install
    /// (`npm i -g foo@npm:bar`), whose registry package is this one.
    public let manifestName: String?
    public let prefix: NodePrefix
    public let runtime: NpmRuntime
    /// Where the package directory links to, when it is a symlink: what
    /// `npm link` and `npm install -g ./dir` leave — a working copy, not a
    /// registry release.
    public let linkTarget: String?
    /// `package.json`'s `repository`, as written (a URL or a `github:` shorthand).
    public let repository: String?
    /// A registry other than npm's own, configured for this package.
    public let customRegistry: CustomRegistry?
    /// The package's own update command, for the packages that have one.
    public let ownUpdate: NpmOwnUpdate?
    /// The npmrc whose `prefix=` names another prefix than this one: where a
    /// bare `npm i -g` from this prefix's npm would install (`NpmScanner.npmrcPrefixElsewhere`).
    public let npmrcPrefixElsewhere: String?

    /// The `registry` (or `@scope:registry`) an npmrc sets, and in which file.
    /// Only that key is read — never an auth token.
    public struct CustomRegistry: Sendable, Equatable, Codable {
        public let url: String
        public let file: String
    }

    public init(
        path: String, name: String, version: String?, manifestName: String?, prefix: NodePrefix,
        runtime: NpmRuntime, linkTarget: String? = nil, repository: String? = nil,
        customRegistry: CustomRegistry? = nil, ownUpdate: NpmOwnUpdate? = nil, npmrcPrefixElsewhere: String? = nil
    ) {
        self.path = path
        self.name = name
        self.version = version
        self.manifestName = manifestName
        self.prefix = prefix
        self.runtime = runtime
        self.linkTarget = linkTarget
        self.repository = repository
        self.customRegistry = customRegistry
        self.ownUpdate = ownUpdate
        self.npmrcPrefixElsewhere = npmrcPrefixElsewhere
    }
}

/// The node and npm a prefix runs on — what its packages' `engines` are held
/// against, and what an update would run.
public struct NpmRuntime: Sendable, Equatable, Codable {
    /// `<prefix>/bin/node`, when it is an executable.
    public let node: String?
    /// `<prefix>/bin/npm`, when the prefix has node too: npm is a script, and
    /// only this prefix's node is known to be the one it belongs with.
    public let npm: String?
    /// `lib/node_modules/npm/package.json`'s version.
    public let npmVersion: String?
    /// The node binary's signature, measured against the Node.js Foundation's
    /// Team ID (`NpmScanner.nodeTeamIdentifier`).
    public let nodeSignature: CLIToolTrust.Signature?
    public let nodeQuarantined: Bool
    /// From the layout (`NodePrefix.layoutNodeVersion`), or from
    /// `node --version` of a Node.js-signed binary when the layout does not say.
    public let nodeVersion: String?

    public init(
        node: String?, npm: String?, npmVersion: String?, nodeSignature: CLIToolTrust.Signature?,
        nodeQuarantined: Bool, nodeVersion: String?
    ) {
        self.node = node
        self.npm = npm
        self.npmVersion = npmVersion
        self.nodeSignature = nodeSignature
        self.nodeQuarantined = nodeQuarantined
        self.nodeVersion = nodeVersion
    }

    public func with(nodeVersion: String?) -> NpmRuntime {
        NpmRuntime(node: node, npm: npm, npmVersion: npmVersion, nodeSignature: nodeSignature,
                   nodeQuarantined: nodeQuarantined, nodeVersion: nodeVersion)
    }
}

/// A package whose vendor documents its own update command.
public enum NpmOwnUpdate: Sendable, Equatable, Codable {
    /// `openclaw update`, with what its config says.
    case openclaw(OpenClawSettings)
    /// `agent-browser upgrade` — not run (`NpmCheck.updateCommand`), but watched
    /// for by the busy check.
    case agentBrowser
}

/// The parts of `~/.openclaw/openclaw.json` that decide an update, and whether
/// the installed openclaw documents `--tag`.
///
/// openclaw 2026.3.28's `update` (read in its `dist/update-cli-*.js` and
/// `docs/cli/update.md`, 2026-10-02): the channel is `update.channel` —
/// `stable` (dist-tag `latest`, the default for an npm install), `beta` (dist-tag
/// `beta`, falling back to `latest` when that is newer) or `dev` (a git checkout).
/// `update.auto.enabled` turns its own auto-updater on; it is off unless set.
public struct OpenClawSettings: Sendable, Equatable, Codable {
    /// `update.channel` as written, nil when unset or unreadable.
    public let channel: String?
    /// `update.auto.enabled`, nil when unset.
    public let autoUpdate: Bool?
    /// The installed package's `docs/cli/update.md` documents `--tag <dist-tag|version|spec>`,
    /// which pins the exact version this check chose.
    public let supportsTag: Bool

    public init(channel: String?, autoUpdate: Bool?, supportsTag: Bool) {
        self.channel = channel
        self.autoUpdate = autoUpdate
        self.supportsTag = supportsTag
    }

    /// The channel openclaw itself would use: an unknown value reads as unset
    /// (`normalizeUpdateChannel`), and unset is `stable` for a package install.
    public var effectiveChannel: String {
        let normalized = channel?.trimmingCharacters(in: .whitespaces).lowercased()
        return ["stable", "beta", "dev"].contains(normalized ?? "") ? normalized! : "stable"
    }

    /// The config, read as openclaw reads it (JSON5). Unreadable or missing reads
    /// as defaults, as it does for openclaw (an invalid config has no stored channel).
    static func read(home: URL, package: URL) -> OpenClawSettings {
        let docs = package.appendingPathComponent("docs/cli/update.md")
        let supportsTag = (try? String(contentsOf: docs, encoding: .utf8))?
            .contains("--tag <dist-tag|version|spec>") ?? false
        let config = home.appendingPathComponent(".openclaw/openclaw.json")
        guard let data = try? Data(contentsOf: config),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any],
              let update = json["update"] as? [String: Any]
        else { return OpenClawSettings(channel: nil, autoUpdate: nil, supportsTag: supportsTag) }
        let auto = (update["auto"] as? [String: Any])?["enabled"] as? Bool
        return OpenClawSettings(channel: update["channel"] as? String, autoUpdate: auto, supportsTag: supportsTag)
    }
}

/// Finds globally installed npm CLIs under every node prefix (`NodePrefixes`).
///
/// Network-free and runs nothing: every fact comes from the layout, the
/// packages' `package.json`, the npmrc files and node's code signature.
public struct NpmScanner: Sendable {

    /// The Node.js Foundation's Team ID, which nodejs.org's macOS binaries carry
    /// (`codesign -dvv`, 2026-10-02: nvm's v24.13.0 and fnm's v22.21.1 and
    /// v24.12.0, all "Developer ID Application: Node.js Foundation (HX7739G8FX)").
    /// Homebrew's node is ad hoc signed (26.10.0_1, same day).
    public static let nodeTeamIdentifier = "HX7739G8FX"

    /// Ship with node, or have their own group.
    static let excluded: Set<String> = ["npm", "corepack", "@anthropic-ai/claude-code"]

    static let defaultRegistry = "https://registry.npmjs.org/"

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature

    let home: URL
    let prefixes: [NodePrefix]
    let checkSignature: SignatureCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        prefixes: [NodePrefix]? = nil,
        checkSignature: @escaping SignatureCheck = { CLIToolTrust.signature(of: $0, teamIdentifier: NpmScanner.nodeTeamIdentifier) }
    ) {
        self.home = home
        self.prefixes = prefixes ?? NodePrefixes(home: home).discover()
        self.checkSignature = checkSignature
    }

    /// Every CLI package in every prefix, each prefix once (by its resolved path,
    /// first source wins). Blocking file-system and Security work: keep it off
    /// the cooperative pool.
    public func scan() -> [NpmInstall] {
        var seen = Set<String>()
        var found: [NpmInstall] = []
        for prefix in prefixes {
            let resolved = prefix.url.resolvingSymlinksInPath().path
            guard seen.insert(resolved).inserted else { continue }
            let modules = prefix.url.appendingPathComponent("lib/node_modules")
            let names = Self.packageNames(in: modules)
            guard !names.isEmpty else { continue }
            let runtime = self.runtime(of: prefix)
            let registries = Self.registryConfig(home: home, prefix: prefix.url)
            let elsewhere = Self.npmrcPrefixElsewhere(home: home, prefix: prefix)
            for name in names {
                if let install = package(name, in: modules, prefix: prefix, runtime: runtime, registries: registries,
                                         npmrcPrefixElsewhere: elsewhere) {
                    found.append(install)
                }
            }
        }
        return found
    }

    /// `name` and `@scope/name` entries of a `node_modules`, sorted; dot entries
    /// (npm's `.package-lock.json`, its `.<name>-<hash>` staging directories)
    /// are not packages.
    static func packageNames(in modules: URL) -> [String] {
        let fm = FileManager.default
        let top = ((try? fm.contentsOfDirectory(atPath: modules.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        return top.flatMap { entry -> [String] in
            guard entry.hasPrefix("@") else { return [entry] }
            let scoped = ((try? fm.contentsOfDirectory(atPath: modules.appendingPathComponent(entry).path)) ?? [])
            return scoped.filter { !$0.hasPrefix(".") }.sorted().map { entry + "/" + $0 }
        }
    }

    func package(
        _ name: String, in modules: URL, prefix: NodePrefix, runtime: NpmRuntime,
        registries: [(key: String, value: String, file: String)], npmrcPrefixElsewhere: String?
    ) -> NpmInstall? {
        guard !Self.excluded.contains(name) else { return nil }
        let directory = modules.appendingPathComponent(name)
        let link = try? FileManager.default.destinationOfSymbolicLink(atPath: directory.path)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Self.hasBin(json)
        else { return nil }
        let manifestName = json["name"] as? String
        if let manifestName, Self.excluded.contains(manifestName) { return nil }
        let repository: String? = (json["repository"] as? String)
            ?? ((json["repository"] as? [String: Any])?["url"] as? String)
        let ownUpdate: NpmOwnUpdate?
        switch manifestName ?? name {
        case "openclaw": ownUpdate = .openclaw(OpenClawSettings.read(home: home, package: directory))
        case "agent-browser": ownUpdate = .agentBrowser
        default: ownUpdate = nil
        }
        return NpmInstall(
            path: directory.path, name: name, version: json["version"] as? String, manifestName: manifestName,
            prefix: prefix, runtime: runtime,
            linkTarget: link.map { URL(fileURLWithPath: $0, relativeTo: directory.deletingLastPathComponent()).standardizedFileURL.path },
            repository: repository,
            customRegistry: Self.customRegistry(for: manifestName ?? name, in: registries),
            ownUpdate: ownUpdate, npmrcPrefixElsewhere: npmrcPrefixElsewhere)
    }

    /// A command on `PATH`: `bin` as a path or a non-empty map, or the older
    /// `directories.bin`, which npm turns into links the same way.
    static func hasBin(_ json: [String: Any]) -> Bool {
        if let bin = json["bin"] as? String, !bin.isEmpty { return true }
        if let bin = json["bin"] as? [String: Any], !bin.isEmpty { return true }
        if let directories = json["directories"] as? [String: Any], directories["bin"] is String { return true }
        return false
    }

    func runtime(of prefix: NodePrefix) -> NpmRuntime {
        let fm = FileManager.default
        let bin = prefix.url.appendingPathComponent("bin")
        let nodeURL = bin.appendingPathComponent("node")
        let node = fm.isExecutableFile(atPath: nodeURL.path) ? nodeURL.path : nil
        let npmURL = bin.appendingPathComponent("npm")
        let npm = node != nil && fm.fileExists(atPath: npmURL.path) ? npmURL.path : nil
        let npmManifest = prefix.url.appendingPathComponent("lib/node_modules/npm/package.json")
        let npmVersion = (try? Data(contentsOf: npmManifest))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["version"] as? String
        let resolved = nodeURL.resolvingSymlinksInPath()
        return NpmRuntime(
            node: node, npm: npm, npmVersion: npmVersion,
            nodeSignature: node == nil ? nil : checkSignature(resolved),
            nodeQuarantined: node == nil ? false : CLIToolTrust.hasQuarantine(resolved),
            nodeVersion: prefix.layoutNodeVersion)
    }

    /// The npmrc that sets a `prefix` other than `prefix`, or nil. The user's
    /// `~/.npmrc` is read before the prefix's own global `etc/npmrc`, as npm does.
    /// A bare `npm i -g` — what openclaw's own update runs — installs there.
    static func npmrcPrefixElsewhere(home: URL, prefix: NodePrefix) -> String? {
        let own = prefix.url.resolvingSymlinksInPath().path
        for file in [home.appendingPathComponent(".npmrc"), prefix.url.appendingPathComponent("etc/npmrc")] {
            guard let set = NodePrefixes.npmrcPrefix(in: file, home: home) else { continue }
            return URL(fileURLWithPath: set).resolvingSymlinksInPath().path == own ? nil : file.path
        }
        return nil
    }

    // MARK: - Registry configuration

    /// The `registry` and `@scope:registry` keys of the npmrc files a global
    /// install of this prefix reads, in npm's precedence: the user's `~/.npmrc`,
    /// then the prefix's global `etc/npmrc`, then npm's own builtin `npmrc`.
    /// Every other key — tokens included — is left where it is.
    static func registryConfig(home: URL, prefix: URL) -> [(key: String, value: String, file: String)] {
        let files = [
            home.appendingPathComponent(".npmrc"),
            prefix.appendingPathComponent("etc/npmrc"),
            prefix.appendingPathComponent("lib/node_modules/npm/npmrc"),
        ]
        return files.flatMap { file in
            NodePrefixes.npmrcEntries(in: file)
                .filter { $0.key == "registry" || ($0.key.hasPrefix("@") && $0.key.hasSuffix(":registry")) }
                .reversed()  // the last one in a file wins
                .map { ($0.key, $0.value, file.path) }
        }
    }

    /// The first configured registry that applies to `name`, unless it is npm's own.
    static func customRegistry(
        for name: String, in entries: [(key: String, value: String, file: String)]
    ) -> NpmInstall.CustomRegistry? {
        let scopeKey = name.hasPrefix("@") ? name.split(separator: "/").first.map { "\($0):registry" } : nil
        let entry = entries.first { $0.key == scopeKey } ?? entries.first { $0.key == "registry" }
        guard let entry else { return nil }
        let normalized = entry.value.hasSuffix("/") ? entry.value : entry.value + "/"
        guard normalized.lowercased() != defaultRegistry else { return nil }
        return NpmInstall.CustomRegistry(url: entry.value, file: entry.file)
    }
}
