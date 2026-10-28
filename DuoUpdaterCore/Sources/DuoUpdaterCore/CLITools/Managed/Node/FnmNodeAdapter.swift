import Foundation

/// The Node versions fnm keeps (`<fnm dir>/node-versions/v<x.y.z>/installation`)
/// as managed rows, one per major (D1), moved by `fnm --fnm-dir <root> install
/// <major>` (design §4.6).
///
/// What was measured, with Homebrew's fnm 1.39.0 and `--fnm-dir` an isolated
/// root (2026-10-27):
/// - **Scan, disk only**: the three roots fnm has used (`NodePrefixes`'s
///   list); `aliases/default` is an absolute link to a version's
///   `installation`.
/// - **Check**: nodejs.org's `index.json` (`NodeDistIndex`), fnm's own source.
/// - **The command** (`env -i HOME PATH=/usr/bin:/bin fnm --fnm-dir <root>
///   install 22`): v22.23.4 beside v22.21.1 in 7 s; `default` stays on
///   22.21.1; the old version's global packages are not carried (FNM-31,
///   fnm #481). Already there: "warning: Version already installed", exit 0.
/// - **Interrupted** (§13.3): fnm downloads and extracts into
///   `node-versions/.downloads/.tmp…` and renames into place at the end; a
///   SIGINT/SIGTERM 1 s in exits 130/143 leaving that temporary directory,
///   the old version runs, the next plain run completes. Once the version's
///   directory appeared the command had already exited 0.
///
/// fnm is a Rust binary, ad hoc signed by its build (`codesign -dv`:
/// `Signature=adhoc`, no Team): Homebrew's keg is run (D5.1); the one fnm's
/// installer puts in its root is handed out to copy (D5.2).
public struct FnmNodeAdapter: ManagerAdapter {

    public static let id = ManagerID("fnm-node")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "fnm Node", signer: nil, logo: nil, tint: .label, lane: "fnm")

    public var descriptor: ManagerDescriptor { Self.descriptor }

    public typealias Host = NvmNodeAdapter.Host

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

    /// The first fnm whose `install <major>` resolves the newest of the major
    /// as asked (FNM-50/51).
    static let installSince = "1.36.0"

    /// fnm's default root by release (`directories.rs`): `$XDG_DATA_HOME/fnm`,
    /// else `~/.fnm` from older releases, else Application Support.
    var directories: [String] {
        [".local/share/fnm", ".fnm", "Library/Application Support/fnm"].map { home.path + "/" + $0 }
    }

    // MARK: - ManagerAdapter

    public func scan() async -> ManagedScan {
        let host = self.host
        let directories = self.directories
        let descriptor = self.descriptor
        return await offCooperativePool {
            var roots: [ManagedRoot] = []
            var items: [ManagedItem] = []
            var states: [String: String] = [:]
            var seen: Set<String> = []
            for directory in directories {
                guard let canonical = host.resolve(directory), seen.insert(canonical).inserted else { continue }
                let versions = directory + "/node-versions"
                guard let names = host.directories(versions) else { continue }
                let defaultPatch = Self.linkedDefault(host.resolve(directory + "/aliases/default"))
                let found = NodeLines.items(
                    names: names, versions: versions, root: directory, node: "installation/bin/node",
                    default: defaultPatch, descriptor: descriptor, extraEffects: [.packagesNotCarried],
                    exists: host.exists)
                guard !found.isEmpty else { continue }
                roots.append(ManagedRoot(manager: Self.id, path: directory, binary: binary(root: directory)))
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
            moveDefault: { "fnm default \($0)" })
    }

    /// `fnm --fnm-dir <root> install <major>`: the root spelled, so the fnm a
    /// GUI process runs acts on the row's own root whichever it would pick.
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary else { return nil }
        if let version = binary.version, VersionComparator.isNewer(Self.installSince, than: version) { return nil }
        return (CLIToolCommand(
            executable: binary.path, arguments: ["--fnm-dir", root.path, "install", String(item.key.dropFirst())],
            pathPrefix: nil), [:])
    }

    /// The new version's directory (renamed into place whole), fnm's
    /// downloads (a stop leaves `.downloads/.tmp<random>`, which no later run
    /// removes) and the aliases (§13.4).
    public func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption? {
        ManagedInterruption(
            paths: [root.path + "/node-versions/.downloads", root.path + "/aliases"],
            created: [ManagedSnapshot.NewEntries(directory: root.path + "/node-versions", namePrefix: "v")])
    }

    public func reread(_ item: ManagedItem) async -> String? {
        await scan().items.first { $0.identity == item.identity }?.installed
    }

    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog {
        try await ManagedNotes.fetch(item.notes, force: force)
    }

    // MARK: - The parts

    /// Homebrew's fnm first — the keg rule lets it run — then the one fnm's
    /// installer leaves in its root. Blocking.
    func binary(root: String) -> ManagedRoot.Binary? {
        for prefix in homebrewRoots {
            let link = prefix + "/bin/fnm"
            guard let resolved = host.resolve(link),
                  let version = HomebrewKeg.version(
                    of: resolved, prefix: prefix, formula: "fnm", paths: [["bin", "fnm"]], contents: host.contents)
            else { continue }
            return ManagedRoot.Binary(path: link, version: version, trust: host.isQuarantined(resolved) ? .quarantined : .homebrewKeg)
        }
        let own = root + "/fnm"
        guard let resolved = host.resolve(own) else { return nil }
        return ManagedRoot.Binary(path: own, version: nil, trust: host.isQuarantined(resolved) ? .quarantined : .untrusted(nil))
    }

    /// `aliases/default`'s target, `…/node-versions/v22.21.1/installation` →
    /// "22.21.1".
    static func linkedDefault(_ resolved: String?) -> String? {
        guard let resolved else { return nil }
        let components = URL(fileURLWithPath: resolved).pathComponents
        guard components.count >= 2, components.last == "installation" else { return nil }
        return NodeLines.Patch(directoryName: components[components.count - 2])?.version
    }
}
