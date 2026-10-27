import Foundation
import Testing
@testable import DuoUpdaterCore

/// uv's tools as managed rows (`UvToolAdapter`, design §4.2), driven by uv's
/// own files and output: the fixtures in `Fixtures/managed/uv-tool/` are what
/// uv 0.13.4 wrote and printed on 2026-10-27 in an isolated home after
/// `uv tool install 'ruff==0.6.0'`, `'black>=23,<24'` and `'cowsay==5.0'` on
/// Python 3.9.6, with the home rewritten to `/ZZFixture-home`. cowsay's
/// receipt then had its `specifier` removed by hand — the receipt an unpinned
/// `uv tool install cowsay` writes, held at an old version — and uv read it
/// as such (`outdated.txt`, `upgrade-cowsay.stderr.txt`: "Updated cowsay v5.0
/// -> v6.1").
///
/// The host is scripted (`FakeHost`): nothing here lists the real home, runs
/// uv or reaches the network. Each case names the mutation it fails under.
struct UvToolAdapterTests {

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let tools = "/ZZFixture-home/.local/share/uv/tools"
    static let uv = "/ZZFixture-home/.local/bin/uv"

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/uv-tool/\(name)"))
    }

    static func pipxFixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/pipx/\(name)"))
    }

    final class FakeHost: @unchecked Sendable {
        let lock = NSLock()
        var install: UvInstall? = UvInstall(
            path: UvToolAdapterTests.uv, executable: UvToolAdapterTests.uv, version: nil, signature: .vendor)
        var binaryVersion: String? = "0.13.4"
        var files: [String: Data] = [:]
        var directories: [String: [String]] = [:]
        var outdated: UvToolAdapter.Output?
        var pypi: [String: Data] = [:]
        var processes: [NpmActivity.Process] = []
        private var _runs: [(arguments: [String], environment: [String: String])] = []
        private var _fetches: [String] = []
        var runs: [(arguments: [String], environment: [String: String])] { lock.withLock { _runs } }
        var fetches: [String] { lock.withLock { _fetches } }

        init() throws {
            let tools = UvToolAdapterTests.tools
            directories[tools] = [".gitignore", ".lock", "black", "cowsay", "ruff"]
            for (tool, version, extra) in [
                ("ruff", "0.6.0", [String]()), ("black", "23.12.1", ["click-8.1.8.dist-info", "packaging-26.3.dist-info"]),
                ("cowsay", "5.0", []),
            ] {
                files[tools + "/\(tool)/uv-receipt.toml"] = try UvToolAdapterTests.fixture("\(tool)-uv-receipt.toml")
                files[tools + "/\(tool)/pyvenv.cfg"] = try UvToolAdapterTests.fixture("pyvenv.cfg")
                directories[tools + "/\(tool)/lib"] = ["python3.9"]
                directories[tools + "/\(tool)/lib/python3.9/site-packages"] = ["\(tool)-\(version).dist-info"] + extra
            }
            files[tools + "/black/lib/python3.9/site-packages/black-23.12.1.dist-info/METADATA"] =
                try UvToolAdapterTests.fixture("black-METADATA")
            outdated = UvToolAdapter.Output(stdout: try UvToolAdapterTests.fixture("outdated.txt"))
        }

        /// The venv after `uv tool upgrade`: the old dist-info gone, the new one there.
        func upgrade(_ tool: String, from old: String, to new: String) {
            lock.withLock {
                let key = UvToolAdapterTests.tools + "/\(tool)/lib/python3.9/site-packages"
                directories[key] = (directories[key] ?? []).map { $0 == "\(tool)-\(old).dist-info" ? "\(tool)-\(new).dist-info" : $0 }
            }
        }

        var host: UvToolAdapter.Host {
            UvToolAdapter.Host(
                binary: { self.lock.withLock { self.install } },
                version: { _ in self.binaryVersion },
                contents: { path in self.lock.withLock { self.files[path] } },
                directories: { path in self.lock.withLock { self.directories[path] } },
                modified: { _ in Date(timeIntervalSince1970: 1_792_750_000) },
                run: { executable, arguments, environment in
                    #expect(executable == UvToolAdapterTests.uv)
                    return self.lock.withLock {
                        self._runs.append((arguments, environment))
                        return self.outdated
                    }
                },
                pypi: { project in
                    try self.lock.withLock {
                        self._fetches.append(project)
                        guard let data = self.pypi[project] else { throw PyPIProject.Failure.http(404) }
                        return data
                    }
                },
                proxyEnvironment: { ["https_proxy": "http://zz.invalid:3128"] },
                processes: { self.processes })
        }
    }

    actor Runs {
        private(set) var commands: [CLIToolCommand] = []
        private(set) var environments: [[String: String]] = []
        func record(_ command: CLIToolCommand, _ environment: [String: String]) {
            commands.append(command)
            environments.append(environment)
        }
    }

    static func provider(_ host: FakeHost, runs: Runs = Runs(), afterRun: @escaping @Sendable () -> Void = {}) -> ManagedProvider {
        ManagedProvider(
            UvToolAdapter(home: home, host: host.host), home: home,
            proxyEnvironment: { ["https_proxy": "http://zz.invalid:3128"] },
            processes: { [] }, token: { nil },
            runner: { command, environment, _, _, _ in
                await runs.record(command, environment)
                afterRun()
                return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: [])
            })
    }

    static func status(_ report: CLIToolReport, _ key: String) -> CLIToolStatus? {
        report.statuses.first { $0.managedItem?.key == key }
    }

    // MARK: scan

    /// One row per tool directory with a receipt, its request from the
    /// receipt, its version from the venv's dist-info — never a dependency's
    /// (black's venv holds click 8.1.8). Mutation: read requirements[0]
    /// blindly; take the first dist-info in site-packages.
    @Test func theScanReadsReceiptsAndDistInfo() async throws {
        let host = try FakeHost()
        let scan = await UvToolAdapter(home: Self.home, host: host.host).scan()
        #expect(scan.items.map(\.key) == ["black", "cowsay", "ruff"])
        let black = try #require(scan.items.first { $0.key == "black" })
        #expect(black.installed == "23.12.1")
        #expect(black.request == ManagedItem.Request(kind: .range, spelled: ">=23,<24"))
        #expect(black.facts.contains(.python("3.9.6")))
        #expect(black.notes == .gitHubReleases(owner: "psf", repo: "black", tagPrefix: ""))
        let ruff = try #require(scan.items.first { $0.key == "ruff" })
        #expect(ruff.request == ManagedItem.Request(kind: .exact, spelled: "==0.6.0"))
        let cowsay = try #require(scan.items.first { $0.key == "cowsay" })
        #expect(cowsay.request == nil)
        #expect(cowsay.installed == "5.0")
        #expect(scan.roots == [ManagedRoot(
            manager: UvToolAdapter.id, path: Self.tools,
            binary: ManagedRoot.Binary(path: Self.uv, version: nil, trust: .vendorSigned(team: UvScanner.teamIdentifier)))])
        #expect(host.runs.isEmpty)
    }

    /// §10's "no `ChildProcess` in any adapter's scan", read from the source.
    /// Mutation: call `host.run`, `host.version` or `ChildProcess` from `scan()`.
    @Test func theScanSourceNamesNoSpawn() throws {
        for (file, function) in [
            ("Uv/UvToolAdapter.swift", "public func scan() async -> ManagedScan {"),
            ("Uv/UvPythonAdapter.swift", "public func scan() async -> ManagedScan {"),
            ("Pipx/PipxAdapter.swift", "public func scan() async -> ManagedScan {"),
            ("Pipx/PipxAdapter.swift", "func locateBinary() -> ManagedRoot.Binary? {"),
        ] {
            let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Sources/DuoUpdaterCore/CLITools/Managed/\(file)"), encoding: .utf8)
            let start = try #require(source.range(of: function))
            var depth = 0
            var end = start.upperBound
            for index in source[start.lowerBound...].indices {
                if source[index] == "{" { depth += 1 }
                if source[index] == "}" {
                    depth -= 1
                    if depth == 0 { end = index; break }
                }
            }
            let body = source[start.upperBound..<end]
            #expect(!body.isEmpty)
            for spawn in ["ChildProcess", "host.run", "host.version", "runVersion", "Process(", "host.pypi"] {
                #expect(!body.contains(spawn), "\(file): \(function) names \(spawn)")
            }
        }
        // The scan's binaries are read with no version run: `UvScanner`'s
        // default reader spawns `uv --version`.
        let uv = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/DuoUpdaterCore/CLITools/Managed/Uv/UvToolAdapter.swift"), encoding: .utf8)
        #expect(uv.contains("binary: { await UvScanner(home: home, readVersion: { _ in nil }).scan().first }"))
        let pipx = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/DuoUpdaterCore/CLITools/Managed/Pipx/PipxAdapter.swift"), encoding: .utf8)
        #expect(pipx.contains("UvScanner(home: home, readVersion: { _ in nil }).locate()"))
    }

    // MARK: check

    /// §8.1's P2 rows from uv's own `--outdated`: cowsay (no specifier) is
    /// offered 5.0 → 6.1 with `uv tool upgrade cowsay`; ruff (`==0.6.0`) is
    /// pinned at 0.17.2 with `uv tool install ruff@latest` to copy; black
    /// (`>=23,<24`) is reported, not offered (D9). Mutation: offer a `.pinned`
    /// row; treat a range as unpinned; parse `- black` as a tool.
    @Test func theRowsFollowEachRequest() async throws {
        let host = try FakeHost()
        let report = await Self.provider(host).check()
        #expect(report.statuses.map { $0.managedItem?.key } == ["black", "cowsay", "ruff"])

        let cowsay = try #require(Self.status(report, "cowsay"))
        #expect(cowsay.state == .updateAvailable)
        #expect(cowsay.latestVersion == "6.1")
        #expect(cowsay.oneClick == CLIToolCommand(
            executable: Self.uv, arguments: ["tool", "upgrade", "cowsay"], pathPrefix: "/ZZFixture-home/.local/bin"))
        #expect(cowsay.identity == "uv-tool|\(Self.tools)|cowsay")

        let ruff = try #require(Self.status(report, "ruff"))
        #expect(ruff.state == .pinned)
        #expect(ruff.latestVersion == "0.17.2")
        #expect(ruff.oneClick == nil)
        #expect(ruff.manualCommand == CLIToolCommand(executable: Self.uv, arguments: ["tool", "install", "ruff@latest"], pathPrefix: nil))

        let black = try #require(Self.status(report, "black"))
        #expect(black.state == .unknown)
        #expect(black.oneClick == nil)
        #expect(black.withheld == .unsupportedInstaller)

        #expect(host.runs.map(\.arguments) == [["tool", "list", "--outdated"]])
        #expect(host.fetches.isEmpty)
    }

    /// The check's uv runs with an environment built from scratch: a terminal
    /// `duo`'s `UV_*` would change what it reads. Mutation: hand
    /// `ProcessInfo.processInfo.environment` on.
    @Test func theCheckRunsUvWithABuiltEnvironment() async throws {
        let host = try FakeHost()
        _ = await Self.provider(host).check()
        let environment = try #require(host.runs.first?.environment)
        #expect(Set(environment.keys) == ["HOME", "PATH", "NO_COLOR", "https_proxy"])
        #expect(environment["HOME"] == "/ZZFixture-home")
        #expect(environment["PATH"] == "/ZZFixture-home/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    /// Offline, uv exits 2 with nothing on stdout (`outdated-offline.stderr.txt`):
    /// every row unknown, none current. Mutation: read an empty stdout as
    /// "nothing outdated" whatever the exit.
    @Test func anOfflineCheckLeavesEveryRowUnknown() async throws {
        let host = try FakeHost()
        host.outdated = UvToolAdapter.Output(stdout: Data(), exitStatus: 2)
        let report = await Self.provider(host).check()
        #expect(report.statuses.count == 3)
        for status in report.statuses {
            #expect(status.state == .unknown)
            #expect(status.withheld == .channelUnreadable)
        }
    }

    /// A tool `--outdated` leaves out with nothing said about it is current at
    /// its installed version.
    @Test func aToolOutdatedLeavesOutIsCurrent() async throws {
        let host = try FakeHost()
        host.outdated = UvToolAdapter.Output(stdout: Data("ruff v0.6.0 [latest: 0.17.2]\n- ruff\n".utf8))
        let report = await Self.provider(host).check()
        let cowsay = try #require(Self.status(report, "cowsay"))
        #expect(cowsay.state == .upToDate)
        #expect(cowsay.latestVersion == "5.0")
    }

    /// uv also leaves a tool out when it could not read it — "Tool `cowsay`
    /// environment not found" on stderr, exit 0 (its interpreter gone) — when
    /// its version is a pre-release (`latest.rs` takes none), and when its
    /// config says `offline = true` (an empty list, exit 0). None of those is
    /// current. Mutation: read every left-out tool as current.
    @Test func aToolLeftOutForAReasonIsNotCurrent() async throws {
        let host = try FakeHost()
        host.outdated = UvToolAdapter.Output(
            stdout: Data("ruff v0.6.0 [latest: 0.17.2]\n- ruff\n".utf8),
            stderr: Data("warning: Tool `cowsay` environment not found (run `uv tool install cowsay --reinstall` to reinstall)\n".utf8))
        var report = await Self.provider(host).check()
        #expect(Self.status(report, "cowsay")?.state == .unknown)
        #expect(Self.status(report, "cowsay")?.withheld == .channelUnreadable)

        host.outdated = UvToolAdapter.Output(stdout: Data())
        host.files["/ZZFixture-home/.config/uv/uv.toml"] = Data("offline = true\n".utf8)
        report = await Self.provider(host).check()
        #expect(report.statuses.allSatisfy { $0.state == .unknown })

        host.files["/ZZFixture-home/.config/uv/uv.toml"] = nil
        host.upgrade("cowsay", from: "5.0", to: "6.2b1")
        report = await Self.provider(host).check()
        #expect(Self.status(report, "cowsay")?.state == .unknown)
        #expect(Self.status(report, "ruff")?.state == .upToDate)
    }

    /// A tool from a local wheel, a directory, a URL or git: its receipt
    /// names the source and `--outdated` still prints PyPI's latest for the
    /// name, but `uv tool upgrade` rebuilds from the source ("Nothing to
    /// upgrade"). Reported, never offered. Mutation: offer PyPI's latest.
    @Test func aToolFromALocalSourceIsNotOnAnIndex() async throws {
        let host = try FakeHost()
        host.files[Self.tools + "/cowsay/uv-receipt.toml"] = Data(
            "[tool]\nrequirements = [{ name = \"cowsay\", path = \"/ZZFixture-home/cowsay-0.0.1-py3-none-any.whl\" }]\n".utf8)
        let report = await Self.provider(host).check()
        let cowsay = try #require(Self.status(report, "cowsay"))
        #expect(cowsay.state == .unknown)
        #expect(cowsay.oneClick == nil)
        #expect(cowsay.withheld == .unsupportedInstaller)
    }

    /// `uv tool install cowsay -c c.txt` (`cowsay<6`): `uv tool upgrade`
    /// resolves inside the constraint, so the tool is held like a range (D9).
    /// Mutation: read `requirements` alone.
    @Test func aConstraintNarrowsTheRequest() async throws {
        let host = try FakeHost()
        host.files[Self.tools + "/cowsay/uv-receipt.toml"] = Data("""
            [tool]
            requirements = [{ name = "cowsay" }]
            constraints = [{ name = "cowsay", specifier = "<6" }]
            """.utf8)
        let report = await Self.provider(host).check()
        let cowsay = try #require(Self.status(report, "cowsay"))
        #expect(cowsay.managedItem?.request == ManagedItem.Request(kind: .range, spelled: "<6"))
        #expect(cowsay.oneClick == nil)
    }

    /// A pin held below a post-release is pinned, not ahead: PEP 440 has
    /// `1.0.post1` above `1.0`, which `VersionComparator` reads the other way.
    /// Mutation: order the managed Python rows with `VersionComparator`.
    @Test func aPostReleaseIsNewerThanThePin() async throws {
        let host = try FakeHost()
        host.files[Self.tools + "/ruff/uv-receipt.toml"] = Data("[tool]\nrequirements = [{ name = \"ruff\", specifier = \"==0.6.0\" }]\n".utf8)
        host.outdated = UvToolAdapter.Output(stdout: Data("ruff v0.6.0 [latest: 0.6.0.post1]\n- ruff\n".utf8))
        let report = await Self.provider(host).check()
        #expect(Self.status(report, "ruff")?.state == .pinned)
        #expect(Self.status(report, "ruff")?.latestVersion == "0.6.0.post1")
    }

    /// Below 0.11.0 `--outdated` is not read — 0.10.10–0.10.12 had it, but
    /// asked for no Python of the tool's — so each tool is asked of PyPI for
    /// its venv's Python. black's newest is 26.10.1, which needs Python ≥3.10;
    /// on 3.9.6 the newest it can get is 25.11.0 — what uv's own `--outdated`
    /// printed too. Mutation: take `info.version` without its
    /// `requires_python`; spawn uv anyway.
    @Test func anOldUvIsAnsweredFromPyPIForTheVenvsPython() async throws {
        let host = try FakeHost()
        host.binaryVersion = "0.10.12"
        host.pypi = [
            "black": try Self.pipxFixture("pypi-black-trimmed.json"),
            "cowsay": try Self.pipxFixture("pypi-cowsay.json"),
        ]
        let report = await Self.provider(host).check()
        #expect(host.runs.isEmpty)
        #expect(Set(host.fetches) == ["black", "cowsay", "ruff"])
        #expect(Self.status(report, "black")?.latestVersion == "25.11.0")
        let cowsay = try #require(Self.status(report, "cowsay"))
        #expect(cowsay.state == .updateAvailable)
        #expect(cowsay.latestVersion == "6.1")
        // ruff's document was not served: its row says why, the others stand.
        #expect(Self.status(report, "ruff")?.withheld == .channelUnreadable)
    }

    /// An unsigned uv no hash vouched for is never run: the check goes to PyPI
    /// and the update is handed out to copy. Mutation: run an untrusted binary.
    @Test func anUntrustedUvIsNeverRun() async throws {
        let host = try FakeHost()
        host.install = UvInstall(path: Self.uv, executable: Self.uv, version: "0.13.4", signature: .adHoc)
        host.pypi = ["cowsay": try Self.pipxFixture("pypi-cowsay.json")]
        let report = await Self.provider(host).check()
        #expect(host.runs.isEmpty)
        let cowsay = try #require(Self.status(report, "cowsay"))
        #expect(cowsay.state == .updateAvailable)
        #expect(cowsay.oneClick == nil)
        #expect(cowsay.withheld == .unverified)
        #expect(cowsay.manualCommand?.arguments == ["tool", "upgrade", "cowsay"])
    }

    // MARK: update

    /// The click runs `uv tool upgrade cowsay` and nothing else, and reads the
    /// version back from the venv. Mutation: pass a flag (it persists into the
    /// receipt, UV-17); report the checked version instead of the re-read one.
    @Test func theClickUpgradesAndRereadsTheVenv() async throws {
        let host = try FakeHost()
        let runs = Runs()
        let provider = Self.provider(host, runs: runs) { host.upgrade("cowsay", from: "5.0", to: "6.1") }
        let report = await provider.check()
        let cowsay = try #require(Self.status(report, "cowsay"))
        let outcome = await provider.update(cowsay) { _ in }
        #expect(outcome == .updated(version: "6.1"))
        #expect(await runs.commands.map(\.arguments) == [["tool", "upgrade", "cowsay"]])
        #expect(await runs.environments.first?["HOME"] == "/ZZFixture-home")
    }

    /// uv's "Nothing to upgrade" exits 0: a run that left the venv where it was
    /// is not an update (`ManagedProvider.update`).
    @Test func anUpgradeThatMovedNothingIsNotUpdated() async throws {
        let host = try FakeHost()
        let provider = Self.provider(host)
        let report = await provider.check()
        let cowsay = try #require(Self.status(report, "cowsay"))
        guard case .failed(let message, _) = await provider.update(cowsay, progress: { _ in }) else {
            Issue.record("an upgrade that moved nothing was reported as done")
            return
        }
        #expect(message.hasPrefix("not updated: cowsay is still 5.0"))
    }

    /// A `uv tool upgrade` already running from this uv makes the row busy.
    @Test func aRunningUvToolUpgradeMakesTheRowsBusy() async throws {
        let host = try FakeHost()
        host.processes = [NpmActivity.Process(pid: 4242, arguments: [Self.uv, "tool", "upgrade", "ruff"], executable: Self.uv)]
        let report = await Self.provider(host).check()
        let cowsay = try #require(Self.status(report, "cowsay"))
        #expect(cowsay.oneClick == nil)
        #expect(cowsay.withheld == .busy)
        #expect(cowsay.note == "uv tool upgrade is running (pid 4242)")
    }

    // MARK: parsing

    @Test func theOutdatedParserSkipsExecutableLines() throws {
        let parsed = UvToolOutdated.parse(try Self.fixture("outdated.txt"))
        #expect(parsed.keys.sorted() == ["black", "cowsay", "ruff"])
        #expect(parsed["black"]?.latest == "25.11.0")
        #expect(parsed["blackd"] == nil)
    }

    @Test func receiptsReadTheirRequestsAndOptions() throws {
        let receipt = try #require(UvToolReceipt.parse(Data("""
            [tool]
            requirements = [
                { name = "httpie", extras = ["socks"] },
                { name = "Black", specifier = "~=24.1", marker = "python_version >= '3.9'" },
            ]
            python = "3.12"

            [tool.options]
            exclude-newer = "2024-03-25"
            """.utf8), tool: "black"))
        #expect(receipt.requirement.name == "Black")
        #expect(receipt.requirement.specifier == "~=24.1")
        #expect(receipt.request == ManagedItem.Request(kind: .range, spelled: "~=24.1"))
        #expect(receipt.excludeNewer == "2024-03-25")
        #expect(receipt.python == "3.12")
        #expect(receipt.excludeNewerDate == ISO8601DateFormatter().date(from: "2024-03-25T23:59:59Z"))
        #expect(UvToolReceipt.parse(Data("[tool]\nrequirements = [{ name = \"ruff\", specifier = \"==1.*\" }]".utf8), tool: "ruff")?
            .request?.kind == .range)
        // uv 0.2.20–0.2.31's PEP 508 strings, which 0.13.4 still reads.
        let old = try #require(UvToolReceipt.parse(Data("[tool]\nrequirements = [\"cowsay==5.0\"]\n".utf8), tool: "cowsay"))
        #expect(old.request == ManagedItem.Request(kind: .exact, spelled: "==5.0"))
        // `--exclude-newer P1100D` writes fractional seconds.
        #expect(UvToolReceipt.date(excludeNewer: "2023-10-22T17:16:21.688846Z")
            == ISO8601DateFormatter().date(from: "2023-10-22T17:16:21Z"))
    }
}
