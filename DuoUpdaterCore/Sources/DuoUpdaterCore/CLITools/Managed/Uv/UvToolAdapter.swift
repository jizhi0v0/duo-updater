import Foundation

/// The tools `uv tool install` keeps (`~/.local/share/uv/tools/<name>`) as
/// managed rows, one per tool, moved by uv's own `uv tool upgrade <name>`
/// (plans/cli-managers-redesign.md §4.2). uv the binary keeps its own row
/// (`UvProvider`); this is what it installs.
///
/// What was measured, on uv 0.13.4 in an isolated home (2026-10-27; the
/// fixtures under `Tests/…/Fixtures/managed/uv-tool/` are its raw output):
/// - **Scan, disk only**: each tool directory's `uv-receipt.toml`
///   (`UvToolReceipt`) for the request, the venv's dist-info for the installed
///   version, `pyvenv.cfg`'s `version_info` for its Python.
/// - **Check**: `uv tool list --outdated` (uv ≥0.11.0; `UvToolOutdated`),
///   cwd `/`, the environment built from scratch — `UV_*` from a terminal-run
///   `duo` would change what it reads. It asks PyPI's simple index, never
///   api.github.com. Offline it exits 2 with nothing on stdout, so its rows
///   read "channel unreadable", never current. Below 0.11.0 — 0.10.x's
///   `--outdated` asked for no Python, index or `exclude-newer` of the tool's
///   (`outdatedSince`) — and whenever this uv may not be run, each tool is
///   asked of PyPI's JSON instead (`PyPIProject`), for its venv's Python.
/// - **What `uv tool upgrade` does, by request** (§12 item 14): no specifier
///   → moves to the newest ("Updated cowsay v5.0 -> v6.1", on stderr, exit 0);
///   `==0.6.0` → "Nothing to upgrade" plus a hint to run `uv tool install
///   ruff@latest`, exit 0; `>=23,<24` at its top → "Nothing to upgrade", exit
///   0. A range below its top would move inside it, which nothing here can
///   tell until a PEP 440 range matcher exists (D9), so a ranged tool is
///   reported, never offered. Any flag passed persists into the receipt
///   (UV-17), so none is. The venv is synced in place and the old version is
///   gone.
///
/// The binary is `UvScanner`'s: `~/.local/bin/uv` signed by Astral's Team (or
/// an unsigned one its published hash matched), not quarantined. Its
/// `--version` waits for the check (`resolve`).
public struct UvToolAdapter: ManagerAdapter {

