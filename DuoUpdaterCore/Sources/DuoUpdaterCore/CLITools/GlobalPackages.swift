import Foundation

/// The packages `pnpm add -g` installed, read into the npm group's shape
/// (`NpmInstall`) so the same check holds them, as bun's are (`BunPackages`).
///
/// - **Which packages**: the `dependencies` of each project of pnpm's global
///   install (`GlobalPackageHomes.pnpmProjects`) — pnpm 10's one `global/5`, and
///   pnpm 11's `global/v11/<hash>` links, one per package, which keep their path
///   while each update moves them to a new project (measured 2026-10-13, pnpm
///   11.28.4 and 12.9.1). Each `node_modules/<name>` is a link into pnpm's own
///   store, which is how pnpm installs, not `pnpm link`.
/// - **Which pnpm**: a project's layout needs a pnpm that reads it — 10 or older
///   for `global/5`, 11 or later for `global/v11` (pnpm 11.28.4's `ls -g` finds
///   nothing in a home holding only a pnpm 10 project) — picked from the copies
///   on disk by `GlobalPackageManagers.pick`.
/// - **The node**: a package's commands are `#!/usr/bin/env node` scripts, run
///   on the user's `PATH` node. Its `engines` are held against the node that runs
///   the pnpm when that is a JavaScript copy, else against Homebrew's
///   (`BunPackages.knownNode`), as bun's are.
public struct PnpmPackages: Sendable {

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

    var pnpmHome: URL { GlobalPackageHomes.pnpm(home: home) }

    /// Every package of every project, each checked against the pnpm that
    /// reads its layout among `managers`. Blocking.
    public func scan(managers: [GlobalPackageManager]) -> [NpmInstall] {
        let projects = GlobalPackageHomes.pnpmProjects(in: pnpmHome)
        guard !projects.isEmpty else { return [] }
        let scanner = NpmScanner(home: home, prefixes: [], checkSignature: checkNodeSignature)
        let fallback = BunPackages(home: home, systemPrefixes: systemPrefixes, checkNodeSignature: checkNodeSignature)
            .knownNode()
        let registries = GlobalPackageManagers.npmrcRegistries(home: home)
        var found: [NpmInstall] = []
        for (project, isolated) in projects {
            let manifest = project.appendingPathComponent("package.json")
            let specifiers = BunPackages.specifiers(in: manifest)
            guard !specifiers.isEmpty else { continue }
            let manager = GlobalPackageManagers.pick(managers.filter { $0.tool == .pnpm }) { manager in
                guard let major = manager.major else { return true }
                return isolated ? major >= 11 : major <= 10
            }
            let runtime = manager?.runtime ?? fallback?.runtime ?? NpmRuntime(
                node: nil, npm: nil, npmVersion: nil, nodeSignature: nil, nodeQuarantined: false, nodeVersion: nil)
            let prefix = NodePrefix(path: project.path, source: .pnpm, layoutNodeVersion: runtime.nodeVersion)
            let global = GlobalInstall(
                tool: .pnpm, manager: manager, home: pnpmHome.path, manifest: manifest.path, isolated: isolated)
            let modules = project.appendingPathComponent("node_modules")
            // pnpm 10 and 12 link into the project's `.pnpm`, 11 into the home's store.
            let ownLinks = [modules.appendingPathComponent(".pnpm"), project.appendingPathComponent(".pnpm"),
                            pnpmHome.appendingPathComponent("store")]
            for name in specifiers.keys.sorted() {
                if let install = scanner.package(
                    name, in: modules, prefix: prefix, runtime: runtime, registries: registries,
                    npmrcPrefixElsewhere: nil, global: global, specifier: specifiers[name], ownLinks: ownLinks) {
                    found.append(install)
                }
            }
        }
        return found
    }
}

/// The packages `yarn global add` installed — Yarn 1's; Yarn 2 and later have
/// no global packages — read from its global folder, `~/.config/yarn/global`
/// (`yarn global dir`, 1.22.22, measured 2026-10-13), as bun's and pnpm's are.
/// Its `node_modules` holds real directories, so a link there is `yarn link`'s.
public struct YarnPackages: Sendable {

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

    var global: URL { home.appendingPathComponent(".config/yarn/global") }

    /// Every package of the global folder, checked against the Yarn 1 among
    /// `managers` that would run the update. Blocking.
    public func scan(managers: [GlobalPackageManager]) -> [NpmInstall] {
        let manifest = global.appendingPathComponent("package.json")
        let specifiers = BunPackages.specifiers(in: manifest)
        guard !specifiers.isEmpty else { return [] }
        let manager = GlobalPackageManagers.pick(managers.filter { $0.tool == .yarn }) { $0.major == 1 }
        let fallback = BunPackages(home: home, systemPrefixes: systemPrefixes, checkNodeSignature: checkNodeSignature)
            .knownNode()
        let runtime = manager?.runtime ?? fallback?.runtime ?? NpmRuntime(
            node: nil, npm: nil, npmVersion: nil, nodeSignature: nil, nodeQuarantined: false, nodeVersion: nil)
        let prefix = NodePrefix(path: global.path, source: .yarn, layoutNodeVersion: runtime.nodeVersion)
        let install = GlobalInstall(tool: .yarn, manager: manager, home: global.path, manifest: manifest.path, isolated: false)
        let scanner = NpmScanner(home: home, prefixes: [], checkSignature: checkNodeSignature)
        let registries = GlobalPackageManagers.npmrcRegistries(home: home)
        let modules = global.appendingPathComponent("node_modules")
        return specifiers.keys.sorted().compactMap {
            scanner.package($0, in: modules, prefix: prefix, runtime: runtime, registries: registries,
                            npmrcPrefixElsewhere: nil, global: install, specifier: specifiers[$0])
        }
    }
}

extension GlobalPackageManagers {
    /// The registry keys of the user's `~/.npmrc` (`registry`, `@scope:registry`),
    /// which pnpm and Yarn 1 both read, shaped as `NpmScanner.customRegistry` wants.
    static func npmrcRegistries(home: URL) -> [(key: String, value: String, file: String)] {
        let npmrc = home.appendingPathComponent(".npmrc")
        return NodePrefixes.npmrcEntries(in: npmrc)
            .filter { $0.key == "registry" || ($0.key.hasPrefix("@") && $0.key.hasSuffix(":registry")) }
            .reversed()
            .map { ($0.key, $0.value, npmrc.path) }
    }
}
