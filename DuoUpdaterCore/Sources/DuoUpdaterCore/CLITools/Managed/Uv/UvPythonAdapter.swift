import Foundation

/// The Pythons `uv python install` keeps (`~/.local/share/uv/python`) as
/// managed rows, one per line — CPython by minor, free-threaded apart — moved
/// by uv's own `uv python upgrade <line>` (plans/cli-managers-redesign.md
/// §4.3). uv the binary keeps its own row (`UvProvider`).
///
/// What was measured, on uv 0.13.4 in an isolated `UV_PYTHON_INSTALL_DIR`
/// (2026-10-27; the fixtures under `Tests/…/Fixtures/managed/uv-python/` are
/// its raw output):
/// - **Scan, disk only**: each patch is a real directory
///   `cpython-3.12.5-macos-aarch64-none`; uv points the minor's link
///   `cpython-3.12-macos-aarch64-none` at the newest. The link's name is the
///   line's key; free-threaded builds are their own line
///   (`cpython-3.13+freethreaded-macos-aarch64-none`).
/// - **Check**: `uv python list <line> --only-downloads --output-format json`,
///   cwd `/` (its `path`s are relative to the cwd), the environment built
///   from scratch. 30 ms; it reads uv's own frozen list of builds, so its
///   answer moves only when uv does (`.asKnownBy`), and `--offline` printed
///   the same bytes.
/// - **What `uv python upgrade <line>` does**: installs the newest patch beside
///   the old one, repoints the minor's link ("Installed Python 3.12.15 in
///   8.11s", exit 0); at the newest, "… is already on the latest supported
///   patch release", exit 0. The old patch stays.
/// - **Interrupted** (§13.3, SIGINT and SIGTERM to the process group 1.5 s
///   and 7.6 s in): exit 130 / 143 while downloading; the old patch runs, the
///   link unmoved, nothing left beside it; the next plain run completes.
///
/// `uv python upgrade` came in 0.7.14 (a preview, with a warning, until
/// 0.10.0, PY-08); below it the row is reported, never offered.
public struct UvPythonAdapter: ManagerAdapter {

