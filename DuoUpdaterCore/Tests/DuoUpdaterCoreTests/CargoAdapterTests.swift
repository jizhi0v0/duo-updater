import Foundation
import Testing
@testable import DuoUpdaterCore

/// cargo's installs as managed rows (`CargoAdapter`, design §4.9), driven by
/// cargo's own files: `Fixtures/managed/cargo/` holds what cargo 1.99.1 wrote
/// after `cargo install tokei --version 14.0.0 --features yaml` in an
/// isolated `CARGO_HOME`, and the tails of crates.io's sparse index for tokei
/// and rand (2026-10-27).
///
/// The host is scripted (`FakeHost`): nothing here reads the real home, runs
/// cargo or reaches the network. Each case names the mutation it fails under.
struct CargoAdapterTests {

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let root = "/ZZFixture-home/.cargo"
    static let rustupSHA = String(repeating: "ab", count: 32)

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/cargo/\(name)"))
    }

    /// The real home's shape (2026-10-27): one package of two binaries on
    /// several lines, a path install, plus the fixture's tokei.
    static let v1 = """
        [v1]
        "cross 0.2.5 (registry+https://github.com/rust-lang/crates.io-index)" = [
            "cross",
            "cross-util",
        ]
        "duo-email 0.1.4 (path+file:///Users/x/duo-email)" = ["duo-email"]
        "hexyl 0.16.0 (git+https://github.com/sharkdp/hexyl#5e5ce4c9)" = ["hexyl"]
        "tokei 14.0.0 (registry+https://github.com/rust-lang/crates.io-index)" = ["tokei"]
        """

    final class FakeHost: @unchecked Sendable {
        let lock = NSLock()
        var files: [String: Data] = [:]
        var links: [String: String] = [:]
        var rustup: RustScanner.Rustup? = RustScanner.Rustup(
            path: CargoAdapterTests.root + "/bin/rustup", problem: nil, sha256: CargoAdapterTests.rustupSHA,
            hostTriple: "aarch64-apple-darwin", claimedVersion: "1.29.1", quarantined: false)
        var toolchain: String? = "1.99.1"
        var published: String? = "1.29.1"
        var index: [String: Data] = [:]
        var processes: [NpmActivity.Process] = []
        private var _identified = 0
        var identified: Int { lock.withLock { _identified } }

        init() throws {
            let v2 = try JSONSerialization.jsonObject(with: CargoAdapterTests.fixture("crates2-tokei14.json")) as! [String: Any]
            files[CargoAdapterTests.root + "/.crates.toml"] = Data(CargoAdapterTests.v1.utf8)
            files[CargoAdapterTests.root + "/.crates2.json"] = try JSONSerialization.data(withJSONObject: v2)
            for name in ["cargo", "rustc", "rustup"] {
                links[CargoAdapterTests.root + "/bin/" + name] = CargoAdapterTests.root + "/bin/rustup"
            }
            index["tokei"] = try CargoAdapterTests.fixture("index-tokei-tail")
            index["cross"] = Data(#"{"name":"cross","vers":"0.2.5","yanked":false}"#.utf8)
        }

        var host: CargoAdapter.Host {
            CargoAdapter.Host(
                contents: { path in self.lock.withLock { self.files[path] } },
                resolve: { path in self.lock.withLock { self.links[path] } },
                rustup: { home in
                    #expect(home == CargoAdapterTests.root)
                    return self.lock.withLock { self.rustup }
                },
                toolchain: { rustupHome in
                    #expect(rustupHome == "/ZZFixture-home/.rustup")
                    return self.lock.withLock { self.toolchain }
                },
                identify: { sha, _, _ in
                    self.lock.withLock {
                        self._identified += 1
                        return sha == CargoAdapterTests.rustupSHA ? self.published : nil
                    }
                },
                index: { crate in
                    guard let data = self.lock.withLock({ self.index[crate] }) else { throw SparseIndex.Failure.http(404) }
                    return data
                },
                processes: { self.lock.withLock { self.processes } })
        }
    }

    static func adapter(_ host: FakeHost, proof: RustupProof = RustupProof()) -> CargoAdapter {
        CargoAdapter(home: home, host: host.host, proof: proof)
    }

    static func provider(
        _ host: FakeHost, proof: RustupProof, runs: Runs = Runs(), afterRun: @escaping @Sendable () -> Void = {}
    ) -> ManagedProvider {
        ManagedProvider(
            adapter(host, proof: proof), home: home,
            proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { command, environment, _, _, _ in
                await runs.record(command, environment)
                afterRun()
                return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: [])
            })
    }

    actor Runs {
        private(set) var commands: [(CLIToolCommand, [String: String])] = []
        func record(_ command: CLIToolCommand, _ environment: [String: String]) { commands.append((command, environment)) }
    }

    static func status(_ report: CLIToolReport, _ key: String) -> CLIToolStatus? {
        report.statuses.first { $0.managedItem?.key == key }
    }

    // MARK: the records

    /// v1 names every package, its binaries on one line or several; v2 adds
    /// how it was built under the same key. Mutation: read bins from the first
    /// line only; take v2's keys as the list; read `rustc`'s first line.
    @Test func theRecordsReadAsCargoWroteThem() throws {
        let fixture = try CrateTracker.packages(
            v1: String(decoding: Self.fixture("crates-v1-tokei14.toml"), as: UTF8.self),
            v2: Self.fixture("crates2-tokei14.json"))
        #expect(fixture == [CrateTracker.Package(
            name: "tokei", version: "14.0.0", source: "registry+https://github.com/rust-lang/crates.io-index",
            bins: ["tokei"], features: ["yaml"], allFeatures: false, noDefaultFeatures: false,
            versionRequest: "=14.0.0", rustc: "1.99.1")])

        let packages = CrateTracker.packages(v1: Self.v1, v2: nil)
        #expect(packages.map(\.name) == ["cross", "duo-email", "hexyl", "tokei"])
        #expect(packages[0].bins == ["cross", "cross-util"])
        #expect(packages.map(\.origin) == [
            .cratesIO, .path("file:///Users/x/duo-email"), .git("https://github.com/sharkdp/hexyl#5e5ce4c9"), .cratesIO,
        ])
        // In v1 only (cargo-binstall writes v1 first): defaults, still a package.
        #expect(packages[3].features.isEmpty && packages[3].versionRequest == nil)
        #expect(CrateTracker.origin(of: "sparse+https://index.crates.io/") == .cratesIO)
        #expect(CrateTracker.origin(of: "sparse+https://my.registry/") == .otherRegistry("sparse+https://my.registry/"))
    }

    // MARK: the index

    /// cargo's index layout. Mutation: keep the name's case; split a
    /// three-letter name like a long one.
    @Test func theIndexPathIsCargos() {
        #expect(SparseIndex.url(of: "a").absoluteString == "https://index.crates.io/1/a")
        #expect(SparseIndex.url(of: "ab").absoluteString == "https://index.crates.io/2/ab")
        #expect(SparseIndex.url(of: "abc").absoluteString == "https://index.crates.io/3/a/abc")
        #expect(SparseIndex.url(of: "tokei").absoluteString == "https://index.crates.io/to/ke/tokei")
        #expect(SparseIndex.url(of: "Inflector").absoluteString == "https://index.crates.io/in/fl/inflector")
    }

    /// The index is in publish order: rand's newest is 0.10.3 though 0.8.8
    /// came after 0.10.2. Pre-releases and yanked versions are never the
    /// newest. Mutation: take the last line; drop the pre-release filter.
    @Test func theNewestIsByVersionNotByLine() throws {
        let rand = SparseIndex.releases(try Self.fixture("index-rand-tail"))
        #expect(rand.map(\.version) == ["0.8.6", "0.10.2", "0.8.7", "0.9.5", "0.8.8", "0.10.3"])
        #expect(SparseIndex.newest(rand)?.version == "0.10.3")
        #expect(SparseIndex.newest(rand)?.rustVersion == "1.85")
        let tokei = SparseIndex.releases(try Self.fixture("index-tokei-tail"))
        #expect(SparseIndex.newest(tokei)?.version == "15.0.0")
        let lines = [
            #"{"vers":"1.0.0","yanked":false}"#, #"{"vers":"2.0.0","yanked":true}"#,
            #"{"vers":"1.1.0-rc.1","yanked":false}"#, #"{"vers":"1.0.1+build.5","yanked":false}"#,
        ].joined(separator: "\n")
        #expect(SparseIndex.newest(SparseIndex.releases(Data(lines.utf8)))?.version == "1.0.1+build.5")
    }

    // MARK: scan and trust

    /// One row per package; a git, path or other-registry install is reported.
    /// cargo is rustup's proxy, unproved until a check proves the bytes.
    /// Mutation: offer a git row; trust the proxy without the proof.
    @Test func theScanFindsEveryPackageAndWaitsForTheProof() async throws {
        let host = try FakeHost()
        let scan = await Self.adapter(host).scan()
        #expect(scan.items.map(\.key) == ["cross", "duo-email", "hexyl", "tokei"])
        #expect(scan.items[0].installPath == Self.root + "/bin/cross")
        #expect(scan.roots.first?.binary == ManagedRoot.Binary(
            path: Self.root + "/bin/cargo", version: "1.99.1", trust: .untrusted(.adHoc)))
        #expect(host.identified == 0)
        let tokei = try #require(scan.items.last)
        #expect(tokei.effects == [.compilesFromSource, .oldRemoved, .dropsSpecifier("=14.0.0")])
        #expect(tokei.notes == .crate("tokei"))
        #expect(CargoAdapter.notIndexed(scan.items[1]) == "installed from a local path (file:///Users/x/duo-email)")
        #expect(CargoAdapter.notIndexed(scan.items[2]) == "installed from git (https://github.com/sharkdp/hexyl#5e5ce4c9)")
    }

    /// cargo-binstall's record, as cargo-binstall 1.26.1 wrote it on this Mac
    /// (2026-10-27): objects back to back, no newline. A package binstall
    /// recorded at the version `.crates.toml` has says so; one cargo has
    /// since replaced (the record stays at the old version) does not.
    /// Mutation: match by name alone; split the record on newlines.
    @Test func aPackageCargoBinstallInstalledSaysSo() async throws {
        let record = try Self.fixture("binstall-crates-v1.json")
        #expect(!record.contains(0x0A))
        #expect(CrateTracker.binstalled(record) == ["hyperfine 1.18.0", "ripgrep 15.2.0"])
        let host = try FakeHost()
        host.files[Self.root + "/.crates.toml"] = Data("""
            [v1]
            "hyperfine 2.0.0 (registry+https://github.com/rust-lang/crates.io-index)" = ["hyperfine"]
            "ripgrep 15.2.0 (registry+https://github.com/rust-lang/crates.io-index)" = ["rg"]
            """.utf8)
        host.files[Self.root + "/binstall/crates-v1.json"] = record
        let items = await Self.adapter(host).scan().items
        let note = ManagedItem.Fact.note("installed by cargo-binstall; the update builds it with cargo install")
        #expect(items.map(\.key) == ["hyperfine", "ripgrep"])
        #expect(!items[0].facts.contains(note))
        #expect(items[1].facts.contains(note))
    }

    /// A `bin/cargo` that is not rustup's proxy — or a `bin/rustc` that is
    /// not, which the command names as `RUSTC` — is never proved or run.
    /// Mutation: check only `cargo`'s link.
    @Test func aCargoThatIsNotTheProxyIsNotRun() async throws {
        let host = try FakeHost()
        host.links[Self.root + "/bin/rustc"] = "/opt/homebrew/Cellar/rust/1.99.1/bin/rustc"
        let report = await Self.provider(host, proof: RustupProof()).check()
        #expect(host.identified == 0)
        let tokei = try #require(Self.status(report, "tokei"))
        #expect(tokei.state == .updateAvailable)
        #expect(tokei.oneClick == nil)
        #expect(tokei.withheld == .unverified)
        #expect(tokei.commandToCopy?.arguments == ["install", "tokei", "--features", "yaml"])
    }

    // MARK: check and click

    /// The check proves rustup once, then offers tokei 14.0.0 → 15.0.0 with
    /// its recorded features; the click runs exactly that, with the root's
    /// homes and its own `rustc` proxy. Mutation: drop `--features`; leave
    /// `RUSTC` out (§12 item 9: exit 101 without it); skip the proof.
    @Test func tokeiIsOfferedWithItsFeaturesAndTheClickRunsThat() async throws {
        let host = try FakeHost()
        let proof = RustupProof()
        let runs = Runs()
        // After the build the records say 15.0.0.
        let after = String(decoding: try #require(host.files[Self.root + "/.crates.toml"]), as: UTF8.self)
            .replacingOccurrences(of: "tokei 14.0.0", with: "tokei 15.0.0")
        let provider = Self.provider(host, proof: proof, runs: runs) {
            host.lock.withLock { host.files[Self.root + "/.crates.toml"] = Data(after.utf8) }
        }
        let report = await provider.check()
        #expect(host.identified == 1)
        #expect(proof.version(of: Self.rustupSHA) == "1.29.1")
        let tokei = try #require(Self.status(report, "tokei"))
        #expect(tokei.state == .updateAvailable)
        #expect(tokei.installedVersion == "14.0.0")
        #expect(tokei.latestVersion == "15.0.0")
        let command = try #require(tokei.oneClick)
        #expect(command.executable == Self.root + "/bin/cargo")
        #expect(command.arguments == ["install", "tokei", "--features", "yaml"])
        #expect(Self.status(report, "cross")?.state == .upToDate)
        #expect(Self.status(report, "hexyl")?.withheld == .unsupportedInstaller)
        #expect(Self.status(report, "duo-email")?.oneClick == nil)

        #expect(await provider.update(tokei) { _ in } == .updated(version: "15.0.0"))
        let commands = await runs.commands
        #expect(commands.count == 1)
        #expect(commands.first?.0 == command)
        #expect(commands.first?.1["CARGO_HOME"] == Self.root)
        #expect(commands.first?.1["RUSTUP_HOME"] == "/ZZFixture-home/.rustup")
        #expect(commands.first?.1["RUSTC"] == Self.root + "/bin/rustc")
    }

    /// The click sees the proof the check recorded, with no network: the
    /// scan at the click hashes the bytes and finds them proved. Bytes that
    /// changed since are not. Mutation: let the scan call `identify`; key the
    /// proof by path.
    @Test func theProofIsByTheBytes() async throws {
        let host = try FakeHost()
        let proof = RustupProof()
        _ = await Self.adapter(host, proof: proof).resolve(await Self.adapter(host, proof: proof).scan())
        let proved = await Self.adapter(host, proof: proof).scan()
        #expect(proved.roots.first?.binary?.trust == .verifiedHash)
        #expect(host.identified == 1)
        host.rustup = RustScanner.Rustup(
            path: Self.root + "/bin/rustup", problem: nil, sha256: String(repeating: "cd", count: 32),
            hostTriple: "aarch64-apple-darwin", claimedVersion: "1.29.1", quarantined: false)
        let changed = await Self.adapter(host, proof: proof).scan()
        #expect(changed.roots.first?.binary?.trust == .untrusted(.adHoc))
    }

    /// A newest that needs a newer rustc than the default toolchain is not
    /// offered: `cargo install` would stop on it. Mutation: ignore
    /// `rust_version`; compare against the rustc that built the old one.
    @Test func aNewestAboveTheToolchainIsReported() async throws {
        let host = try FakeHost()
        host.toolchain = "1.70.0"
        let report = await Self.provider(host, proof: RustupProof()).check()
        let tokei = try #require(Self.status(report, "tokei"))
        #expect(tokei.state == .unknown)
        #expect(tokei.withheld == .runtimeTooOld)
        #expect(tokei.oneClick == nil)
        #expect(tokei.managedItem?.facts.contains(.note("15.0.0 needs rustc 1.71; the default toolchain is 1.70.0")) == true)
    }

    /// A `cargo install` of the crate, or rustup moving the toolchain, takes
    /// the click away. Mutation: match any cargo command; ignore rustup.
    @Test func aRunningInstallOrRustupIsBusy() {
        #expect(CargoAdapter.busy(crate: "tokei", processes: [
            NpmActivity.Process(pid: 7, arguments: ["/x/.cargo/bin/cargo", "install", "tokei"], executable: "/x/.cargo/bin/rustup"),
        ]) == "cargo install tokei is running (pid 7)")
        #expect(CargoAdapter.busy(crate: "tokei", processes: [
            NpmActivity.Process(pid: 8, arguments: ["cargo", "build", "--release"], executable: nil),
            NpmActivity.Process(pid: 9, arguments: ["cargo", "install", "hexyl"], executable: nil),
        ]) == nil)
        #expect(CargoAdapter.busy(crate: "tokei", processes: [
            NpmActivity.Process(pid: 10, arguments: ["rustup", "update", "stable"], executable: nil),
        ]) == "rustup update is running (pid 10)")
    }

    /// `default_toolchain` before any table. Mutation: read past `[overrides]`.
    @Test func theDefaultToolchainIsTheTopLevelKey() {
        #expect(CargoAdapter.defaultToolchain("""
            version = "12"
            default_toolchain = "stable-aarch64-apple-darwin"
            profile = "default"

            [overrides]
            """) == "stable-aarch64-apple-darwin")
        #expect(CargoAdapter.defaultToolchain("[overrides]\ndefault_toolchain = \"x\"") == nil)
    }

    /// crates.io's `repository`, and a GitHub URL with `.git`. Mutation: keep `.git`.
    @Test func theRepositoryIsReadOffCratesIO() {
        let data = Data(#"{"crate":{"id":"tokei","repository":"https://github.com/XAMPPRocky/tokei.git"}}"#.utf8)
        let url = CratesIO.repository(data)
        #expect(url == "https://github.com/XAMPPRocky/tokei.git")
        #expect(CratesIO.gitHub(url!)! == ("XAMPPRocky", "tokei"))
        #expect(CratesIO.gitHub("https://gitlab.com/a/b") == nil)
    }
}
