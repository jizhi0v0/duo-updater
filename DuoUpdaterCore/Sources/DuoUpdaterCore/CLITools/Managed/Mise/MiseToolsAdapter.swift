import Foundation

/// The tools mise keeps (`mise use`, `[tools]` in its config) as managed rows:
/// one row per request in the config, moved by mise's own `mise upgrade`
/// (plans/cli-managers-redesign.md §4.1; closes #1605). mise the binary keeps
/// its own row (`MiseProvider`); this is what it installs.
///
/// What was measured, on mise 2026.10.7 in an isolated home (2026-10-23; the
/// fixtures under `Tests/…/Fixtures/managed/mise/` are its raw output):
/// - **Where it runs: cwd `/`.** mise reads the config of the directory it
///   runs in and every one above it. From `$HOME` it reads `~/mise.toml` too,
///   and an untrusted one (any with `[env]`, tasks or templates) fails every
///   command: "Config files in ~/mise.toml are not trusted", exit 1. Worse,
///   `mise upgrade -y` (and `install -y`) run from there *trusts it* — it
///   wrote `~/.local/state/mise/trusted-configs/<home>` — so a one-click would
///   decide that for the user. From `/` mise reads the global config alone
///   (`~/.config/mise/config.toml` and its `conf.d`; not `~/.tool-versions`),
///   which needs no trust, and `-y` trusted nothing. That is D3's fallback,
///   taken: a request in a project or in `~/mise.toml` is not a row.
/// - **The check is three read-only commands** — `mise ls --json`, `mise
///   outdated --json`, `mise outdated --bump --json` (`MiseToolsLs`,
///   `MiseToolsOutdated`) — 15 ms, 520 ms cold / 15 ms warm, 194 ms / 17 ms.
///   mise asks mise-versions.jdx.dev, and api.github.com only as a fallback
///   with its own token chain (MISE-28/29).
/// - **The update is `mise upgrade -y <tool>`**: the config byte-identical
///   (sha256 before and after), the old version kept 24 h in
///   `~/.local/state/mise/tool-purgatory.json` (≥2026.8.15, else removed at
///   once), every request of the tool moved. Never `@<version>` (it installs
///   what nothing requests) and never `--bump` (it rewrites the config):
///   that one is the pin's command to copy.
/// - **Interrupted** with SIGINT or SIGTERM during the download or the
///   extraction (four runs): exit 130 / signal 15, the old version still
///   runs, a half-written `installs/<tool>/<new>` and its download are left,
///   `mise ls` does not list the half-written one, and the next plain
///   `mise upgrade -y <tool>` completes it. Input for D15; until it is decided
///   the command runs to the end once started (§13.1).
/// - **PATH**: an npm backend found mise's own node with neither the shims
///   nor a node on `PATH`; the shims and `~/.local/bin` lead it anyway, as
///   §4.1 says, for the backends that do look (pipx → uv, MISE-76).
///
/// The binary is `MiseScanner`'s — `~/.local/bin/mise`, signed by Jeffrey
/// Dickey's Team, not quarantined — read here without running it: its
/// `--version` waits for the check (`resolve`). With no such binary the
/// installs are listed from disk and nothing is run.
public struct MiseToolsAdapter: ManagerAdapter {