    public static let id = ManagerID("uv-python")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "uv Python", signer: "Astral", logo: "cli-uv",
        tint: .rgb(red: 0xDE / 255, green: 0x5F / 255, blue: 0xE9 / 255),
        // The same binary as uv tools and uv itself, and the same `.lock`.
        lane: "uv", versionOrder: .pep440)

    public var descriptor: ManagerDescriptor { Self.descriptor }

    /// Everything the adapter reads from the Mac, injected so tests never
    /// touch the host (`UvPythonAdapterTests`).
    public struct Host: Sendable {
        /// `UvScanner`'s first install, read from disk only: no `--version`.
        public var binary: @Sendable () async -> UvInstall?
        /// `uv --version` of the binary at this path.
        public var version: @Sendable (String) async -> String?
        /// The names in a directory, nil when it cannot be listed. Blocking.
        public var directories: @Sendable (String) -> [String]?
        /// Whether a file is there. Blocking.
        public var exists: @Sendable (String) -> Bool
        /// One read-only uv command's stdout; nil when it could not run, failed,
        /// or was stopped by its deadline or a signal.
        public var run: @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String]) async -> Data?
        public var proxyEnvironment: @Sendable () -> [String: String]
        public var processes: @Sendable () -> [NpmActivity.Process]

        public init(
            binary: @escaping @Sendable () async -> UvInstall?,
            version: @escaping @Sendable (String) async -> String?,
            directories: @escaping @Sendable (String) -> [String]?,
            exists: @escaping @Sendable (String) -> Bool,
            run: @escaping @Sendable (String, [String], [String: String]) async -> Data?,
            proxyEnvironment: @escaping @Sendable () -> [String: String],
            processes: @escaping @Sendable () -> [NpmActivity.Process]
        ) {
            self.binary = binary
            self.version = version
            self.directories = directories
            self.exists = exists
            self.run = run
            self.proxyEnvironment = proxyEnvironment
            self.processes = processes
        }

        public static func live(home: URL) -> Host {
            Host(
                binary: { await UvScanner(home: home, readVersion: { _ in nil }).scan().first },
                version: { path in await UvScanner.runVersion(URL(fileURLWithPath: path).resolvingSymlinksInPath()) },
                directories: { try? FileManager.default.contentsOfDirectory(atPath: $0) },
                exists: { FileManager.default.fileExists(atPath: $0) },
                run: { executable, arguments, environment in
                    guard let outcome = try? await ChildProcess.run(
                        executable, arguments, environment: environment,
                        workingDirectory: URL(fileURLWithPath: "/"), standardInput: Data(),
                        standardOutput: .capture, standardError: .discard,
                        deadline: UvToolAdapter.checkDeadline, onCancel: .terminateChild),
                          !outcome.timedOut, !outcome.uncaughtSignal, outcome.terminationStatus == 0
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

    /// The first uv with `uv python upgrade` (PY-06/07).
    static let upgradeSince = "0.7.14"

    // MARK: - Where

    /// `uv python dir` in a home with no `UV_PYTHON_INSTALL_DIR` or XDG
    /// variables — what a GUI process and the `uv` it starts both see.
    var pythonDirectory: String { home.path + "/.local/share/uv/python" }

    // MARK: - ManagerAdapter

    /// Disk only: one item per line holding at least one patch directory, at
    /// its newest patch.
    public func scan() async -> ManagedScan {
        let host = self.host
        let root = pythonDirectory
        let descriptor = self.descriptor
        let found: (items: [ManagedItem], states: [String: String])? = await offCooperativePool {
            guard let names = host.directories(root) else { return nil }
            var lines: [String: [Patch]] = [:]
            // The minor's link (`cpython-3.12-…`) names no patch, so it is
            // never read as one.
            for name in names {
                guard let patch = Patch(directoryName: name) else { continue }
                lines[patch.line, default: []].append(patch)
            }
            var items: [ManagedItem] = []
            var states: [String: String] = [:]
            for (line, patches) in lines.sorted(by: { $0.key < $1.key }) {
                let ordered = patches.sorted { PythonVersion.compare($0.versionOrNil, $1.versionOrNil) == .orderedDescending }
                let newest = ordered[0]
                let directory = root + "/" + newest.directoryName
                // A directory uv is still writing has no interpreter yet.
                let readable = host.exists(directory + "/bin/python3")
                let older = ordered.dropFirst().map(\.version)
                var facts: [ManagedItem.Fact] = []
                if !older.isEmpty { facts.append(.alsoInstalled(older)) }
                let item = ManagedItem(
                    descriptor: descriptor, root: root, key: line, name: newest.title, installPath: directory,
                    shape: .line, installed: readable ? newest.version : nil, alsoInstalled: older,
                    effects: [.oldKept(for: nil)], facts: facts)
                items.append(item)
                states[item.identity] = ordered.map(\.version).joined(separator: ",")
            }
            return (items, states)
        }
        guard let found, !found.items.isEmpty else { return .empty }
        let install = await host.binary()
        return ManagedScan(
            roots: [ManagedRoot(manager: Self.id, path: root, binary: UvToolAdapter.binary(install))],
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

    /// One `uv python list <line> --only-downloads` per line: what uv itself
    /// knows of that line's newest build. Nothing is asked of a uv that may
    /// not run — the list is its own, there is no other source.
    public func check(_ scan: ManagedScan) async -> [ManagedVerdict] {
        guard let root = scan.roots.first else { return [] }
        guard let binary = root.binary, root.runnable else {
            return scan.items.map { ManagedVerdict(item: $0, vendorWouldUpgrade: nil) }
        }
        let environment = commandEnvironment(binary: binary.path)
        let knownBy = binary.version.map { ManagedItem.Fact.asKnownBy("uv \($0)") }
        var verdicts: [ManagedVerdict] = []
        for item in scan.items {
            guard item.installed != nil else {
                verdicts.append(ManagedVerdict(item: item, vendorWouldUpgrade: nil))
                continue
            }
            guard let output = await host.run(
                binary.path, ["python", "list", item.key, "--only-downloads", "--output-format", "json"], environment)
            else {
                verdicts.append(ManagedVerdict(
                    item: item, vendorWouldUpgrade: nil,
                    blocker: .channelUnreadable("uv python list \(item.key) did not answer")))
                continue
            }
            let newest = Self.newestDownload(output, line: item.key)
            var answered = item.with(latestOverall: newest)
            if let knownBy { answered = answered.adding(fact: knownBy) }
            verdicts.append(ManagedVerdict(item: answered, vendorWouldUpgrade: Self.wouldUpgrade(answered)))
        }
        let processes = host.processes
        let path = binary.path
        let busy = await offCooperativePool { Self.busy(binary: path, processes: processes()) }
        guard let busy else { return verdicts }
        return verdicts.map { ManagedVerdict(item: $0.item, vendorWouldUpgrade: $0.vendorWouldUpgrade, blocker: $0.blocker, busy: busy) }
    }

    /// `~/.local/bin/uv python upgrade <line>`, no flags. Nil for a uv known
    /// to be older than the command.
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary else { return nil }
        if let version = binary.version, VersionComparator.isNewer(Self.upgradeSince, than: version) { return nil }
        return (CLIToolCommand(
            executable: binary.path, arguments: ["python", "upgrade", item.key],
            pathPrefix: (binary.path as NSString).deletingLastPathComponent), [:])
    }

    /// The new patch's directory (named by uv), the minor links beside it
    /// and in `~/.local/bin`, and uv's `.temp` downloads (§13.4: stops landed
    /// between the rename into place and the links' move). Another Python
    /// installed into this directory while the run is stopped would be
    /// removed with it.
    public func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption? {
        let bin = home.path + "/.local/bin"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let links = names.sorted().map { root.path + "/" + $0 }.filter {
            (try? FileManager.default.destinationOfSymbolicLink(atPath: $0)) != nil
        }
        return ManagedInterruption(
            paths: links + [root.path + "/.temp"] + ManagedInterruption.links(in: bin, into: root.path),
            created: [ManagedSnapshot.NewEntries(directory: root.path, namePrefix: "cpython-"),
                      ManagedSnapshot.NewEntries(directory: bin, linkingInto: root.path)])
    }

    public func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String? {
        guard let binary = root.binary else { return nil }
        return Self.busy(binary: binary.path, processes: processes)
    }

    /// The line's newest patch after the upgrade.
    public func reread(_ item: ManagedItem) async -> String? {
        await scan().items.first { $0.identity == item.identity }?.installed
    }

    // MARK: - The parts

    /// One patch directory: `cpython-3.12.5-macos-aarch64-none`,
    /// `cpython-3.13.9+freethreaded-macos-aarch64-none`. Only CPython final
    /// releases make rows: a pre-release's line is not what `upgrade` moves
    /// to, and PyPy or GraalPy are not what the minor's link names.
    struct Patch {
        let directoryName: String
        let version: String
        /// The minor's link name: the line's key.
        let line: String
        /// "Python 3.12", "Python 3.13+freethreaded".
        let title: String

        var versionOrNil: PythonVersion? { PythonVersion(version) }

        init?(directoryName: String) {
            let parts = directoryName.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "cpython" else { return nil }
            let build = parts[1].split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
            let numbers = build[0].split(separator: ".", omittingEmptySubsequences: false)
            guard numbers.count == 3, numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
            else { return nil }
            let variant = build.count == 2 ? "+" + build[1] : ""
            let minor = "\(numbers[0]).\(numbers[1])"
            self.directoryName = directoryName
            self.version = String(build[0])
            self.line = "cpython-\(minor)\(variant)-\(parts[2])"
            self.title = "Python \(minor)\(variant)"
        }
    }

    /// The newest build `uv python list <line> --only-downloads` names for the
    /// line — the same implementation, variant, platform and libc — nil when
    /// none.
    static func newestDownload(_ data: Data, line: String) -> String? {
        guard let downloads = try? JSONDecoder().decode([Download].self, from: data) else { return nil }
        return downloads
            .filter { Patch(directoryName: $0.key)?.line == line }
            .map(\.version)
            .max { PythonVersion.compare(PythonVersion($0), PythonVersion($1)) == .orderedAscending }
    }

    struct Download: Decodable {
        let key: String
        let version: String
    }

    /// What `uv python upgrade` would do: move the line when uv knows a newer
    /// patch. Nothing listed is current as far as this uv knows.
    static func wouldUpgrade(_ item: ManagedItem) -> Bool? {
        guard let installed = item.installed else { return nil }
        guard let latest = item.latestOverall else { return false }
        return ManagerDescriptor.VersionOrder.pep440.isNewer(latest, than: installed)
    }

    /// Built from scratch, never inherited: uv reads `UV_*` from its environment.
    func commandEnvironment(binary: String) -> [String: String] {
        var environment = host.proxyEnvironment()
        environment["HOME"] = home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: (binary as NSString).deletingLastPathComponent)
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// A running `uv python install|upgrade|uninstall` of this binary: uv's
    /// `.lock` in the directory would make a second one wait.
    static func busy(binary: String, processes: [NpmActivity.Process]) -> String? {
        for process in processes where BunActivity.isBun(process, bun: binary) {
            let arguments = Array(process.arguments.dropFirst())
            guard let python = arguments.firstIndex(of: "python"), python + 1 < arguments.count,
                  ["install", "upgrade", "uninstall"].contains(arguments[python + 1])
            else { continue }
            return "uv python \(arguments[python + 1]) is running (pid \(process.pid))"
        }
        return nil
    }
}

extension PythonVersion {
    /// Nil last: a version that cannot be read sorts below every one that can.
    static func compare(_ a: PythonVersion?, _ b: PythonVersion?) -> ComparisonResult {
        switch (a, b) {
        case let (a?, b?): return compare(a, b)
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        }
    }
}

extension ManagedItem {
    /// This item with one more fact for the pane.
    func adding(fact: Fact) -> ManagedItem {
        ManagedItem(
            descriptor: descriptor, root: root, key: key, name: name, installPath: installPath, shape: shape,
            request: request, installed: installed, latestWithinRequest: latestWithinRequest,
            latestOverall: latestOverall, alsoInstalled: alsoInstalled, backend: backend, notes: notes,
            effects: effects, facts: facts + [fact], binaryTrust: binaryTrust)
    }
}
