import Foundation
import Testing
@testable import DuoUpdaterCore

/// uv's Pythons as managed lines (`UvPythonAdapter`, design §4.3), driven by
/// uv's own layout and output: the fixtures in `Fixtures/managed/uv-python/`
/// are what uv 0.13.4 printed on 2026-10-27 for `uv python list <line>
/// --only-downloads --output-format json` in an isolated
/// `UV_PYTHON_INSTALL_DIR`, after `uv python install 3.12.5` and
/// `3.13.9+freethreaded`. The directory names below are the ones uv made there.
///
/// The host is scripted (`FakeHost`): nothing here lists the real home, runs
/// uv or reaches the network. Each case names the mutation it fails under.
struct UvPythonAdapterTests {

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let root = "/ZZFixture-home/.local/share/uv/python"
    static let uv = "/ZZFixture-home/.local/bin/uv"
    static let line312 = "cpython-3.12-macos-aarch64-none"
    static let line313t = "cpython-3.13+freethreaded-macos-aarch64-none"

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/uv-python/\(name)"))
    }

    final class FakeHost: @unchecked Sendable {
        let lock = NSLock()
        var install: UvInstall? = UvInstall(
            path: UvPythonAdapterTests.uv, executable: UvPythonAdapterTests.uv, version: nil, signature: .vendor)
        var homebrew: ManagedRoot.Binary?
        var executable = UvPythonAdapterTests.uv
        var binaryVersion: String? = "0.13.4"
        var entries: [String] = [
            ".gitignore", ".lock",
            ".temp",
            "cpython-3.12-macos-aarch64-none",
            "cpython-3.12.5-macos-aarch64-none",
            "cpython-3.12.3-macos-aarch64-none",
            "cpython-3.13+freethreaded-macos-aarch64-none",
            "cpython-3.13.9+freethreaded-macos-aarch64-none",
            "cpython-3.15.0rc1-macos-aarch64-none",
            "pypy-3.11.13-macos-aarch64-none",
        ]
        var interpreters: Set<String> = [
            "cpython-3.12.5-macos-aarch64-none", "cpython-3.12.3-macos-aarch64-none",
            "cpython-3.13.9+freethreaded-macos-aarch64-none",
        ]
        var downloads: [String: Data] = [:]
        var processes: [NpmActivity.Process] = []
        private var _runs: [(arguments: [String], environment: [String: String])] = []
        var runs: [(arguments: [String], environment: [String: String])] { lock.withLock { _runs } }

        init() throws {
            downloads[UvPythonAdapterTests.line312] = try UvPythonAdapterTests.fixture("downloads-3.12.json")
            downloads[UvPythonAdapterTests.line313t] = try UvPythonAdapterTests.fixture("downloads-3.13t.json")
        }

        /// The directory after `uv python upgrade`: the new patch beside the old.
        func install(_ name: String) {
            lock.withLock {
                entries.append(name)
                interpreters.insert(name)
            }
        }

        var host: UvPythonAdapter.Host {
            UvPythonAdapter.Host(
                binary: { self.lock.withLock { self.install } },
                homebrewBinary: { self.lock.withLock { self.homebrew } },
                version: { _ in self.binaryVersion },
                directories: { path in
                    self.lock.withLock { path == UvPythonAdapterTests.root ? self.entries : nil }
                },
                exists: { path in
                    self.lock.withLock {
                        let prefix = UvPythonAdapterTests.root + "/"
                        guard path.hasPrefix(prefix), path.hasSuffix("/bin/python3") else { return false }
                        let name = path.dropFirst(prefix.count).dropLast("/bin/python3".count)
                        return self.interpreters.contains(String(name))
                    }
                },
                run: { executable, arguments, environment in
                    #expect(executable == self.lock.withLock { self.executable })
                    return self.lock.withLock {
                        self._runs.append((arguments, environment))
                        return arguments.count > 2 ? self.downloads[arguments[2]] : nil
                    }
                },
                proxyEnvironment: { ["https_proxy": "http://zz.invalid:3128"] },
                processes: { self.processes })
        }
    }

    actor Runs {
        private(set) var commands: [CLIToolCommand] = []
        func record(_ command: CLIToolCommand) { commands.append(command) }
    }

    static func provider(_ host: FakeHost, runs: Runs = Runs(), afterRun: @escaping @Sendable () -> Void = {}) -> ManagedProvider {
        ManagedProvider(
            UvPythonAdapter(home: home, host: host.host), home: home,
            proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { command, _, _, _, _ in
                await runs.record(command)
                afterRun()
                return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: [])
            })
    }

    static func status(_ report: CLIToolReport, _ key: String) -> CLIToolStatus? {
        report.statuses.first { $0.managedItem?.key == key }
    }

    // MARK: scan

    /// One row per line, at its newest patch, older patches beside it; the
    /// minor's link is not a patch, and a pre-release, PyPy, or uv's own
    /// files make no row. Mutation: count the link as a patch; take the
    /// first directory instead of the newest; let `3.15.0rc1` or `pypy` in.
    @Test func theScanMakesOneRowPerLine() async throws {
        let host = try FakeHost()
        let scan = await UvPythonAdapter(home: Self.home, host: host.host).scan()
        #expect(scan.items.map(\.key) == [Self.line312, Self.line313t])
        let py312 = try #require(scan.items.first)
        #expect(py312.name == "Python 3.12")
        #expect(py312.shape == .line)
        #expect(py312.installed == "3.12.5")
        #expect(py312.alsoInstalled == ["3.12.3"])
        #expect(py312.installPath == Self.root + "/cpython-3.12.5-macos-aarch64-none")
        #expect(py312.effects == [.oldKept(for: nil)])
        #expect(scan.items[1].name == "Python 3.13+freethreaded")
        #expect(scan.items[1].installed == "3.13.9")
        #expect(scan.roots == [ManagedRoot(
            manager: UvPythonAdapter.id, path: Self.root,
            binary: ManagedRoot.Binary(path: Self.uv, version: nil, trust: .vendorSigned(team: UvScanner.teamIdentifier)))])
        #expect(host.runs.isEmpty)
    }

    /// A patch directory uv is still writing has no interpreter: its version
    /// is not read as installed. Mutation: trust the directory name alone.
    @Test func aPatchWithoutItsInterpreterIsUnreadable() async throws {
        let host = try FakeHost()
        host.interpreters.remove("cpython-3.13.9+freethreaded-macos-aarch64-none")
        let report = await Self.provider(host).check()
        let row = try #require(Self.status(report, Self.line313t))
        #expect(row.state == .unknown)
        #expect(row.withheld == .versionUnreadable)
        #expect(!host.runs.contains { $0.arguments.contains(Self.line313t) })
    }

    // MARK: check

    /// 3.12.5 → 3.12.15 offered with `uv python upgrade <line>`, asked of uv's
    /// list by the line's own key, from an environment built from scratch;
    /// the free-threaded line reads its own builds (3.13.16). Mutation: ask
    /// `uv python list 3.12` (PyPy and GraalPy answer too); take the first
    /// download instead of the line's; pass the inherited environment.
    @Test func eachLineIsAskedOfUvsOwnList() async throws {
        let host = try FakeHost()
        let report = await Self.provider(host).check()
        #expect(host.runs.map(\.arguments) == [
            ["python", "list", Self.line312, "--only-downloads", "--output-format", "json"],
            ["python", "list", Self.line313t, "--only-downloads", "--output-format", "json"],
        ])
        let environment = try #require(host.runs.first?.environment)
        #expect(environment["HOME"] == "/ZZFixture-home")
        #expect(environment["https_proxy"] == "http://zz.invalid:3128")
        #expect(!environment.keys.contains { $0.hasPrefix("UV_") })

        let py312 = try #require(Self.status(report, Self.line312))
        #expect(py312.state == .updateAvailable)
        #expect(py312.installedVersion == "3.12.5")
        #expect(py312.latestVersion == "3.12.15")
        #expect(py312.oneClick?.arguments == ["python", "upgrade", Self.line312])
        #expect(py312.managedItem?.facts.contains(.asKnownBy("uv 0.13.4")) == true)
        let py313t = try #require(Self.status(report, Self.line313t))
        #expect(py313t.latestVersion == "3.13.16")
    }

    /// At the newest uv knows, the line is current; uv listing nothing newer
    /// for it is current too, as known by that uv. Mutation: read an empty
    /// list as unreadable.
    @Test func aLineAtUvsNewestIsCurrent() async throws {
        let host = try FakeHost()
        host.downloads[Self.line313t] = Data("[]".utf8)
        host.install("cpython-3.12.15-macos-aarch64-none")
        let report = await Self.provider(host).check()
        let py312 = try #require(Self.status(report, Self.line312))
        #expect(py312.state == .upToDate)
        #expect(py312.installedVersion == "3.12.15")
        #expect(py312.managedItem?.alsoInstalled == ["3.12.5", "3.12.3"])
        #expect(try #require(Self.status(report, Self.line313t)).state == .upToDate)
    }

    /// A uv that did not answer leaves the line unknown, never current.
    /// Mutation: map a failed run to an empty list.
    @Test func aFailedListIsNotCurrent() async throws {
        let host = try FakeHost()
        host.downloads = [:]
        let report = await Self.provider(host).check()
        let py312 = try #require(Self.status(report, Self.line312))
        #expect(py312.state == .unknown)
        #expect(py312.withheld == .channelUnreadable)
    }

    /// An ad hoc signed uv is never run: no list, no one-click. Mutation: run
    /// the binary before the trust gate.
    @Test func anUntrustedUvIsNeverRun() async throws {
        let host = try FakeHost()
        host.install = UvInstall(path: Self.uv, executable: Self.uv, version: "0.13.4", signature: .adHoc)
        let report = await Self.provider(host).check()
        #expect(host.runs.isEmpty)
        let py312 = try #require(Self.status(report, Self.line312))
        #expect(py312.state == .unknown)
        #expect(py312.withheld == .unverified)
        #expect(py312.oneClick == nil)
    }

    /// Homebrew's uv runs the lines when there is no standalone uv — the
    /// Homebrew-only Mac that used to see only "program was not found".
    /// Mutation: keep the binary from `UvScanner` alone.
    @Test func aHomebrewUvRunsTheLinesWhenNoStandaloneUvExists() async throws {
        let host = try FakeHost()
        host.install = nil
        host.homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/uv", version: "0.13.6", trust: .homebrewKeg)
        host.executable = "/opt/homebrew/bin/uv"
        let report = await Self.provider(host).check()
        let py312 = try #require(Self.status(report, Self.line312))
        #expect(py312.state == .updateAvailable)
        #expect(py312.oneClick?.executable == "/opt/homebrew/bin/uv")
        #expect(py312.oneClick?.arguments == ["python", "upgrade", Self.line312])
        #expect(py312.managedItem?.facts.contains(.asKnownBy("uv 0.13.6")) == true)
        #expect(host.runs.map(\.arguments) == [
            ["python", "list", Self.line312, "--only-downloads", "--output-format", "json"],
            ["python", "list", Self.line313t, "--only-downloads", "--output-format", "json"],
        ])
    }

    /// A runnable standalone uv still wins when Homebrew's is also there: it is
    /// the copy `uv self update` owns. Mutation: prefer Homebrew whenever found.
    @Test func aRunnableStandaloneUvIsPreferredOverHomebrew() async throws {
        let host = try FakeHost()
        host.homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/uv", version: "0.13.6", trust: .homebrewKeg)
        let scan = await UvPythonAdapter(home: Self.home, host: host.host).scan()
        #expect(scan.roots.first?.binary?.path == Self.uv)
        #expect(scan.roots.first?.binary?.trust == .vendorSigned(team: UvScanner.teamIdentifier))
    }

    /// A standalone uv that may not run does not shadow a Homebrew uv that may.
    /// Mutation: stop at the first `UvScanner` install whatever its trust.
    @Test func aHomebrewUvRunsWhenTheStandaloneUvCannot() async throws {
        let host = try FakeHost()
        host.install = UvInstall(path: Self.uv, executable: Self.uv, version: "0.13.4", signature: .adHoc)
        host.homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/uv", version: "0.13.6", trust: .homebrewKeg)
        host.executable = "/opt/homebrew/bin/uv"
        let report = await Self.provider(host).check()
        let py312 = try #require(Self.status(report, Self.line312))
        #expect(py312.state == .updateAvailable)
        #expect(py312.oneClick?.executable == "/opt/homebrew/bin/uv")
        #expect(host.runs.count == 2)
    }

    /// A uv older than 0.7.14 has no `python upgrade`: the newer patch is
    /// reported, not offered. Mutation: offer the command whatever the version.
    @Test func aUvWithoutPythonUpgradeIsNotOffered() async throws {
        let host = try FakeHost()
        host.binaryVersion = "0.7.13"
        let report = await Self.provider(host).check()
        let py312 = try #require(Self.status(report, Self.line312))
        #expect(py312.state == .updateAvailable)
        #expect(py312.oneClick == nil)
        #expect(py312.withheld == .unsupportedInstaller)
    }

    // MARK: update

    /// The click runs `uv python upgrade <line>` and nothing else, and reads
    /// the line's newest patch back from disk. Mutation: pass `--reinstall`;
    /// report the checked version.
    @Test func theClickUpgradesTheLineAndRereadsIt() async throws {
        let host = try FakeHost()
        let runs = Runs()
        let provider = Self.provider(host, runs: runs) { host.install("cpython-3.12.15-macos-aarch64-none") }
        let report = await provider.check()
        let py312 = try #require(Self.status(report, Self.line312))
        let outcome = await provider.update(py312) { _ in }
        #expect(outcome == .updated(version: "3.12.15"))
        #expect(await runs.commands.map(\.arguments) == [["python", "upgrade", Self.line312]])
    }

    /// A `uv python install` already running from this uv makes the rows busy.
    @Test func aRunningUvPythonInstallMakesTheRowsBusy() async throws {
        let host = try FakeHost()
        host.processes = [NpmActivity.Process(pid: 4343, arguments: [Self.uv, "python", "install", "3.14"], executable: Self.uv)]
        let report = await Self.provider(host).check()
        let py312 = try #require(Self.status(report, Self.line312))
        #expect(py312.oneClick == nil)
        #expect(py312.withheld == .busy)
        #expect(py312.note == "uv python install is running (pid 4343)")
    }

    // MARK: parsing

    /// Only the line's own builds count: a list naming another platform's or
    /// PyPy's newer build (made up here — uv's answer to a line's full key
    /// held none) leaves the line's newest as it is. Mutation: take the
    /// newest of the whole list.
    @Test func onlyTheLinesOwnBuildsCount() {
        let list = Data("""
            [{"key":"cpython-3.12.15-macos-aarch64-none","version":"3.12.15"},
             {"key":"cpython-3.12.16-linux-x86_64-gnu","version":"3.12.16"},
             {"key":"cpython-3.12.17+freethreaded-macos-aarch64-none","version":"3.12.17"},
             {"key":"pypy-3.12.18-macos-aarch64-none","version":"3.12.18"}]
            """.utf8)
        #expect(UvPythonAdapter.newestDownload(list, line: "cpython-3.12-macos-aarch64-none") == "3.12.15")
    }

    /// Directory names as uv writes them. Mutation: split the platform on its
    /// own dashes; keep a pre-release.
    @Test func patchDirectoriesNameTheirLine() {
        let patch = UvPythonAdapter.Patch(directoryName: "cpython-3.13.9+freethreaded-macos-aarch64-none")
        #expect(patch?.line == "cpython-3.13+freethreaded-macos-aarch64-none")
        #expect(patch?.version == "3.13.9")
        #expect(UvPythonAdapter.Patch(directoryName: "cpython-3.12-macos-aarch64-none") == nil)
        #expect(UvPythonAdapter.Patch(directoryName: "cpython-3.15.0rc1-macos-aarch64-none") == nil)
        #expect(UvPythonAdapter.Patch(directoryName: "pypy-3.11.13-macos-aarch64-none") == nil)
    }
}
