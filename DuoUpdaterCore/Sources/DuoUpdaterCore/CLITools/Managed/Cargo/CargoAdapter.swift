import Foundation

/// The packages `cargo install` put under `~/.cargo` as managed rows, one per
/// package, moved by `cargo install <name>` with the features it was built
/// with (plans/cli-managers-redesign.md §4.9, D8).
///
/// What was measured, with cargo 1.99.1 through rustup's proxy and an
/// isolated `CARGO_HOME` (2026-10-27):
/// - **The list, disk only**: `.crates.toml` and `.crates2.json`
///   (`CrateTracker`).
/// - **The newest, no spawn**: crates.io's sparse index per crate
///   (`SparseIndex`), revalidated by ETag; git and path installs are on no
///   index and are reported only.
/// - **The command**: `env -i HOME CARGO_HOME RUSTUP_HOME PATH=<system>
///   ~/.cargo/bin/cargo install …` failed — `could not execute process
///   rustc -vV (never executed)`, exit 101: rustup's proxy runs cargo, and
///   cargo looks `rustc` up on `PATH`. With `RUSTC` naming the root's own
///   `rustc` proxy it built: `cargo install tokei --features yaml` over 14.0.0
///   (installed `--version 14.0.0 --features yaml`) → "Replaced package
///   `tokei v14.0.0` with `tokei v15.0.0`", exit 0, 17 s; `.crates2.json`
///   kept `["yaml"]` and dropped `version_req` `=14.0.0` (§12 items 9, 10).
///
/// cargo here is rustup's proxy: `<root>/bin/cargo` and `<root>/bin/rustc`
/// links to `<root>/bin/rustup`, run only when that rustup's bytes are
/// rust-lang's own (`RustCheck`'s rule 1, proved by `resolve` and recorded in
/// `RustupProof`). Anything else at `bin/cargo` — a Homebrew rust, a copy —
/// leaves the rows reported, the command handed out.
public struct CargoAdapter: ManagerAdapter {

