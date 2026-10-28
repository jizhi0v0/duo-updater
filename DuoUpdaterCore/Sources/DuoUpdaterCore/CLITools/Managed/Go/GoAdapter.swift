import Foundation

/// The programs `go install` put in `GOBIN` as managed rows, one per binary,
/// moved by `go install <package>@latest` (plans/cli-managers-redesign.md
/// §4.9).
///
/// What was measured, with Homebrew's go 1.27.3 and an isolated `GOBIN`
/// (2026-10-27):
/// - **The list, disk only**: go keeps no record; each binary's build info
///   (`GoBuildInfo`) names its package (`path`) and module (`mod`) — what
///   `go version -m` prints.
/// - **The newest**: `go list -m -json <module>@latest` from `/` with
///   `GOTOOLCHAIN=local GOFLAGS=-mod=mod` and nothing else but `HOME` and the
///   system `PATH`: 0.27 s for `golang.org/x/vuln` → `"Version": "v1.9.0"`,
///   `"GoVersion": "1.26.0"`; it went through `~/Library/Application
///   Support/go/env`'s `GOPROXY=https://goproxy.cn,direct` (`-x` shows every
///   GET to goproxy.cn, §12 item 13).
/// - **The command**: `go install mvdan.cc/gofumpt@latest` with the same
///   environment and `GOBIN` the root: v0.9.1 → v0.12.0, exit 0, a new inode;
///   again: exit 0, inode and mtime unchanged.
///
/// `GOTOOLCHAIN=local`: a release whose `go.mod` asks for a newer Go than
/// this one is reported (`.runtimeTooOld`), never fetched. go is run only from
/// Homebrew's keg (D5.1; `brew install go` 1.27.3: `bin/go -> ../libexec/bin/go`,
/// ad hoc signed — the keg is the proof), else the pkg installer's
/// `/usr/local/go/bin/go` when Google signed it (§12 item 7, measured
/// 2026-10-27 on go.dev's `go1.27.3.darwin-arm64.pkg`: "Developer ID
/// Application: Google LLC (EQHXZ8M8AV)", hardened runtime, `codesign
/// --verify --strict` valid; the toolchain it runs, `pkg/tool/darwin_arm64/
/// compile`, `link`, `asm`, the same Team).
public struct GoAdapter: ManagerAdapter {

    public static let id = ManagerID("go")

