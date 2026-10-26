import Foundation
import Testing
@testable import DuoUpdaterCore

/// pipx's venvs as managed rows (`PipxAdapter`, design §4.4), driven by
/// pipx's own files: the fixtures in `Fixtures/managed/pipx/` are what pipx
/// 1.18.4 (Python 3.12.15) wrote on 2026-10-27 in an isolated home after
/// `pipx install 'ruff==0.6.0' 'cowsay==5.0' 'httpie==3.2.1'`, `pipx pin
/// cowsay` and `pipx install <a local directory>` (duolocal), plus pipx
/// 1.11.1's metadata 0.5 for ruff; `pypi-*.json` are PyPI's documents of that
/// day (black's trimmed to seven releases). The home is rewritten to
/// `/ZZFixture-home`.
///
/// The host is scripted: nothing here lists the real home, runs pipx or
/// reaches the network. Each case names the mutation it fails under.
struct PipxAdapterTests {

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let modern = "/ZZFixture-home/Library/Application Support/pipx"
    static let legacy = "/ZZFixture-home/.local/pipx"
    static let keg = "/ZZFixture-brew/Cellar/pipx/1.18.4_1"

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/pipx/\(name)"))
    }

    final class FakeHost: @unchecked Sendable {
        let lock = NSLock()
        var files: [String: Data] = [:]
        var directories: [String: [String]] = [:]
        /// Where each link ends; a path not here is not there.
        var links: [String: String] = [:]
        var quarantined: Set<String> = []
        var verifiedUv: String?
        var pypi: [String: Data] = [:]
        private var _fetches: [String] = []
        var fetches: [String] { lock.withLock { _fetches } }

        init(homebrew: Bool = true) throws {
            let venvs = PipxAdapterTests.modern + "/venvs"
            directories[venvs] = ["cowsay", "duolocal", "httpie", "ruff"]
            for name in ["cowsay", "duolocal", "httpie", "ruff"] {
                files[venvs + "/\(name)/pipx_metadata.json"] = try PipxAdapterTests.fixture("\(name)-pipx_metadata.json")
            }
            pypi["cowsay"] = try PipxAdapterTests.fixture("pypi-cowsay.json")
            pypi["httpie"] = try PipxAdapterTests.fixture("pypi-httpie.json")
            pypi["ruff"] = Data(#"{"info": {"version": "0.17.2", "requires_python": ">=3.7", "project_urls": {}}, "releases": {}}"#.utf8)
            if homebrew {
                links["/ZZFixture-brew/bin/pipx"] = PipxAdapterTests.keg + "/bin/pipx"
                files[PipxAdapterTests.keg + "/INSTALL_RECEIPT.json"] = Data("{}".utf8)
            }
        }

        var host: PipxAdapter.Host {
            PipxAdapter.Host(
                contents: { path in self.lock.withLock { self.files[path] } },
                directories: { path in self.lock.withLock { self.directories[path] } },
                modified: { _ in Date(timeIntervalSince1970: 1_792_750_000) },
                resolve: { path in self.lock.withLock { self.links[path] } },
                isQuarantined: { path in self.lock.withLock { self.quarantined.contains(path) } },
                pypi: { project in
                    try self.lock.withLock {
                        self._fetches.append(project)
                        guard let data = self.pypi[project] else { throw PyPIProject.Failure.http(404) }
                        return data
                    }
                },
                verifiedUv: { self.lock.withLock { self.verifiedUv } })
        }
    }

    static func adapter(_ host: FakeHost) -> PipxAdapter {
        PipxAdapter(home: home, host: host.host, homebrewRoots: ["/ZZFixture-brew"])
    }

    static func provider(_ host: FakeHost) -> ManagedProvider {
        ManagedProvider(
            adapter(host), home: home, proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { _, _, _, _, _ in ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: []) })
    }

    static func status(_ report: CLIToolReport, _ key: String) -> CLIToolStatus? {
        report.statuses.first { $0.managedItem?.key == key }
    }

    // MARK: scan

    @Test func theScanReadsEachVenvsMetadata() async throws {
        let scan = await Self.adapter(try FakeHost()).scan()
        #expect(scan.items.map(\.key) == ["cowsay", "duolocal", "httpie", "ruff"])
        let cowsay = try #require(scan.items.first { $0.key == "cowsay" })
        #expect(cowsay.request == ManagedItem.Request(kind: .exact, spelled: "5.0"))
        #expect(cowsay.facts.contains(.python("3.12.15")))
        let httpie = try #require(scan.items.first { $0.key == "httpie" })
        #expect(httpie.installed == "3.2.1")
        // pipx ignores the specifier (PX-14): not a request, an effect.
        #expect(httpie.request == nil)
        #expect(httpie.effects.contains(.dropsSpecifier("httpie==3.2.1")))
        #expect(scan.roots.map(\.path) == [Self.modern])
        #expect(scan.roots.first?.binary == ManagedRoot.Binary(path: "/ZZFixture-brew/bin/pipx", version: "1.18.4", trust: .homebrewKeg))
    }

    /// Metadata 0.5 (pipx 1.11.1) reads the same way, from the legacy root.
    @Test func legacyMetadataIsRead() async throws {
        let host = try FakeHost()
        host.directories[Self.legacy + "/venvs"] = ["ruff"]
        host.files[Self.legacy + "/venvs/ruff/pipx_metadata.json"] = try Self.fixture("ruff-pipx_metadata-0.5.json")
        let scan = await Self.adapter(host).scan()
        #expect(scan.roots.map(\.path) == [Self.modern, Self.legacy])
        let legacy = try #require(scan.items.first { $0.root == Self.legacy })
        #expect(legacy.installed == "0.6.0")
        #expect(legacy.facts.contains(.python("3.9.6")))
    }

    // MARK: check

    /// httpie is offered 3.2.1 → 3.2.4 with the warning that pipx drops
    /// `==3.2.1` (D7); cowsay is pinned with `pipx unpin cowsay` to copy;
    /// duolocal, from a local path, is reported and never asked of PyPI.
    /// Mutation: treat `package_or_url`'s `==` as a pin; ask PyPI for a
    /// path install; offer a `pipx pin`ned venv.
    @Test func theRowsFollowPipxsOwnRules() async throws {
        let host = try FakeHost()
        let report = await Self.provider(host).check()
        #expect(report.statuses.map { $0.managedItem?.key } == ["cowsay", "duolocal", "httpie", "ruff"])

        let httpie = try #require(Self.status(report, "httpie"))
        #expect(httpie.state == .updateAvailable)
        #expect(httpie.latestVersion == "3.2.4")
        // Its backend is pip: nothing on PATH but the system's — never
        // `~/.local/bin`, whose uv pipx would run unverified.
        #expect(httpie.oneClick == CLIToolCommand(
            executable: "/ZZFixture-brew/bin/pipx", arguments: ["upgrade", "httpie"], pathPrefix: nil))

        let cowsay = try #require(Self.status(report, "cowsay"))
        #expect(cowsay.state == .pinned)
        #expect(cowsay.latestVersion == "6.1")
        #expect(cowsay.manualCommand == CLIToolCommand(executable: "/ZZFixture-brew/bin/pipx", arguments: ["unpin", "cowsay"], pathPrefix: nil))

        let local = try #require(Self.status(report, "duolocal"))
        #expect(local.state == .unknown)
        #expect(local.withheld == .unsupportedInstaller)

        #expect(Set(host.fetches) == ["cowsay", "httpie", "ruff"])
    }

    /// A pipx that pip or `uv tool` put in `~/.local/bin` is a script nothing
    /// verifies (D5.2): the update is handed out to copy, worded as such.
    /// Mutation: give a script the keg's one-click.
    @Test func aScriptPipxIsHandedOutToCopy() async throws {
        let host = try FakeHost(homebrew: false)
        let venv = "/ZZFixture-home/.local/share/uv/tools/pipx"
        host.links["/ZZFixture-home/.local/bin/pipx"] = venv + "/bin/pipx"
        host.directories[venv + "/lib"] = ["python3.12"]
        host.directories[venv + "/lib/python3.12/site-packages"] = ["pipx-1.18.4.dist-info"]
        let report = await Self.provider(host).check()
        let httpie = try #require(Self.status(report, "httpie"))
        #expect(httpie.state == .updateAvailable)
        #expect(httpie.oneClick == nil)
        #expect(httpie.withheld == .unverified)
        #expect(httpie.manualCommand?.arguments == ["upgrade", "httpie"])
        #expect(CLIToolsModelReason.of(httpie) == "pipx is a script, with no signature to check")
    }

    /// No pipx at all: rows are listed, nothing is offered.
    @Test func noPipxOffersNothing() async throws {
        let host = try FakeHost(homebrew: false)
        let report = await Self.provider(host).check()
        let httpie = try #require(Self.status(report, "httpie"))
        #expect(httpie.oneClick == nil)
        #expect(httpie.withheld == .updaterMissing)
    }

    /// A venv in the root this pipx would not pick by itself is upgraded with
    /// `PIPX_HOME` naming it, written into the command — the copy handed out
    /// acts on the same venv: with `~/.local/pipx` there, pipx ≥1.15.1 keeps
    /// using it, and a bare `pipx upgrade` of an Application Support venv
    /// says "not installed" (or moves the legacy one of that name).
    /// Mutation: never name the root; name it in the environment only.
    @Test func pipxHomeNamesARootPipxWouldNotPick() async throws {
        let host = try FakeHost()
        host.directories[Self.legacy] = ["venvs"]
        host.directories[Self.legacy + "/venvs"] = ["ruff"]
        host.files[Self.legacy + "/venvs/ruff/pipx_metadata.json"] = try Self.fixture("ruff-pipx_metadata-0.5.json")
        let adapter = Self.adapter(host)
        let scan = await adapter.scan()
        for item in scan.items where item.key == "ruff" {
            let root = try #require(scan.root(of: item))
            let upgrade = try #require(adapter.upgrade(item, root: root))
            #expect(upgrade.environment == [:])
            if item.root == Self.legacy {
                #expect(upgrade.command.executable == "/ZZFixture-brew/bin/pipx")
            } else {
                #expect(upgrade.command.executable == "/usr/bin/env")
                #expect(upgrade.command.arguments == ["PIPX_HOME=" + Self.modern, "/ZZFixture-brew/bin/pipx", "upgrade", "ruff"])
            }
        }
        // No legacy root: a 1.18 pipx's own default, nothing to name.
        let plain = try FakeHost()
        let plainAdapter = Self.adapter(plain)
        let plainScan = await plainAdapter.scan()
        let httpie = try #require(plainScan.items.first { $0.key == "httpie" })
        #expect(plainAdapter.upgrade(httpie, root: try #require(plainScan.root(of: httpie)))?.command.executable
            == "/ZZFixture-brew/bin/pipx")
    }

    /// A venv on pipx's uv backend finds uv on `PATH`: only a uv that may run
    /// is put there. Mutation: put `~/.local/bin` on PATH; use an unverified uv.
    @Test func aUvBackendVenvGetsOnlyAVerifiedUv() async throws {
        let host = try FakeHost()
        let venv = Self.modern + "/venvs/httpie/pipx_metadata.json"
        let original = try #require(host.files[venv])
        var json = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json["backend"] = "uv"
        host.files[venv] = try JSONSerialization.data(withJSONObject: json)
        host.verifiedUv = "/ZZFixture-home/.local/bin/uv"
        let withUv = Self.adapter(host)
        var scan = await withUv.scan()
        var item = try #require(scan.items.first { $0.key == "httpie" })
        #expect(withUv.upgrade(item, root: try #require(scan.root(of: item)))?.command.pathPrefix == "/ZZFixture-home/.local/bin")
        host.verifiedUv = nil
        scan = await withUv.scan()
        item = try #require(scan.items.first { $0.key == "httpie" })
        #expect(withUv.upgrade(item, root: try #require(scan.root(of: item)))?.command.pathPrefix == nil)
    }

    /// pipx's own rules beyond the pin, from 1.16–1.18's metadata: a venv
    /// from a lock file is left alone ("Not upgrading locked package"), one
    /// with its own index options is not asked of PyPI, a `--suffix` venv is
    /// asked by its package's name, and a cooldown holds the newest back.
    /// Mutation: ignore `lock_file`, `pip_args`, `package`, `cooldown_days`.
    @Test func lockIndexSuffixAndCooldownAreFollowed() async throws {
        let host = try FakeHost()
        let venvs = Self.modern + "/venvs"
        func edit(_ name: String, into target: String? = nil, _ change: (inout [String: Any]) -> Void) throws {
            let original = try #require(host.files[venvs + "/\(name)/pipx_metadata.json"])
            var json = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
            var main = try #require(json["main_package"] as? [String: Any])
            change(&main)
            json["main_package"] = main
            host.files[venvs + "/\(target ?? name)/pipx_metadata.json"] = try JSONSerialization.data(withJSONObject: json)
        }
        try edit("ruff") { $0["lock_file"] = ["path": "/ZZFixture-home/pylock.toml"] }
        try edit("httpie") { $0["pip_args"] = ["--index-url", "https://pypi.example.invalid/simple"] }
        try edit("cowsay", into: "cowsay-b") { $0["pinned"] = false; $0["package_or_url"] = "cowsay"; $0["cooldown_days"] = 1150 }
        host.directories[venvs] = ["cowsay-b", "httpie", "ruff"]
        var clocked = host.host
        clocked.now = { ISO8601DateFormatter().date(from: "2026-10-27T00:00:00Z")! }
        let report = await ManagedProvider(
            PipxAdapter(home: Self.home, host: clocked, homebrewRoots: ["/ZZFixture-brew"]), home: Self.home,
            proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { _, _, _, _, _ in ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: []) }).check()
        #expect(Self.status(report, "ruff")?.state == .unknown)
        #expect(Self.status(report, "ruff")?.withheld == .unsupportedInstaller)
        #expect(Self.status(report, "httpie")?.state == .unknown)
        let suffixed = try #require(Self.status(report, "cowsay-b"))
        // cowsay 5.0 was uploaded 2022-06-22, 6.0 2023-09-08: 1150 days back
        // from 2026-10-27 is 2023-09-03, before 6.0.
        #expect(suffixed.state == .upToDate)
        #expect(suffixed.latestVersion == "5.0")
        #expect(host.fetches == ["cowsay"])
    }

    /// The keg's `bin/pipx`, or the `libexec/bin/pipx` Homebrew's links it to,
    /// is a keg; any other file under it is not. Mutation: accept any depth;
    /// accept `bin/pipx` alone (Homebrew's real pipx resolves to `libexec`).
    @Test func theKegRuleIsTheKegsOwnPipx() throws {
        let host = try FakeHost()
        host.links["/ZZFixture-brew/bin/pipx"] = Self.keg + "/libexec/bin/pipx"
        #expect(Self.adapter(host).locateBinary()?.trust == .homebrewKeg)
        host.links["/ZZFixture-brew/bin/pipx"] = Self.keg + "/share/tools/pipx"
        #expect(Self.adapter(host).locateBinary() == nil)
    }

    /// A quarantined keg is not run.
    @Test func aQuarantinedKegIsNotRun() async throws {
        let host = try FakeHost()
        host.quarantined = [Self.keg + "/bin/pipx"]
        let report = await Self.provider(host).check()
        #expect(Self.status(report, "httpie")?.withheld == .unverified)
        #expect(Self.status(report, "httpie")?.managedItem?.binaryTrust == .quarantined)
    }

    @Test func indexRequirementsAreToldFromPathsAndURLs() {
        #expect(PipxMetadata.isIndexRequirement("httpie==3.2.1"))
        #expect(PipxMetadata.isIndexRequirement("black[d]>=23"))
        #expect(!PipxMetadata.isIndexRequirement("/ZZFixture-home/src/duolocal"))
        #expect(!PipxMetadata.isIndexRequirement("git+https://github.com/pypa/sampleproject"))
        #expect(!PipxMetadata.isIndexRequirement("sampleproject @ https://example.invalid/x.whl"))
        #expect(PipxMetadata.carriesSpecifier("httpie==3.2.1", package: "httpie"))
        #expect(!PipxMetadata.carriesSpecifier("httpie", package: "httpie"))
    }
}

/// The app's reason for a withheld row, as the pane and `duo` word it.
enum CLIToolsModelReason {
    static func of(_ status: CLIToolStatus) -> String? {
        status.withheld.map { CLIToolWording.reason($0, of: status) }
    }
}