    public static let id = ManagerID("cargo")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "cargo install", signer: nil, logo: "cli-rust", tint: .label,
        // The toolchain's cargo compiles; `rustup update` replaces it.
        lane: "rust", deadline: RustUpdater.defaultDeadline)

    public var descriptor: ManagerDescriptor { Self.descriptor }

    /// Everything the adapter reads from the Mac, injected so tests never
    /// touch the host (`CargoAdapterTests`).
    struct Host: Sendable {
        /// A file's bytes, nil when there is none. Blocking.
        var contents: @Sendable (String) -> Data?
        /// The path with every link followed; nil when nothing is there.
        var resolve: @Sendable (String) -> String?
        /// rustup's binary under a cargo home, hashed (`RustScanner.rustup`). Blocking.
        var rustup: @Sendable (_ cargoHome: String) -> RustScanner.Rustup?
        /// The default toolchain's Rust version ("1.99.1"), from its manifest. Blocking.
        var toolchain: @Sendable (_ rustupHome: String) -> String?
        /// The version rust-lang publishes these bytes as; nil when none.
        /// Throws when the server could not be read.
        var identify: @Sendable (_ sha256: String, _ triple: String?, _ claimed: String?) async throws -> String?
        var index: @Sendable (_ crate: String) async throws -> Data
        var processes: @Sendable () -> [NpmActivity.Process]

        init(
            contents: @escaping @Sendable (String) -> Data?,
            resolve: @escaping @Sendable (String) -> String?,
            rustup: @escaping @Sendable (String) -> RustScanner.Rustup?,
            toolchain: @escaping @Sendable (String) -> String?,
            identify: @escaping @Sendable (String, String?, String?) async throws -> String?,
            index: @escaping @Sendable (String) async throws -> Data,
            processes: @escaping @Sendable () -> [NpmActivity.Process]
        ) {
            self.contents = contents
            self.resolve = resolve
            self.rustup = rustup
            self.toolchain = toolchain
            self.identify = identify
            self.index = index
            self.processes = processes
        }

        static let live = Host(
            contents: NvmNodeAdapter.Host.live.contents, resolve: NvmNodeAdapter.Host.live.resolve,
            rustup: { RustScanner(cargoHome: URL(fileURLWithPath: $0), rustupHome: URL(fileURLWithPath: "/")).rustup() },
            toolchain: { CargoAdapter.defaultToolchainVersion(rustupHome: $0) },
            identify: { sha256, triple, claimed in
                try await RustRelease().identify(sha256: sha256, triple: triple, claimed: claimed).verified
            },
            index: { try await SparseIndex.fetch($0) },
            processes: { NpmActivity.runningProcesses() })
    }

    let home: URL
    let host: Host
    let proof: RustupProof

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, host: .live)
    }

    init(home: URL, host: Host, proof: RustupProof = .shared) {
        self.home = home
        self.host = host
        self.proof = proof
    }

    /// `CARGO_HOME`'s and `RUSTUP_HOME`'s defaults: what a GUI process sees.
    var root: String { home.path + "/.cargo" }
    var rustupHome: String { home.path + "/.rustup" }

    // MARK: - ManagerAdapter

    public func scan() async -> ManagedScan {
        let (host, root, rustupHome, descriptor, proof) = (self.host, self.root, self.rustupHome, self.descriptor, self.proof)
        return await offCooperativePool {
            guard let v1 = host.contents(root + "/.crates.toml") else { return .empty }
            let packages = CrateTracker.packages(
                v1: String(decoding: v1, as: UTF8.self), v2: host.contents(root + "/.crates2.json"))
            guard !packages.isEmpty else { return .empty }
            let binary = Self.binary(root: root, rustupHome: rustupHome, host: host, proof: proof)
            var items: [ManagedItem] = []
            var states: [String: String] = [:]
            for package in packages {
                let item = Self.item(package, root: root, descriptor: descriptor)
                items.append(item)
                states[item.identity] = [package.version, package.source, package.features.joined(separator: "+"),
                                         package.allFeatures ? "all" : "-", package.noDefaultFeatures ? "nodefault" : "-"]
                    .joined(separator: ",")
            }
            return ManagedScan(roots: [ManagedRoot(manager: Self.id, path: root, binary: binary)], items: items, states: states)
        }
    }

    /// Proves rustup's bytes against rust-lang's published hash, once per
    /// bytes per process (`RustupProof`), so the scan at the click can see the
    /// proof without the network.
    public func resolve(_ scan: ManagedScan) async -> ManagedScan {
        guard let root = scan.roots.first, let binary = root.binary, binary.trust == .untrusted(.adHoc) else { return scan }
        let (host, cargoHome) = (self.host, self.root)
        guard let rustup = await offCooperativePool({ host.rustup(cargoHome) }), rustup.problem == nil,
              !rustup.quarantined, let sha256 = rustup.sha256,
              let verified = try? await host.identify(sha256, rustup.hostTriple, rustup.claimedVersion)
        else { return scan }
        proof.record(sha256, version: verified)
        let proved = ManagedRoot(
            manager: root.manager, path: root.path,
            binary: ManagedRoot.Binary(path: binary.path, version: binary.version, trust: .verifiedHash))
        return ManagedScan(roots: [proved] + scan.roots.dropFirst(), items: scan.items, states: scan.states)
    }

    /// One sparse-index read per crates.io package, at most
    /// `UvToolAdapter.parallelFetches` at once. Packages from git, a path or
    /// another registry are reported.
    public func check(_ scan: ManagedScan) async -> [ManagedVerdict] {
        let fetch = host.index
        let rustc = scan.roots.first?.binary?.version
        var verdicts: [String: ManagedVerdict] = [:]
        var asked: [ManagedItem] = []
        for item in scan.items {
            if let reason = Self.notIndexed(item) {
                verdicts[item.identity] = ManagedVerdict(item: item, vendorWouldUpgrade: nil, blocker: .notIndexed(reason))
            } else {
                asked.append(item)
            }
        }
        let answers: [ManagedVerdict] = await withTaskGroup(of: ManagedVerdict.self) { group in
            var pending = asked[...]
            var results: [ManagedVerdict] = []
            func start(_ item: ManagedItem) {
                group.addTask {
                    do {
                        let releases = SparseIndex.releases(try await fetch(item.key))
                        return Self.verdict(item, releases: releases, rustc: rustc)
                    } catch {
                        return ManagedVerdict(
                            item: item, vendorWouldUpgrade: nil,
                            blocker: .channelUnreadable("crates.io's index did not answer for \(item.key): \(error)"))
                    }
                }
            }
            for _ in 0..<UvToolAdapter.parallelFetches { if let next = pending.popFirst() { start(next) } }
            while let verdict = await group.next() {
                results.append(verdict)
                if let next = pending.popFirst() { start(next) }
            }
            return results
        }
        for verdict in answers { verdicts[verdict.item.identity] = verdict }
        let processes = host.processes
        let running = await offCooperativePool { processes() }
        return scan.items.compactMap { item in
            guard let verdict = verdicts[item.identity] else { return nil }
            let busy = Self.busy(crate: item.key, processes: running)
            return busy == nil ? verdict
                : ManagedVerdict(item: verdict.item, vendorWouldUpgrade: verdict.vendorWouldUpgrade, blocker: verdict.blocker, busy: busy)
        }
    }

    /// `<root>/bin/cargo install <name>` and the features `.crates2.json`
    /// recorded (D8: what cargo-update passes, without running it or
    /// cargo-binstall), read from the records as they are. `CARGO_HOME` and `RUSTUP_HOME` the row's homes, as
    /// `RustUpdater` sets them; `RUSTC` the root's own proxy (§12 item 9).
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary, Self.notIndexed(item) == nil, let build = package(item) else { return nil }
        var arguments = ["install", item.key]
        if !build.features.isEmpty { arguments += ["--features", build.features.joined(separator: ",")] }
        if build.allFeatures { arguments.append("--all-features") }
        if build.noDefaultFeatures { arguments.append("--no-default-features") }
        return (CLIToolCommand(executable: binary.path, arguments: arguments, pathPrefix: nil),
                ["CARGO_HOME": root.path, "RUSTUP_HOME": rustupHome, "RUSTC": root.path + "/bin/rustc"])
    }

    /// The package's binaries and cargo's two records; a new binary the newer
    /// version adds, and the `bin/cargo-install<random>/` directory cargo
    /// stages them in for a few milliseconds (§13.4: a stop 0.03 s after
    /// "Finished" left it holding the new `tokei`). Another `cargo install`
    /// (or rustup proxy) into this home during the run would be undone with
    /// it: the records are shared.
    public func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption? {
        guard let build = package(item) else { return nil }
        let bin = root.path + "/bin"
        return ManagedInterruption(
            paths: build.bins.map { bin + "/" + $0 } + [root.path + "/.crates.toml", root.path + "/.crates2.json"],
            // Every new entry of `bin`, not only the staging directories: a
            // new binary name left behind once the records are put back is
            // claimed by no package, and cargo then refuses every later
            // `cargo install` of it ("binary `X` already exists in
            // destination … Add --force to overwrite",
            // `src/ops/common_for_install_and_uninstall.rs`; review round 4).
            created: [ManagedSnapshot.NewEntries(directory: bin, any: true)])
    }

    public func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String? {
        Self.busy(crate: item.key, processes: processes)
    }

    public func reread(_ item: ManagedItem) async -> String? {
        await scan().items.first { $0.identity == item.identity }?.installed
    }

    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog {
        try await ManagedNotes.fetch(item.notes, force: force)
    }

    // MARK: - The parts

    /// cargo as the root runs it: `bin/cargo` and `bin/rustc` both rustup's
    /// proxies, and that rustup's bytes proved in this process. Its version is
    /// the default toolchain's, which is the cargo and rustc the proxy runs
    /// from `/`. Blocking.
    static func binary(root: String, rustupHome: String, host: Host, proof: RustupProof) -> ManagedRoot.Binary? {
        let cargo = root + "/bin/cargo"
        guard let resolved = host.resolve(cargo) else { return nil }
        let version = host.toolchain(rustupHome)
        let rustupPath = host.resolve(root + "/bin/rustup")
        guard resolved == rustupPath, host.resolve(root + "/bin/rustc") == rustupPath,
              let rustup = host.rustup(root), rustup.problem == nil
        else { return ManagedRoot.Binary(path: cargo, version: version, trust: .untrusted(nil)) }
        if rustup.quarantined { return ManagedRoot.Binary(path: cargo, version: version, trust: .quarantined) }
        let proved = rustup.sha256.flatMap(proof.version(of:)) != nil
        return ManagedRoot.Binary(path: cargo, version: version, trust: proved ? .verifiedHash : .untrusted(.adHoc))
    }

    static func item(_ package: CrateTracker.Package, root: String, descriptor: ManagerDescriptor) -> ManagedItem {
        var facts: [ManagedItem.Fact] = [.backend(package.source)]
        var built: [String] = []
        if !package.features.isEmpty { built.append("features \(package.features.joined(separator: ","))") }
        if package.allFeatures { built.append("--all-features") }
        if package.noDefaultFeatures { built.append("--no-default-features") }
        if !built.isEmpty { facts.append(.note("built with \(built.joined(separator: ", ")), which the update passes again")) }
        if let rustc = package.rustc { facts.append(.note("built by rustc \(rustc)")) }
        var effects: [ManagedItem.Effect] = [.compilesFromSource, .oldRemoved]
        if let request = package.versionRequest { effects.append(.dropsSpecifier(request)) }
        return ManagedItem(
            descriptor: descriptor, root: root, key: package.name, name: package.name,
            installPath: root + "/bin/" + (package.bins.first ?? package.name), shape: .package,
            installed: package.version, backend: package.source,
            notes: package.origin == .cratesIO ? .crate(package.name) : nil, effects: effects, facts: facts)
    }

    /// Why a package is on no index the check reads; nil for crates.io's.
    static func notIndexed(_ item: ManagedItem) -> String? {
        guard let source = item.backend else { return "no source recorded" }
        switch CrateTracker.origin(of: source) {
        case .cratesIO: return nil
        case .git(let url): return "installed from git (\(url))"
        case .path(let url): return "installed from a local path (\(url))"
        case .otherRegistry(let url): return "installed from another registry (\(url))"
        }
    }

    /// The package as the root's records say now: the flags the update
    /// passes again. Blocking (two small files).
    func package(_ item: ManagedItem) -> CrateTracker.Package? {
        guard let v1 = host.contents(root + "/.crates.toml") else { return nil }
        return CrateTracker.packages(v1: String(decoding: v1, as: UTF8.self), v2: host.contents(root + "/.crates2.json"))
            .first { $0.name == item.key }
    }

    /// The newest crates.io release against the installed one. A newest that
    /// declares a `rust-version` above the default toolchain is not offered:
    /// `cargo install <name>` stops on it rather than pick an older one —
    /// measured 2026-10-27 with toolchain 1.95.0: "cannot install package
    /// `hyperfine 2.0.0`, it requires rustc 1.97.0 or newer, while the
    /// currently active rustc version is 1.95.0 / `hyperfine 1.20.0` supports
    /// rustc 1.88.0", exit 101, nothing installed.
    static func verdict(_ item: ManagedItem, releases: [SparseIndex.Release], rustc: String?) -> ManagedVerdict {
        guard let newest = SparseIndex.newest(releases) else {
            return ManagedVerdict(
                item: item, vendorWouldUpgrade: nil,
                blocker: .channelUnreadable("crates.io lists no release of \(item.key) that is not yanked or a pre-release"))
        }
        let answered = item.with(latestOverall: newest.version)
        guard let installed = item.installed else { return ManagedVerdict(item: answered, vendorWouldUpgrade: nil) }
        let newer = VersionComparator.compare(SparseIndex.core(newest.version), SparseIndex.core(installed)) == .orderedDescending
        if newer, let needed = newest.rustVersion, let rustc, !SparseIndex.satisfies(rustc: rustc, rustVersion: needed) {
            return ManagedVerdict(
                item: answered.adding(fact: .note("\(newest.version) needs rustc \(needed); the default toolchain is \(rustc)")),
                vendorWouldUpgrade: nil, blocker: .runtimeTooOld("rustc \(needed)"))
        }
        return ManagedVerdict(item: answered, vendorWouldUpgrade: newer)
    }

    /// A `cargo install` of this crate running, or rustup changing the
    /// toolchain that compiles it (`RustActivity`).
    static func busy(crate: String, processes: [NpmActivity.Process]) -> String? {
        for process in processes {
            if let command = RustActivity.changingCommand(process.arguments) {
                return "\(command) is running (pid \(process.pid))"
            }
            guard let program = process.arguments.first.map({ ($0 as NSString).lastPathComponent }), program == "cargo",
                  let install = process.arguments.firstIndex(of: "install"),
                  process.arguments[(install + 1)...].contains(crate)
            else { continue }
            return "cargo install \(crate) is running (pid \(process.pid))"
        }
        return nil
    }

    /// `settings.toml`'s `default_toolchain`, and the Rust version its
    /// manifest records. Blocking.
    static func defaultToolchainVersion(rustupHome: String) -> String? {
        guard let data = FileManager.default.contents(atPath: rustupHome + "/settings.toml"),
              let name = defaultToolchain(String(decoding: data, as: UTF8.self))
        else { return nil }
        return RustScanner.manifestVersion(URL(fileURLWithPath: rustupHome)
            .appendingPathComponent("toolchains").appendingPathComponent(name)
            .appendingPathComponent("lib/rustlib/multirust-channel-manifest.toml"))?.number
    }

    /// The top-level `default_toolchain = "…"`, before the first table.
    static func defaultToolchain(_ toml: String) -> String? {
        for raw in toml.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            guard line.hasPrefix("default_toolchain") else { continue }
            let value = line.split(separator: "=", maxSplits: 1).dropFirst().first?
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if let value, !value.isEmpty, !value.contains("/") { return value }
        }
        return nil
    }
}