    /// Google's Team, which signs go.dev's macOS installer and the `go` in it.
    public static let teamIdentifier = "EQHXZ8M8AV"

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "go install", signer: nil, logo: nil, tint: .label, lane: "go")

    public var descriptor: ManagerDescriptor { Self.descriptor }

    /// Everything the adapter reads from the Mac, injected so tests never
    /// touch the host (`GoAdapterTests`).
    public struct Host: Sendable {
        public var contents: @Sendable (String) -> Data?
        public var directories: @Sendable (String) -> [String]?
        /// The path with every link followed; nil when nothing is there.
        public var resolve: @Sendable (String) -> String?
        public var isQuarantined: @Sendable (String) -> Bool
        /// The Go build info of a regular file; nil for anything else. Blocking.
        public var buildInfo: @Sendable (String) -> GoBuildInfo?
        /// One read-only go command's stdout; nil when it could not run, failed,
        /// or was stopped by its deadline or a signal.
        public var run: @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String]) async -> Data?
        public var proxyEnvironment: @Sendable () -> [String: String]
        public var processes: @Sendable () -> [NpmActivity.Process]
        /// The file's signature against Google's Team (`CLIToolTrust.signature`). Blocking.
        public var signature: @Sendable (String) -> CLIToolTrust.Signature

        public init(
            contents: @escaping @Sendable (String) -> Data?,
            directories: @escaping @Sendable (String) -> [String]?,
            resolve: @escaping @Sendable (String) -> String?,
            isQuarantined: @escaping @Sendable (String) -> Bool,
            buildInfo: @escaping @Sendable (String) -> GoBuildInfo?,
            run: @escaping @Sendable (String, [String], [String: String]) async -> Data?,
            proxyEnvironment: @escaping @Sendable () -> [String: String],
            processes: @escaping @Sendable () -> [NpmActivity.Process],
            signature: @escaping @Sendable (String) -> CLIToolTrust.Signature = {
                CLIToolTrust.signature(of: URL(fileURLWithPath: $0), teamIdentifier: GoAdapter.teamIdentifier)
            }
        ) {
            self.contents = contents
            self.directories = directories
            self.resolve = resolve
            self.isQuarantined = isQuarantined
            self.buildInfo = buildInfo
            self.run = run
            self.proxyEnvironment = proxyEnvironment
            self.processes = processes
            self.signature = signature
        }

        public static let live = Host(
            contents: NvmNodeAdapter.Host.live.contents, directories: NvmNodeAdapter.Host.live.directories,
            resolve: NvmNodeAdapter.Host.live.resolve, isQuarantined: NvmNodeAdapter.Host.live.isQuarantined,
            buildInfo: { path in
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      attributes[.type] as? FileAttributeType == .typeRegular
                else { return nil }
                return GoBuildInfo.read(at: URL(fileURLWithPath: path))
            },
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

    /// At most this many `go list` at once.
    static let parallelLists = 4

    /// `go env -w`'s file: what a GUI process's go reads, and the only place
    /// it can learn `GOBIN` or `GOPATH` from (shell exports are unseen, GO-01).
    var envFile: String { home.path + "/Library/Application Support/go/env" }

    /// `$GOBIN`, else the first `$GOPATH` entry's `bin`, else `~/go/bin`.
    /// Blocking.
    func binDirectory() -> String {
        let values = Self.envValues(host.contents(envFile))
        if let bin = values["GOBIN"], bin.hasPrefix("/") { return bin }
        if let gopath = values["GOPATH"]?.split(separator: ":").first, gopath.hasPrefix("/") {
            return String(gopath) + "/bin"
        }
        return home.path + "/go/bin"
    }

    // MARK: - ManagerAdapter

    public func scan() async -> ManagedScan {
        let (host, descriptor) = (self.host, self.descriptor)
        return await offCooperativePool {
            let root = binDirectory()
            guard let names = host.directories(root) else { return .empty }
            var items: [ManagedItem] = []
            var states: [String: String] = [:]
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = root + "/" + name
                // A link is not what `go install` writes.
                guard host.resolve(path) == path, let info = host.buildInfo(path) else { continue }
                let item = Self.item(name: name, info: info, root: root, descriptor: descriptor)
                items.append(item)
                states[item.identity] = [item.installed ?? "-", info.goVersion].joined(separator: ",")
            }
            guard !items.isEmpty else { return .empty }
            return ManagedScan(
                roots: [ManagedRoot(manager: Self.id, path: root, binary: locate())], items: items, states: states)
        }
    }

    /// One `go list -m -json <module>@latest` per module, at most
    /// `parallelLists` at once. Nothing is asked of a go that may not run.
    public func check(_ scan: ManagedScan) async -> [ManagedVerdict] {
        guard let root = scan.roots.first else { return [] }
        var verdicts: [String: ManagedVerdict] = [:]
        var modules: [String: [ManagedItem]] = [:]
        for item in scan.items {
            if let reason = Self.notIndexed(item) {
                verdicts[item.identity] = ManagedVerdict(item: item, vendorWouldUpgrade: nil, blocker: .notIndexed(reason))
            } else if let module = item.backend {
                modules[module, default: []].append(item)
            }
        }
        if let binary = root.binary, root.runnable {
            let environment = commandEnvironment()
            let (run, local) = (host.run, binary.version)
            let answers: [(String, Data?)] = await withTaskGroup(of: (String, Data?).self) { group in
                var pending = modules.keys.sorted()[...]
                var results: [(String, Data?)] = []
                func start(_ module: String) {
                    group.addTask { (module, await run(binary.path, ["list", "-m", "-json", module + "@latest"], environment)) }
                }
                for _ in 0..<Self.parallelLists { if let next = pending.popFirst() { start(next) } }
                while let answer = await group.next() {
                    results.append(answer)
                    if let next = pending.popFirst() { start(next) }
                }
                return results
            }
            for (module, output) in answers {
                for item in modules[module] ?? [] {
                    verdicts[item.identity] = Self.verdict(item, latest: output.flatMap(Self.latest), localGo: local)
                }
            }
        } else {
            for item in modules.values.joined() { verdicts[item.identity] = ManagedVerdict(item: item, vendorWouldUpgrade: nil) }
        }
        let processes = host.processes
        let running = await offCooperativePool { processes() }
        return scan.items.compactMap { item in
            guard let verdict = verdicts[item.identity] else { return nil }
            let busy = Self.busy(package: item.key, processes: running)
            return busy == nil ? verdict
                : ManagedVerdict(item: verdict.item, vendorWouldUpgrade: verdict.vendorWouldUpgrade, blocker: verdict.blocker, busy: busy)
        }
    }

    /// `go install <package>@latest`, `GOBIN` the root, so the new build lands
    /// on the file the row is.
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary, Self.notIndexed(item) == nil else { return nil }
        var environment = Self.goEnvironment
        environment["GOBIN"] = root.path
        return (CLIToolCommand(executable: binary.path, arguments: ["install", item.key + "@latest"], pathPrefix: nil), environment)
    }

    /// The binary alone: `go install` builds under `TMPDIR` and renames the
    /// result into `GOBIN` (§13.4: a stop after the rename left the new
    /// binary, exit −2; put back, identical).
    public func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption? {
        ManagedInterruption(paths: [item.installPath])
    }

    public func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String? {
        Self.busy(package: item.key, processes: processes)
    }

    public func reread(_ item: ManagedItem) async -> String? {
        await scan().items.first { $0.identity == item.identity }?.installed
    }

    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog {
        try await ManagedNotes.fetch(item.notes, force: force)
    }

    // MARK: - The parts

    /// What every go command gets beyond `HOME` and `PATH`: no toolchain
    /// download (GO-12/14), and no `go.mod` of a directory read for flags.
    static let goEnvironment = ["GOTOOLCHAIN": "local", "GOFLAGS": "-mod=mod"]

    /// Built from scratch, never inherited: go reads `GO*` from its environment.
    func commandEnvironment() -> [String: String] {
        var environment = host.proxyEnvironment()
        environment["HOME"] = home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: nil)
        for (key, value) in Self.goEnvironment { environment[key] = value }
        return environment
    }

    /// Homebrew's keg (D5.1), then the pkg installer's `/usr/local/go`, run
    /// only when Google's signature holds. Blocking.
    func locate() -> ManagedRoot.Binary? {
        for prefix in homebrewRoots {
            let link = prefix + "/bin/go"
            guard let resolved = host.resolve(link),
                  let version = HomebrewKeg.version(
                    of: resolved, prefix: prefix, formula: "go", paths: [["libexec", "bin", "go"], ["bin", "go"]],
                    contents: host.contents)
            else { continue }
            return ManagedRoot.Binary(path: link, version: version, trust: host.isQuarantined(resolved) ? .quarantined : .homebrewKeg)
        }
        let pkg = "/usr/local/go/bin/go"
        guard host.resolve(pkg) != nil else { return nil }
        let version = host.contents("/usr/local/go/VERSION").flatMap {
            String(decoding: $0, as: UTF8.self).split(whereSeparator: \.isNewline).first
        }.map { String($0.hasPrefix("go") ? $0.dropFirst(2) : $0) }
        let trust: ManagedRoot.Trust
        if host.isQuarantined(pkg) {
            trust = .quarantined
        } else {
            let signature = host.signature(pkg)
            trust = signature == .vendor ? .vendorSigned(team: Self.teamIdentifier) : .untrusted(signature)
        }
        return ManagedRoot.Binary(path: pkg, version: version, trust: trust)
    }

    /// One binary. Its key is the package `go install` builds — unique in the
    /// directory, since `go install` names the file after it; a file renamed
    /// since (two files of one package) is keyed apart and reported, because
    /// `go install` would write the other name.
    static func item(name: String, info: GoBuildInfo, root: String, descriptor: ManagerDescriptor) -> ManagedItem {
        let package = info.packagePath
        let renamed = package.map { installedName(of: $0) != name } ?? false
        let key = package.map { renamed ? "\($0)#\(name)" : $0 } ?? "#" + name
        var facts: [ManagedItem.Fact] = [.note("built with \(info.goVersion)")]
        if let main = info.main { facts.insert(.backend(main.path), at: 0) }
        if renamed, let package { facts.append(.note("renamed: go install \(package)@latest writes \(installedName(of: package))")) }
        let version = info.main.map { $0.replacement?.version ?? $0.version }
        return ManagedItem(
            descriptor: descriptor, root: root, key: key, name: name, installPath: root + "/" + name, shape: .package,
            installed: version.map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }, backend: info.main?.path,
            notes: info.main.map { .goModule($0.path) },
            effects: [.oldRemoved], facts: facts)
    }

    /// The file name `go install` gives a package: its last element, or the
    /// one before a major version suffix (`…/cmd/foo/v2` → `foo`).
    static func installedName(of package: String) -> String {
        let parts = package.split(separator: "/").map(String.init)
        if parts.count >= 2, let last = parts.last, GoModule.isMajorSuffix(last) { return parts[parts.count - 2] }
        return parts.last ?? package
    }

    /// Why `go install <package>@latest` is not this binary's update; nil when it is.
    static func notIndexed(_ item: ManagedItem) -> String? {
        guard item.backend != nil, !item.key.hasPrefix("#") else { return "built outside module mode" }
        if item.key.hasPrefix("command-line-arguments") { return "built from loose .go files, not a package" }
        if item.key.contains("#") { return "renamed since go install wrote it" }
        guard let version = item.installed else { return nil }
        if version == "(devel)" { return "built from a checkout (devel)" }
        if version.contains("+dirty") { return "built from a checkout with uncommitted changes" }
        if isPseudoVersion(version) { return "a pseudo-version: built from a commit, not a release" }
        return nil
    }

    /// `0.0.0-20191109021931-daa7c04131f5`, `1.2.4-0.20191109…-…`,
    /// `1.2.3-pre.0.20191109…-…` (the `v` already dropped).
    static func isPseudoVersion(_ version: String) -> Bool {
        version.range(
            of: #"^[0-9]+\.[0-9]+\.[0-9]+-(?:[0-9A-Za-z-]+\.)*?(?:0\.)?[0-9]{14}-[0-9a-f]{12}(?:\+incompatible)?$"#,
            options: .regularExpression) != nil
    }

    struct Latest: Decodable {
        let Version: String
        let GoVersion: String?
    }

    static func latest(_ data: Data) -> Latest? {
        try? JSONDecoder().decode(Latest.self, from: data)
    }

    static func verdict(_ item: ManagedItem, latest: Latest?, localGo: String?) -> ManagedVerdict {
        guard let latest else {
            return ManagedVerdict(
                item: item, vendorWouldUpgrade: nil,
                blocker: .channelUnreadable("go list -m \(item.backend ?? item.key)@latest did not answer"))
        }
        let version = latest.Version.hasPrefix("v") ? String(latest.Version.dropFirst()) : latest.Version
        let answered = item.with(latestOverall: version)
        guard let installed = item.installed else { return ManagedVerdict(item: answered, vendorWouldUpgrade: nil) }
        let newer = VersionComparator.isNewer(version, than: installed)
        if newer, let needed = latest.GoVersion, let localGo, VersionComparator.isNewer(needed, than: localGo) {
            return ManagedVerdict(
                item: answered.adding(fact: .note("\(version) needs go \(needed); GOTOOLCHAIN=local keeps go \(localGo), so no toolchain is downloaded")),
                vendorWouldUpgrade: nil, blocker: .runtimeTooOld("go \(needed)"))
        }
        return ManagedVerdict(item: answered, vendorWouldUpgrade: newer)
    }

    /// A `go install` of this package running.
    static func busy(package: String, processes: [NpmActivity.Process]) -> String? {
        for process in processes {
            guard let program = process.arguments.first.map({ ($0 as NSString).lastPathComponent }), program == "go",
                  let install = process.arguments.firstIndex(of: "install"),
                  process.arguments[(install + 1)...].contains(where: { $0 == package || $0.hasPrefix(package + "@") })
            else { continue }
            return "go install \(package) is running (pid \(process.pid))"
        }
        return nil
    }

    /// `KEY=value` lines, as `go env -w` writes them.
    static func envValues(_ data: Data?) -> [String: String] {
        guard let data else { return [:] }
        var values: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        return values
    }
}