    public static let id = ManagerID("mise")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "mise tools", signer: "Jeffrey Dickey", logo: "cli-mise", tint: .label,
        // `mise self-update` replaces the binary these rows' commands run.
        lane: "mise",
        // mise falls back to api.github.com with whatever token it finds, ours
        // only through the retry below (MISE-29b).
        updaterSpendsGitHubAPI: .ourTokenIfAny)

    public var descriptor: ManagerDescriptor { Self.descriptor }

    /// Everything the adapter reads from the Mac, injected so tests never touch
    /// the host (`MiseToolsAdapterTests`).
    public struct Host: Sendable {
        /// `MiseScanner`'s install, read from disk only: no `--version`.
        public var binary: @Sendable () async -> MiseInstall?
        /// `mise --version` of the binary at this path.
        public var version: @Sendable (String) async -> String?
        /// A file's bytes, nil when there is none. Blocking.
        public var contents: @Sendable (String) -> Data?
        /// The names of a directory's real subdirectories — symlinks left out —
        /// nil when it cannot be listed. Blocking.
        public var directories: @Sendable (String) -> [String]?
        /// A file's modification date. Blocking.
        public var modified: @Sendable (String) -> Date?
        /// One read-only mise command's standard output, nil unless it exited 0.
        public var run: @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String]) async -> Data?
        /// The proxy variables a GUI app lacks (`SystemProxyEnvironment`).
        public var proxyEnvironment: @Sendable () -> [String: String]
        public var processes: @Sendable () -> [NpmActivity.Process]

        public init(
            binary: @escaping @Sendable () async -> MiseInstall?,
            version: @escaping @Sendable (String) async -> String?,
            contents: @escaping @Sendable (String) -> Data?,
            directories: @escaping @Sendable (String) -> [String]?,
            modified: @escaping @Sendable (String) -> Date?,
            run: @escaping @Sendable (String, [String], [String: String]) async -> Data?,
            proxyEnvironment: @escaping @Sendable () -> [String: String],
            processes: @escaping @Sendable () -> [NpmActivity.Process]
        ) {
            self.binary = binary
            self.version = version
            self.contents = contents
            self.directories = directories
            self.modified = modified
            self.run = run
            self.proxyEnvironment = proxyEnvironment
            self.processes = processes
        }

        public static func live(home: URL) -> Host {
            Host(
                binary: { await MiseScanner(home: home, readVersion: { _ in nil }).scan() },
                version: { path in
                    let binary = await offCooperativePool { URL(fileURLWithPath: path).resolvingSymlinksInPath() }
                    return await MiseScanner.runVersion(binary)
                },
                contents: { FileManager.default.contents(atPath: $0) },
                directories: { path in
                    guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
                    // `attributesOfItem` does not follow a symlink: mise's
                    // alias links (`20 -> ./20.20.2`, `latest`) are left out.
                    return names.filter {
                        (try? FileManager.default.attributesOfItem(atPath: path + "/" + $0))?[.type] as? FileAttributeType
                            == .typeDirectory
                    }
                },
                modified: { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date },
                run: { executable, arguments, environment in
                    // Empty stdin: a prompt, should one come, gets end of file
                    // instead of a `duo` user's terminal.
                    guard let outcome = try? await ChildProcess.run(
                        executable, arguments, environment: environment,
                        workingDirectory: URL(fileURLWithPath: "/"), standardInput: Data(),
                        standardOutput: .capture, standardError: .discard,
                        deadline: MiseToolsAdapter.checkDeadline, onCancel: .terminateChild),
                          outcome.succeeded, !outcome.timedOut
                    else { return nil }
                    return outcome.standardOutput
                },
                proxyEnvironment: { SystemProxyEnvironment.applied(to: [:]) },
                processes: { NpmActivity.runningProcesses() })
        }
    }

    let home: URL
    let host: Host

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, host: .live(home: home))
    }

    public init(home: URL, host: Host) {
        self.home = home
        self.host = host
    }

    /// `CLIToolsModel.check`'s rule: a check's request answers within 15 s.
    static let checkDeadline = ChildProcess.Deadline(terminateAfter: .seconds(15), killAfter: .seconds(16))

    /// What mise's own install or upgrade runs as: a row is busy while one does.
    static let busySubcommands: Set<String> = ["install", "upgrade", "use"]

    /// The first mise that keeps tools in purgatory instead of removing the old
    /// version at once (MISE-32/33).
    static let purgatorySince = "2026.8.15"

    // MARK: - Where

    var dataDirectory: String { home.path + "/.local/share/mise" }
    var installs: String { dataDirectory + "/installs" }
    /// The shims and the installer's bin lead the child's `PATH`, for a backend
    /// that looks for its runtime there (MISE-76).
    var pathPrefix: String { dataDirectory + "/shims:" + home.path + "/.local/bin" }
    /// `MiseScanner.location`: the one binary these commands are run with.
    var binaryPath: String { home.path + "/.local/bin/mise" }

    /// The global config, the only one read from `/` (see the type's doc).
    var configFiles: [String] {
        let config = home.path + "/.config/mise"
        return [config + "/config.toml", config + "/config.local.toml", config + "/conf.d", home.path + "/.config/mise.toml"]
    }

    // MARK: - ManagerAdapter

    /// Disk only: one item per tool directory under `installs/`, named by its
    /// `.mise.backend.toml` (`short`, `full`), at its newest real version
    /// directory. These name what is there, not the rows: a row is a request,
    /// and only mise reads its config (`check`). The state carries the backend,
    /// the version set and the global config's dates, so a `mise use` or an
    /// install in a terminal makes the next open re-check.
    public func scan() async -> ManagedScan {
        let host = self.host
        let installs = self.installs
        let root = dataDirectory
        let configFiles = self.configFiles
        let descriptor = self.descriptor
        let found: (items: [ManagedItem], states: [String: String])? = await offCooperativePool {
            guard let slugs = host.directories(installs) else { return nil }
            let stamp = configFiles.map { host.modified($0).map { String(Int($0.timeIntervalSince1970)) } ?? "-" }
                .joined(separator: ",")
            var items: [ManagedItem] = []
            var states: [String: String] = [:]
            for slug in slugs.sorted() where !slug.hasPrefix(".") {
                let directory = installs + "/" + slug
                let backend = Self.backend(host.contents(directory + "/.mise.backend.toml"))
                let name = backend?.short ?? slug
                guard !name.contains(ManagerID.identitySeparator) else { continue }
                let versions = (host.directories(directory) ?? []).filter { !$0.hasPrefix(".") }
                    .sorted { VersionComparator.compare($0, $1) == .orderedAscending }
                let item = ManagedItem(
                    descriptor: descriptor, root: root, key: name, name: name, installPath: directory,
                    shape: .request, installed: versions.last, backend: backend?.full)
                items.append(item)
                states[item.identity] = [backend?.full ?? "-", versions.joined(separator: ","), stamp].joined(separator: "|")
            }
            return (items, states)
        }
        guard let found else { return .empty }
        let install = await host.binary()
        let rootFound = ManagedRoot(manager: Self.id, path: root, binary: Self.binary(install))
        return ManagedScan(roots: [rootFound], items: found.items, states: found.states)
    }

    /// The binary's version, read by running it once — what `scan` may not do.
    public func resolve(_ scan: ManagedScan) async -> ManagedScan {
        guard let root = scan.roots.first, let binary = root.binary, root.runnable, binary.version == nil else {
            return scan
        }
        let version = await host.version(binary.path)
        let resolved = ManagedRoot(
            manager: root.manager, path: root.path,
            binary: ManagedRoot.Binary(path: binary.path, version: version, trust: binary.trust))
        return ManagedScan(roots: [resolved] + scan.roots.dropFirst(), items: scan.items, states: scan.states)
    }

    public func check(_ scan: ManagedScan) async -> [ManagedVerdict] {
        guard let root = scan.roots.first else { return [] }
        guard let binary = root.binary, root.runnable else {
            // Listed from disk; the root's trust says why nothing was asked
            // (`ManagedCheck`, a check that needs the binary).
            return scan.items.map { ManagedVerdict(item: $0, vendorWouldUpgrade: nil) }
        }
        let environment = commandEnvironment()
        guard let lsData = await host.run(binary.path, ["ls", "--json"], environment),
              let ls = MiseToolsLs.parse(lsData)
        else {
            return scan.items.map {
                ManagedVerdict(item: $0, vendorWouldUpgrade: nil, blocker: .channelUnreadable("mise ls --json did not answer"))
            }
        }
        let outdated = await host.run(binary.path, ["outdated", "--json"], environment).flatMap(MiseToolsOutdated.parse)
        let bump = await host.run(binary.path, ["outdated", "--bump", "--json"], environment).flatMap(MiseToolsOutdated.parse)
        let reading = MiseToolsOutdated.Reading(ls: ls, outdated: outdated, bump: bump)

        let reader = self.host
        let descriptor = self.descriptor
        let effects = Self.effects(binaryVersion: binary.version)
        let path = binary.path
        return await offCooperativePool {
            let busy = ManagedActivity.running(binary: path, subcommands: Self.busySubcommands, processes: reader.processes())
            return MiseToolsOutdated.verdicts(reading) { tool, entry, decided in
                Self.item(
                    tool: tool, entry: entry, decided: decided, root: root.path, descriptor: descriptor,
                    effects: effects, contents: reader.contents)
            }.map { ManagedVerdict(item: $0.item, vendorWouldUpgrade: $0.vendorWouldUpgrade, blocker: $0.blocker, busy: busy) }
        }
    }

    /// `~/.local/bin/mise upgrade -y <tool>`. `-y` because nothing answers its
    /// prompts; run from `/`, where it trusts nothing (see the type's doc).
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary else { return nil }
        return (CLIToolCommand(executable: binary.path, arguments: ["upgrade", "-y", item.name], pathPrefix: pathPrefix), [:])
    }

    /// `mise upgrade --bump <tool>`: rewrites the request in the config to
    /// follow the newest (MISE-34). Copied, never run.
    public func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand? {
        guard let binary = root.binary else { return nil }
        return CLIToolCommand(executable: binary.path, arguments: ["upgrade", "--bump", item.name], pathPrefix: nil)
    }

    public func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String? {
        guard let binary = root.binary else { return nil }
        return ManagedActivity.running(binary: binary.path, subcommands: Self.busySubcommands, processes: processes)
    }

    /// The row as `mise ls` has it now: its request still in the config, at the
    /// version that was checked or another. Nil when the request is gone, or
    /// mise did not answer — a Cancel during it among them (`.terminateChild`:
    /// nothing has been committed yet).
    public func current(_ checked: ManagedItem, in scan: ManagedScan) async -> ManagedItem? {
        guard let root = scan.root(of: checked), root.runnable, let binary = root.binary,
              let entry = await row(of: checked, binary: binary.path)
        else { return nil }
        return ManagedItem(
            descriptor: checked.descriptor, root: checked.root, key: checked.key, name: checked.name,
            installPath: entry.installPath, shape: checked.shape, request: checked.request, installed: entry.version,
            latestWithinRequest: checked.latestWithinRequest, latestOverall: checked.latestOverall,
            alsoInstalled: checked.alsoInstalled, backend: checked.backend, notes: checked.notes,
            effects: checked.effects, facts: checked.facts)
    }

    /// The version `mise ls` lists for the row's request after the upgrade.
    public func reread(_ item: ManagedItem) async -> String? {
        await row(of: item, binary: binaryPath)?.version
    }

    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog {
        guard case .gitHubReleases(let owner, let repo, let tagPrefix) = item.notes else { return Changelog(entries: []) }
        let source = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=30")!
        let pattern = tagPrefix.isEmpty ? nil : "^" + NSRegularExpression.escapedPattern(for: tagPrefix) + "v?(\\d.*)$"
        return try await DenoChangelog.gitHubReleases(source, force: force, session: .updates) { data in
            StructuredChangelogDecoder.decode(
                String(decoding: data, as: UTF8.self), format: .gitHubReleases, channel: nil, maxEntries: nil,
                tagPattern: pattern)
        }
    }

    /// `MiseUpdater`'s handoff (2026.10.5's words when mise found no token of
    /// its own and GitHub answered 403). Not seen on a backend install yet
    /// (§12 item 2): the second run happens only after mise printed it.
    public var tokenRetry: ManagedTokenRetry? {
        ManagedTokenRetry(variable: "MISE_GITHUB_TOKEN", marker: "No GitHub token was found")
    }

    // MARK: - The parts

    /// Built from scratch, never inherited: mise reads `MISE_*` from its
    /// environment, and a terminal-run `duo` would hand the user's shell's on.
    func commandEnvironment() -> [String: String] {
        var environment = host.proxyEnvironment()
        environment["HOME"] = home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: pathPrefix)
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// `checked`'s request as `mise ls` lists it now.
    func row(of checked: ManagedItem, binary: String) async -> MiseToolsLs.Entry? {
        guard let data = await host.run(binary, ["ls", "--json"], commandEnvironment()),
              let ls = MiseToolsLs.parse(data),
              let tool = ls.tools.first(where: { $0.name == checked.name })
        else { return nil }
        return tool.entries.first { entry in
            entry.isRow && entry.requestedVersion.map { Self.key(tool: tool.name, requested: $0) } == checked.key
        }
    }

    /// "node@20", "npm:prettier@2.0.0": one per request, holding no `|`.
    static func key(tool: String, requested: String) -> String {
        "\(tool)@\(requested)".replacingOccurrences(of: String(ManagerID.identitySeparator), with: "/")
    }

    static func item(
        tool: String, entry: MiseToolsLs.Entry, decided: MiseToolsOutdated.Decided, root: String,
        descriptor: ManagerDescriptor, effects: [ManagedItem.Effect], contents: (String) -> Data?
    ) -> ManagedItem {
        let toolDirectory = (entry.installPath as NSString).deletingLastPathComponent
        let backend = Self.backend(contents(toolDirectory + "/.mise.backend.toml"))?.full
        let newest = decided.latestOverall ?? decided.latestWithinRequest
        return ManagedItem(
            descriptor: descriptor, root: root, key: key(tool: tool, requested: entry.requestedVersion ?? ""),
            name: tool, installPath: entry.installPath, shape: .request, request: decided.request,
            installed: entry.version, latestWithinRequest: decided.latestWithinRequest,
            latestOverall: decided.latestOverall, alsoInstalled: decided.alsoInstalled, backend: backend,
            notes: notes(releaseURL: decided.releaseURL, newest: newest, backend: backend, tool: tool,
                         installPath: entry.installPath, contents: contents),
            effects: effects,
            facts: (entry.source.map { [ManagedItem.Fact.source($0)] } ?? []) + decided.notes.map(ManagedItem.Fact.note))
    }

    /// What `mise upgrade` does besides moving the version: keeps the old one
    /// 24 h from 2026.8.15, removes it at once before. Nothing said when the
    /// version could not be read.
    static func effects(binaryVersion: String?) -> [ManagedItem.Effect] {
        guard let version = binaryVersion else { return [] }
        return VersionComparator.compare(version, purgatorySince) == .orderedAscending ? [.oldRemoved] : [.oldKept(for: "24h")]
    }

    static func binary(_ install: MiseInstall?) -> ManagedRoot.Binary? {
        guard let install, install.problem == nil else { return nil }
        let trust: ManagedRoot.Trust
        if install.quarantined {
            trust = .quarantined
        } else if install.signature == .vendor {
            trust = .vendorSigned(team: MiseScanner.teamIdentifier)
        } else {
            trust = .untrusted(install.signature)
        }
        return ManagedRoot.Binary(path: install.path, version: install.version, trust: trust)
    }

    /// `short = "jq"`, `full = "aqua:jqlang/jq"` from a tool's
    /// `.mise.backend.toml` (three `key = "value"` lines, MISE-05).
    static func backend(_ data: Data?) -> (short: String, full: String?)? {
        guard let data else { return nil }
        var values: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = String(value.dropFirst().dropLast())
        }
        guard let short = values["short"], !short.isEmpty else { return nil }
        return (short, values["full"])
    }

    /// Where a row's notes are (MISE-46 corrected, MISE-49): the GitHub release
    /// mise names, else a `github:`/`aqua:`/`ubi:` backend's repository, else an
    /// `npm:` package's own `repository`. Nothing for `core:node` (its notes
    /// are Node's `CHANGELOG_V<major>.md`, whose parser is P3's), `pipx:`
    /// (PyPI's project URLs, P2's), `cargo:`, `go:` or `asdf:` — an asdf id
    /// names the plugin's repository, not the tool's.
    static func notes(
        releaseURL: String?, newest: String?, backend: String?, tool: String, installPath: String,
        contents: (String) -> Data?
    ) -> ManagedItem.NotesSource? {
        if let releaseURL, let source = gitHubRelease(releaseURL, version: newest) { return source }
        guard let backend else { return nil }
        for prefix in ["github:", "aqua:", "ubi:"] where backend.hasPrefix(prefix) {
            // `github:o/r[exe=x]`, `ubi:o/r@1.2`: the options are not the repository.
            let id = backend.dropFirst(prefix.count).prefix { $0 != "[" && $0 != "@" }
            guard let repository = NpmChangelog.gitHubRepository(String(id)) else { return nil }
            return .gitHubReleases(owner: repository.owner, repo: repository.name, tagPrefix: "")
        }
        if backend.hasPrefix("npm:") {
            let package = String(backend.dropFirst("npm:".count))
            // `node_modules/` (the layout of 2026.10.7) or `lib/node_modules/` (npm's own).
            var manifest: Data?
            for layout in ["/node_modules/", "/lib/node_modules/"] where manifest == nil {
                manifest = contents(installPath + layout + package + "/package.json")
            }
            guard let manifest, let json = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any] else { return nil }
            let raw = json["repository"] as? String ?? (json["repository"] as? [String: Any])?["url"] as? String
            guard let repository = NpmChangelog.gitHubRepository(raw) else { return nil }
            return .gitHubReleases(owner: repository.owner, repo: repository.name, tagPrefix: "")
        }
        return nil
    }

    /// `https://github.com/jqlang/jq/releases/tag/jq-1.8.2` for 1.8.2 →
    /// jqlang/jq, tags prefixed "jq-". A tag that is the version, with or
    /// without a `v`, has no prefix.
    static func gitHubRelease(_ url: String, version: String?) -> ManagedItem.NotesSource? {
        guard let components = URLComponents(string: url), components.host == "github.com" else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[2] == "releases", parts[3] == "tag",
              let repository = NpmChangelog.gitHubRepository(parts[0] + "/" + parts[1])
        else { return nil }
        let tag = parts[4...].joined(separator: "/")
        var prefix = ""
        if let version, tag.hasSuffix(version), tag != version, tag != "v" + version {
            prefix = String(tag.dropLast(version.count))
            if prefix.hasSuffix("v") { prefix.removeLast() }
        }
        return .gitHubReleases(owner: repository.owner, repo: repository.name, tagPrefix: prefix)
    }
}
