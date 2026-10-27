import Foundation

/// The Rubies rbenv builds (`~/.rbenv/versions/<x.y.z>`) as managed rows, one
/// per minor (D1), moved by `rbenv install <x.y.z>` through ruby-build
/// (design §4.8).
///
/// Measured 2026-10-27 with rbenv 1.3.2 and ruby-build 20261023, cloned into
/// an isolated `RBENV_ROOT` and from Homebrew in the real home:
/// - **Newest, no network, no spawn**: the file names under ruby-build's
///   `share/ruby-build` (703); CRuby is the bare `x.y.z` names, so `-dev`,
///   `-preview`, `-rc` and the other implementations (`jruby-…`, `truffleruby-…`)
///   are no line. ruby-build is `$RBENV_ROOT/plugins/ruby-build` (a
///   checkout) or Homebrew's own keg, `opt/ruby-build` (RB-03/04).
/// - **The command**: `rbenv install <x.y.z>` with `PATH` holding Homebrew's
///   `bin`, without which Homebrew's rbenv cannot find `install` (review fact
///   1). Pins are exact names and never move (RB-12/19). Homebrew's rbenv
///   built 3.4.12 beside 3.4.11 in 2:00 (download, configure, `make`,
///   `make install`); a checkout built 3.4.11 in 3:41.
/// - **Interrupted** (§13.3): while downloading, exit 130/1/143 with no
///   `versions/<x.y.z>` left, the old Ruby running; each run left its
///   half-downloaded source and log under `/tmp/ruby-build.*`. The build and
///   install stages were not hit apart.
///
/// rbenv and ruby-build are bash, unsigned (`codesign -dv`: "not signed at
/// all"). Homebrew's are `Cellar/rbenv/<v>/libexec/rbenv` and
/// `Cellar/ruby-build/<v>/share/ruby-build`. One-click needs both from Homebrew (D5.1)
/// and no ruby-build checkout under the root that rbenv would run instead; a
/// checkout is handed out to copy (D5.2).
public struct RbenvAdapter: ManagerAdapter {

    public static let id = ManagerID("rbenv")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "rbenv", signer: nil, logo: nil, tint: .label, lane: "rbenv",
        deadline: DefinitionLines.deadline)

    public var descriptor: ManagerDescriptor { Self.descriptor }

    public typealias Host = PyenvAdapter.Host

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

    var root: String { home.path + "/.rbenv" }

    // MARK: - ManagerAdapter

    public func scan() async -> ManagedScan {
        let host = self.host
        let root = self.root
        let descriptor = self.descriptor
        return await offCooperativePool {
            guard let names = host.directories(root + "/versions") else { return .empty }
            let found = locate()
            let items = DefinitionLines.items(
                names: names, root: root, title: "Ruby", interpreter: "bin/ruby",
                definitions: found.definitions, knownBy: found.rubyBuild.map { "ruby-build \($0)" },
                global: DefinitionLines.global(host.contents(root + "/version")), descriptor: descriptor,
                exists: host.exists)
            guard !items.isEmpty else { return .empty }
            var states: [String: String] = [:]
            for item in items {
                states[item.identity] = ([item.installed ?? "-", item.latestOverall ?? "-"] + item.alsoInstalled).joined(separator: ",")
            }
            return ManagedScan(
                roots: [ManagedRoot(manager: Self.id, path: root, binary: found.binary)], items: items, states: states)
        }
    }

    public func check(_ scan: ManagedScan) async -> [ManagedVerdict] {
        DefinitionLines.verdicts(
            scan.items, definitionsFound: scan.items.contains { $0.latestOverall != nil }, plugin: "ruby-build")
    }

    /// `rbenv install <newest of the line>`, `RBENV_ROOT` the root.
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary, let latest = item.latestOverall else { return nil }
        return (CLIToolCommand(
            executable: binary.path, arguments: ["install", latest], pathPrefix: PyenvAdapter.pathPrefix,
            shellLine: "rbenv install \(latest)"), ["RBENV_ROOT": root.path])
    }

    public func reread(_ item: ManagedItem) async -> String? {
        await scan().items.first { $0.identity == item.identity }?.installed
    }

    // MARK: - The parts

    /// rbenv, ruby-build's definitions and version, and whether the two may
    /// run: Homebrew's rbenv with Homebrew's ruby-build and no checkout of it
    /// under the root; anything else is handed out to copy. Blocking.
    func locate() -> (binary: ManagedRoot.Binary?, definitions: [String]?, rubyBuild: String?) {
        let plugin = root + "/plugins/ruby-build"
        let pluginDefinitions = host.directories(plugin + "/share/ruby-build")
        var kegRubyBuild: (definitions: [String], version: String)?
        for prefix in homebrewRoots {
            let link = prefix + "/opt/ruby-build/share/ruby-build"
            guard let resolved = host.resolve(link), let names = host.directories(resolved) else { continue }
            let keg = ((resolved as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            guard host.contents(keg + "/INSTALL_RECEIPT.json") != nil else { continue }
            kegRubyBuild = (names, (keg as NSString).lastPathComponent)
            break
        }
        // A checkout under the root is the ruby-build rbenv runs (its plugins
        // come first on rbenv's PATH), so its definitions are the ones that count.
        let definitions = pluginDefinitions ?? kegRubyBuild?.definitions
        let rubyBuild = pluginDefinitions != nil
            ? Self.rubyBuildVersion(host.contents(plugin + "/bin/ruby-build")) : kegRubyBuild?.version

        for prefix in homebrewRoots {
            let link = prefix + "/bin/rbenv"
            guard let resolved = host.resolve(link),
                  let version = HomebrewKeg.version(
                    of: resolved, prefix: prefix, formula: "rbenv", paths: [["libexec", "rbenv"], ["bin", "rbenv"]],
                    contents: host.contents)
            else { continue }
            let trust: ManagedRoot.Trust
            if host.isQuarantined(resolved) {
                trust = .quarantined
            } else {
                trust = pluginDefinitions == nil && kegRubyBuild != nil ? .homebrewKeg : .untrusted(nil)
            }
            return (ManagedRoot.Binary(path: link, version: version, trust: trust), definitions, rubyBuild)
        }
        let own = root + "/bin/rbenv"
        guard let resolved = host.resolve(own) else { return (nil, definitions, rubyBuild) }
        let repository = PyenvAdapter.repository(of: resolved)
        let version = DefinitionLines.scriptVersion(host.contents(repository + "/libexec/rbenv---version"))
        return (ManagedRoot.Binary(path: own, version: version, trust: host.isQuarantined(resolved) ? .quarantined : .untrusted(nil)),
                definitions, rubyBuild)
    }

    /// `RUBY_BUILD_VERSION="20261023"` in a checkout's `bin/ruby-build`.
    static func rubyBuildVersion(_ data: Data?) -> String? {
        guard let data else { return nil }
        for raw in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) where raw.hasPrefix("RUBY_BUILD_VERSION=\"") {
            let value = raw.dropFirst("RUBY_BUILD_VERSION=\"".count).prefix { $0 != "\"" }
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }
}