    public static let id = ManagerID("uv-tool")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "uv tools", signer: "Astral", logo: "cli-uv",
        tint: .rgb(red: 0xDE / 255, green: 0x5F / 255, blue: 0xE9 / 255),
        // `uv self update` replaces the binary these rows' commands run, and
        // uv's own `.lock` serialises list, install and upgrade (UV-19).
        lane: "uv", versionOrder: .pep440)

    public var descriptor: ManagerDescriptor { Self.descriptor }

    /// Everything the adapter reads from the Mac, injected so tests never
    /// touch the host (`UvToolAdapterTests`).
    public struct Host: Sendable {
        /// `UvScanner`'s first install, read from disk only: no `--version`.
        public var binary: @Sendable () async -> UvInstall?
        /// `uv --version` of the binary at this path.
        public var version: @Sendable (String) async -> String?
        /// A file's bytes, nil when there is none. Blocking.
        public var contents: @Sendable (String) -> Data?
        /// The names in a directory, nil when it cannot be listed. Blocking.
        public var directories: @Sendable (String) -> [String]?
        /// A file's modification date. Blocking.
        public var modified: @Sendable (String) -> Date?
        /// One read-only uv command's output; nil when it could not run, was
        /// stopped by its deadline or a signal.
        public var run: @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String]) async -> Output?
        /// PyPI's JSON document for a project; throws when it did not answer.
        public var pypi: @Sendable (String) async throws -> Data
        public var proxyEnvironment: @Sendable () -> [String: String]
        public var processes: @Sendable () -> [NpmActivity.Process]

        public init(
            binary: @escaping @Sendable () async -> UvInstall?,
            version: @escaping @Sendable (String) async -> String?,
            contents: @escaping @Sendable (String) -> Data?,
            directories: @escaping @Sendable (String) -> [String]?,
            modified: @escaping @Sendable (String) -> Date?,
            run: @escaping @Sendable (String, [String], [String: String]) async -> Output?,
            pypi: @escaping @Sendable (String) async throws -> Data,
            proxyEnvironment: @escaping @Sendable () -> [String: String],
            processes: @escaping @Sendable () -> [NpmActivity.Process]
        ) {
            self.binary = binary
            self.version = version
            self.contents = contents
            self.directories = directories
            self.modified = modified
            self.run = run
            self.pypi = pypi
            self.proxyEnvironment = proxyEnvironment
            self.processes = processes
        }

        public static func live(home: URL) -> Host {
            Host(
                binary: { await UvScanner(home: home, readVersion: { _ in nil }).scan().first },
                version: { path in await UvScanner.runVersion(URL(fileURLWithPath: path).resolvingSymlinksInPath()) },
                contents: { FileManager.default.contents(atPath: $0) },
                directories: { try? FileManager.default.contentsOfDirectory(atPath: $0) },
                modified: { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date },
                run: { executable, arguments, environment in
                    guard let outcome = try? await ChildProcess.run(
                        executable, arguments, environment: environment,
                        workingDirectory: URL(fileURLWithPath: "/"), standardInput: Data(),
                        standardOutput: .capture, standardError: .capture,
                        deadline: UvToolAdapter.checkDeadline, onCancel: .terminateChild),
                          !outcome.timedOut, !outcome.uncaughtSignal
                    else { return nil }
                    return Output(stdout: outcome.standardOutput, stderr: outcome.standardError, exitStatus: outcome.terminationStatus)
                },
                pypi: { try await PyPIProject.fetch($0) },
                proxyEnvironment: { SystemProxyEnvironment.applied(to: [:]) },
                processes: { NpmActivity.runningProcesses() })
        }
    }

    public struct Output: Sendable {
        public var stdout: Data
        /// Where uv says why it left a tool out (`list.rs`: a missing
        /// environment, an unreadable receipt), exit 0 all the same.
        public var stderr: Data
        public var exitStatus: Int32

        public init(stdout: Data, stderr: Data = Data(), exitStatus: Int32 = 0) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitStatus = exitStatus
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
    /// Offline, uv gave up after its three retries in 6.7 s.
    static let checkDeadline = ChildProcess.Deadline(terminateAfter: .seconds(15), killAfter: .seconds(16))

    /// The first uv whose `uv tool list --outdated` asks for the tool's own
    /// Python and options: 0.10.10 added the flag, but up to 0.10.12 it built
    /// its client with `requires_python: None`, no index locations and no
    /// `exclude-newer` (`crates/uv/src/commands/tool/list.rs` at 0.10.12 and
    /// 0.11.0, read 2026-10-27) — black on Python 3.9 would read 26.10.1,
    /// which `uv tool upgrade` cannot install there.
    static let outdatedSince = "0.11.0"
    /// At most this many PyPI documents at once, as pipx asks (PX-12).
    static let parallelFetches = 8

    // MARK: - Where

    /// `uv tool dir` in a home with no `UV_TOOL_DIR` or XDG variables — what a
    /// GUI process and the `uv` it starts both see.
    var toolsDirectory: String { home.path + "/.local/share/uv/tools" }

    // MARK: - ManagerAdapter

    /// Disk only: one item per tool directory holding a receipt, at the
    /// version its venv's dist-info names.
    public func scan() async -> ManagedScan {
        let host = self.host
        let root = toolsDirectory
        let descriptor = self.descriptor
        let found: (items: [ManagedItem], states: [String: String])? = await offCooperativePool {
            guard let names = host.directories(root) else { return nil }
            var items: [ManagedItem] = []
            var states: [String: String] = [:]
            for name in names.sorted() where !name.hasPrefix(".") && !name.contains(ManagerID.identitySeparator) {
                let directory = root + "/" + name
                let receiptPath = directory + "/uv-receipt.toml"
                guard let receiptData = host.contents(receiptPath) else { continue }
                let receipt = UvToolReceipt.parse(receiptData, tool: name)
                let package = receipt?.requirement.name ?? name
                let distribution = PythonDistribution.read(
                    package, venv: directory, contents: host.contents, directories: host.directories)
                let python = Self.venvPython(host.contents(directory + "/pyvenv.cfg"))
                var facts: [ManagedItem.Fact] = []
                if let python { facts.append(.python(python)) }
                if let excludeNewer = receipt?.excludeNewer { facts.append(.note("exclude-newer \(excludeNewer)")) }
                if let source = receipt?.source ?? distribution?.directSource { facts.append(.note("installed from \(source)")) }
                let item = ManagedItem(
                    descriptor: descriptor, root: root, key: name, name: name, installPath: directory,
                    shape: .package, request: receipt?.request, installed: distribution?.version,
                    notes: distribution.flatMap { Self.notes($0.projectURLs, project: package) },
                    effects: [.oldRemoved], facts: facts)
                items.append(item)
                let stamp = host.modified(receiptPath).map { String(Int($0.timeIntervalSince1970)) } ?? "-"
                states[item.identity] = [receipt?.requirement.specifier ?? "-", distribution?.version ?? "-", stamp]
                    .joined(separator: "|")
            }
            return (items, states)
        }
        guard let found, !found.items.isEmpty else { return .empty }
        let install = await host.binary()
        return ManagedScan(
            roots: [ManagedRoot(manager: Self.id, path: root, binary: Self.binary(install))],
            items: found.items, states: found.states)
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
        var latest: [String: Answer] = [:]
        if let binary = root.binary, root.runnable, let version = binary.version,
           !VersionComparator.isNewer(Self.outdatedSince, than: version) {
            guard let output = await host.run(binary.path, ["tool", "list", "--outdated"], commandEnvironment(binary: binary.path)),
                  output.exitStatus == 0
            else {
                return scan.items.map {
                    ManagedVerdict(item: $0, vendorWouldUpgrade: nil,
                                   blocker: .channelUnreadable("uv tool list --outdated did not answer"))
                }
            }
            let outdated = UvToolOutdated.parse(output.stdout)
            let warnings = String(decoding: output.stderr, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
            let offline = Self.configuredOffline(host.contents(home.path + "/.config/uv/uv.toml"))
            for item in scan.items {
                guard let installed = item.installed else { continue }
                if let entry = outdated[PythonDistribution.normalize(item.name)] {
                    latest[item.identity] = .latest(entry.latest)
                    continue
                }
                // Left out is current only when uv had no other reason to
                // leave it out (`list.rs`, `latest.rs` at 0.13.4): no warning
                // naming it, not a pre-release (never a "latest" there), and
                // not told to stay offline, where an empty list is all it says.
                if let warning = warnings.first(where: { $0.contains("`\(item.name)`") }) {
                    latest[item.identity] = .blocked(.channelUnreadable(warning))
                } else if PythonVersion(installed)?.isPrerelease == true {
                    latest[item.identity] = .blocked(.notRequested("uv tool list --outdated does not look at pre-releases"))
                } else if offline {
                    latest[item.identity] = .blocked(.channelUnreadable("uv is set to offline in ~/.config/uv/uv.toml"))
                } else {
                    latest[item.identity] = .latest(installed)
                }
            }
        } else {
            latest = await pypiLatest(scan.items)
        }

        // From a path, a URL, git or an editable checkout: no index names its
        // releases, and `uv tool upgrade` rebuilds it from where it came
        // ("Nothing to upgrade") whatever `--outdated` printed.
        for item in scan.items {
            if let reason = Self.notIndexed(item) { latest[item.identity] = .blocked(.notIndexed(reason)) }
        }
        let processes = host.processes
        let binaryPath = root.binary?.path
        let answers = latest
        return await offCooperativePool {
            let busy = binaryPath.flatMap { Self.busy(binary: $0, processes: processes()) }
            return scan.items.map { item in
                switch answers[item.identity] {
                case .blocked(let blocker)?:
                    return ManagedVerdict(item: item, vendorWouldUpgrade: nil, blocker: blocker, busy: busy)
                case .latest(let newest)?:
                    let answered = item.with(latestOverall: newest)
                    return ManagedVerdict(item: answered, vendorWouldUpgrade: Self.wouldUpgrade(answered), busy: busy)
                case nil:
                    return ManagedVerdict(item: item, vendorWouldUpgrade: nil, busy: busy)
                }
            }
        }
    }

    /// `~/.local/bin/uv tool upgrade <name>`, no flags (they persist into the
    /// receipt, UV-17).
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary else { return nil }
        return (CLIToolCommand(
            executable: binary.path, arguments: ["tool", "upgrade", item.name],
            pathPrefix: (binary.path as NSString).deletingLastPathComponent), [:])
    }

    /// `uv tool install <name>@latest`: what uv's own hint says lifts a `==`
    /// pin (UV-16); it rewrites the receipt to follow the newest. Copied,
    /// never run.
    public func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand? {
        guard let binary = root.binary, item.request != nil else { return nil }
        return CLIToolCommand(executable: binary.path, arguments: ["tool", "install", item.name + "@latest"], pathPrefix: nil)
    }

    /// The tool's venv whole — uv rewrites it in place (§13.4: a stop left
    /// the new `bin/ruff` beside the old dist-info's removal) — and its entry
    /// points in `~/.local/bin`, those there now and any the new version adds.
    public func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption? {
        let bin = home.path + "/.local/bin"
        return ManagedInterruption(
            paths: [item.installPath] + ManagedInterruption.links(in: bin, into: item.installPath),
            created: [ManagedSnapshot.NewEntries(directory: bin, linkingInto: item.installPath)])
    }

    public func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String? {
        guard let binary = root.binary else { return nil }
        return Self.busy(binary: binary.path, processes: processes)
    }

    /// The version the tool's venv holds after the upgrade.
    public func reread(_ item: ManagedItem) async -> String? {
        let host = self.host
        let package = item.name
        let venv = item.installPath
        return await offCooperativePool {
            PythonDistribution.read(package, venv: venv, contents: host.contents, directories: host.directories)?.version
        }
    }

    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog {
        try await ManagedNotes.fetch(item.notes, force: force)
    }

    // MARK: - The parts

    /// What the check learned of one tool: the newest release, or why none.
    enum Answer: Sendable {
        case latest(String)
        case blocked(ManagedVerdict.Blocker)
    }

    /// What `uv tool upgrade` would do (§3.2's `vendorWouldUpgrade`): an
    /// unpinned tool moves when a newer one is out; a `==` pin never does; a
    /// range might, and nothing here can tell yet (D9).
    static func wouldUpgrade(_ item: ManagedItem) -> Bool? {
        switch item.request?.kind {
        case nil, .alias?:
            guard let installed = item.installed, let latest = item.latestOverall else { return nil }
            if let a = PythonVersion(latest), let b = PythonVersion(installed) { return a > b }
            return VersionComparator.isNewer(latest, than: installed)
        case .exact?:
            return false
        case .range?:
            guard let installed = item.installed, let latest = item.latestOverall else { return nil }
            // At the newest overall it is at the range's top too: nothing to move.
            return installed == latest ? false : nil
        }
    }

    /// Each tool's newest release its venv's Python can install, from PyPI,
    /// at most `parallelFetches` at once.
    func pypiLatest(_ items: [ManagedItem]) async -> [String: Answer] {
        let fetch = host.pypi
        let wanted = items.filter { $0.installed != nil }
        return await withTaskGroup(of: (String, Answer).self) { group in
            var results: [String: Answer] = [:]
            var pending = wanted[...]
            func start(_ item: ManagedItem) {
                let python = item.facts.lazy.compactMap { fact -> String? in
                    if case .python(let version) = fact { return version } else { return nil }
                }.first
                let cutoff = item.facts.lazy.compactMap { fact -> Date? in
                    guard case .note(let text) = fact, text.hasPrefix("exclude-newer ") else { return nil }
                    return UvToolReceipt.date(excludeNewer: String(text.dropFirst("exclude-newer ".count)))
                }.first
                group.addTask {
                    do {
                        let data = try await fetch(item.name)
                        guard let document = PyPIProject.parse(data) else {
                            return (item.identity, .blocked(.channelUnreadable("PyPI's answer for \(item.name) could not be read")))
                        }
                        guard let newest = PyPIProject.newest(in: document, python: python, uploadedBefore: cutoff) else {
                            return (item.identity, .blocked(.channelUnreadable("PyPI lists no release of \(item.name) for this Python")))
                        }
                        return (item.identity, .latest(newest))
                    } catch {
                        return (item.identity, .blocked(.channelUnreadable("PyPI did not answer for \(item.name): \(error)")))
                    }
                }
            }
            for _ in 0..<Self.parallelFetches { if let next = pending.popFirst() { start(next) } }
            while let (identity, result) = await group.next() {
                results[identity] = result
                if let next = pending.popFirst() { start(next) }
            }
            return results
        }
    }

    /// Why a tool's releases cannot be read from an index, from its scan.
    static func notIndexed(_ item: ManagedItem) -> String? {
        for case .note(let text) in item.facts where text.hasPrefix("installed from ") {
            return "\(item.name) was \(text)"
        }
        return nil
    }

    /// `offline = true` at the top of uv's user config.
    static func configuredOffline(_ data: Data?) -> Bool {
        guard let data else { return false }
        for raw in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return false }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "offline" { return parts[1].hasPrefix("true") }
        }
        return false
    }

    /// Built from scratch, never inherited: uv reads `UV_*` from its environment.
    func commandEnvironment(binary: String) -> [String: String] {
        var environment = host.proxyEnvironment()
        environment["HOME"] = home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: (binary as NSString).deletingLastPathComponent)
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// A running `uv tool install|upgrade|uninstall` of this binary. uv's own
    /// `.lock` would make a second one wait (UV-19); the row says why it
    /// waits instead.
    static func busy(binary: String, processes: [NpmActivity.Process]) -> String? {
        for process in processes where BunActivity.isBun(process, bun: binary) {
            let arguments = Array(process.arguments.dropFirst())
            guard let tool = arguments.firstIndex(of: "tool"), tool + 1 < arguments.count,
                  ["install", "upgrade", "uninstall"].contains(arguments[tool + 1])
            else { continue }
            return "uv tool \(arguments[tool + 1]) is running (pid \(process.pid))"
        }
        return nil
    }

    /// `version_info = 3.9.6` (uv) or `version = 3.12.1` (the venv module) in
    /// `pyvenv.cfg`.
    static func venvPython(_ data: Data?) -> String? {
        guard let data else { return nil }
        var fallback: String?
        for raw in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let parts = raw.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "version_info" { return parts[1] }
            if parts[0] == "version" { fallback = parts[1] }
        }
        return fallback
    }

    static func binary(_ install: UvInstall?) -> ManagedRoot.Binary? {
        guard let install, install.problem == nil, install.executable != nil else { return nil }
        let trust: ManagedRoot.Trust
        if install.quarantined {
            trust = .quarantined
        } else if install.isVendorSigned {
            trust = .vendorSigned(team: UvScanner.teamIdentifier)
        } else if install.hashVerdict == .matches {
            trust = .verifiedHash
        } else {
            trust = .untrusted(install.signature)
        }
        return ManagedRoot.Binary(path: install.path, version: install.version, trust: trust)
    }

    /// A Python project's notes: its GitHub repository's releases, when the
    /// metadata names one (`ProjectURLRepo`).
    static func notes(_ urls: [(label: String, url: String)], project: String) -> ManagedItem.NotesSource? {
        ProjectURLRepo.repository(urls, project: project)
            .map { .gitHubReleases(owner: $0.owner, repo: $0.repo, tagPrefix: "") }
    }
}

extension ManagedItem {
    /// This item with the newest release the check found.
    func with(latestOverall: String?) -> ManagedItem {
        ManagedItem(
            descriptor: descriptor, root: root, key: key, name: name, installPath: installPath, shape: shape,
            request: request, installed: installed, latestWithinRequest: latestWithinRequest,
            latestOverall: latestOverall, alsoInstalled: alsoInstalled, backend: backend, notes: notes,
            effects: effects, facts: facts, binaryTrust: binaryTrust)
    }
}
