import Foundation
import Testing
@testable import DuoUpdaterCore

/// pyenv's and rbenv's versions as managed lines (`PyenvAdapter`,
/// `RbenvAdapter`, design §4.7/§4.8). `Fixtures/managed/build/` holds the
/// definition file names of python-build in pyenv 2.8.14 and of ruby-build
/// 20261023, listed from checkouts on 2026-10-27. The layouts below are those
/// checkouts' (`bin/pyenv -> ../libexec/pyenv`, `libexec/pyenv---version`).
///
/// The host is scripted: nothing here lists the real home or runs a manager.
/// Each case names the mutation it fails under.
struct DefinitionLinesTests {

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let pyenvRoot = "/ZZFixture-home/.pyenv"
    static let rbenvRoot = "/ZZFixture-home/.rbenv"

    static func names(_ fixture: String) throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/build/\(fixture)"))
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
    }

    final class FakeHost: @unchecked Sendable {
        let lock = NSLock()
        var files: [String: Data] = [:]
        var directories: [String: [String]] = [:]
        var existing: Set<String> = []
        var links: [String: String] = [:]
        var quarantined: Set<String> = []

        func add(version: String, root: String, interpreter: String) {
            lock.withLock {
                directories[root + "/versions", default: []].append(version)
                existing.insert(root + "/versions/\(version)/\(interpreter)")
            }
        }

        var host: PyenvAdapter.Host {
            PyenvAdapter.Host(
                contents: { path in self.lock.withLock { self.files[path] } },
                directories: { path in self.lock.withLock { self.directories[path] } },
                exists: { path in self.lock.withLock { self.existing.contains(path) } },
                resolve: { path in
                    self.lock.withLock {
                        if let target = self.links[path] { return target }
                        return self.directories[path] != nil || self.files[path] != nil ? path : nil
                    }
                },
                isQuarantined: { path in self.lock.withLock { self.quarantined.contains(path) } })
        }

        /// pyenv as a git checkout, three versions on two lines, `envs` and a
        /// pre-release beside them, the global set to 3.12.15.
        static func pyenvCheckout() throws -> FakeHost {
            let host = FakeHost()
            let root = DefinitionLinesTests.pyenvRoot
            host.directories[root + "/plugins/python-build/share/python-build"] = try DefinitionLinesTests.names("python-build-2.8.14.txt")
            host.directories[root + "/plugins"] = ["python-build"]
            host.existing.insert(root + "/plugins/python-build/bin/pyenv-install")
            host.links[root + "/bin/pyenv"] = root + "/libexec/pyenv"
            host.files[root + "/libexec/pyenv"] = Data()
            host.files[root + "/libexec/pyenv---version"] = Data("#!/usr/bin/env bash\n\nversion=\"2.8.14\"\n".utf8)
            host.files[root + "/version"] = Data("3.12.15\n".utf8)
            host.directories[root + "/versions"] = ["envs", "3.15.0rc1", "pypy3.10-7.3.17"]
            for version in ["3.12.15", "3.12.10", "3.13.9t"] { host.add(version: version, root: root, interpreter: "bin/python3") }
            return host
        }

        /// rbenv and ruby-build from Homebrew, one Ruby.
        static func rbenvKegs() throws -> FakeHost {
            let host = FakeHost()
            let root = DefinitionLinesTests.rbenvRoot
            host.links["/opt/homebrew/bin/rbenv"] = "/opt/homebrew/Cellar/rbenv/1.3.2/libexec/rbenv"
            host.files["/opt/homebrew/Cellar/rbenv/1.3.2/INSTALL_RECEIPT.json"] = Data("{}".utf8)
            let share = "/opt/homebrew/Cellar/ruby-build/20261023/share/ruby-build"
            host.links["/opt/homebrew/opt/ruby-build/share/ruby-build"] = share
            host.directories[share] = try DefinitionLinesTests.names("ruby-build-20261023.txt")
            host.files["/opt/homebrew/Cellar/ruby-build/20261023/INSTALL_RECEIPT.json"] = Data("{}".utf8)
            host.add(version: "3.4.11", root: root, interpreter: "bin/ruby")
            return host
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

    static func provider(_ adapter: any ManagerAdapter, runs: Runs = Runs(), afterRun: @escaping @Sendable () -> Void = {}) -> ManagedProvider {
        ManagedProvider(
            adapter, home: home, proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { command, environment, _, _, _ in
                await runs.record(command, environment)
                afterRun()
                return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: [])
            })
    }

    static func status(_ report: CLIToolReport, _ key: String) -> CLIToolStatus? {
        report.statuses.first { $0.managedItem?.key == key }
    }

    // MARK: pyenv

    /// One row per line at its newest patch, the newest definition read from
    /// disk with pyenv-latest's rule (3.12 → 3.12.16, 3.13t → 3.13.18t, as
    /// `pyenv latest -k` printed); `envs`, pre-releases and PyPy make no row.
    /// Mutation: let `3.12-dev` or a `t` build count for 3.12; sort versions as
    /// strings (3.12.9 above 3.12.16).
    @Test func pyenvLinesReadTheirNewestFromTheDefinitions() async throws {
        let host = try FakeHost.pyenvCheckout()
        let scan = await PyenvAdapter(home: Self.home, host: host.host).scan()
        #expect(scan.items.map(\.key) == ["3.13t", "3.12"])
        let py312 = try #require(scan.items.last)
        #expect(py312.name == "Python 3.12")
        #expect(py312.installed == "3.12.15")
        #expect(py312.alsoInstalled == ["3.12.10"])
        #expect(py312.latestOverall == "3.12.16")
        #expect(py312.facts.contains(.asKnownBy("pyenv 2.8.14")))
        #expect(py312.facts.contains(.defaultAlias("3.12.15")))
        #expect(py312.effects.contains(.compilesFromSource))
        #expect(py312.effects.contains(.cannotBeCancelledOnceStarted))
        #expect(scan.items.first?.latestOverall == "3.13.18t")
    }

    /// A checkout's pyenv has nothing to verify: the newer patch is reported
    /// with `pyenv install 3.12.16` to copy (D5.2). Mutation: run a script.
    @Test func aPyenvCheckoutIsHandedOutToCopy() async throws {
        let host = try FakeHost.pyenvCheckout()
        let report = await Self.provider(PyenvAdapter(home: Self.home, host: host.host)).check()
        let py312 = try #require(Self.status(report, "3.12"))
        #expect(py312.state == .updateAvailable)
        #expect(py312.latestVersion == "3.12.16")
        #expect(py312.oneClick == nil)
        #expect(py312.withheld == .unverified)
        #expect(py312.manualCommand?.display == "pyenv install 3.12.16")
    }

    /// Homebrew's pyenv is a keg (D5.1): the click runs `pyenv install
    /// 3.12.16` with `PYENV_ROOT` the root and Homebrew's `bin` on `PATH`,
    /// and reads the line's newest back. Mutation: install the line (`3.12`),
    /// which prompts when its newest is there; leave Homebrew off `PATH`.
    @Test func homebrewsPyenvInstallsTheNewestPatch() async throws {
        let host = try Self.homebrewsPyenv()
        let runs = Runs()
        let provider = Self.provider(PyenvAdapter(home: Self.home, host: host.host), runs: runs) {
            host.add(version: "3.12.16", root: Self.pyenvRoot, interpreter: "bin/python3")
        }
        let report = await provider.check()
        let py312 = try #require(Self.status(report, "3.12"))
        #expect(py312.oneClick?.arguments == ["install", "3.12.16"])
        #expect(await provider.update(py312) { _ in } == .updated(version: "3.12.16"))
        #expect(await runs.commands.first?.pathPrefix == "/opt/homebrew/bin:/usr/local/bin")
        #expect(await runs.environments.first?["PYENV_ROOT"] == Self.pyenvRoot)
    }

    /// `pyenvCheckout()`'s root with Homebrew's pyenv in place of the
    /// checkout: `~/.pyenv` holds only versions.
    static func homebrewsPyenv() throws -> FakeHost {
        let host = try FakeHost.pyenvCheckout()
        host.directories[Self.pyenvRoot + "/plugins/python-build/share/python-build"] = nil
        host.directories[Self.pyenvRoot + "/plugins"] = nil
        host.existing.remove(Self.pyenvRoot + "/plugins/python-build/bin/pyenv-install")
        host.links[Self.pyenvRoot + "/bin/pyenv"] = nil
        host.files[Self.pyenvRoot + "/libexec/pyenv"] = nil
        host.files[Self.pyenvRoot + "/libexec/pyenv---version"] = nil
        host.links["/opt/homebrew/bin/pyenv"] = "/opt/homebrew/Cellar/pyenv/2.8.14/libexec/pyenv"
        host.files["/opt/homebrew/Cellar/pyenv/2.8.14/INSTALL_RECEIPT.json"] = Data("{}".utf8)
        host.directories["/opt/homebrew/Cellar/pyenv/2.8.14/plugins/python-build/share/python-build"] =
            try Self.names("python-build-2.8.14.txt")
        return host
    }

    /// A python-build checkout under the root beside Homebrew's pyenv is what
    /// the keg runs (the root's plugins come first on its `PATH`), and it
    /// reads only its own definitions: the command is handed out, and the
    /// newest is the checkout's. Mutation: trust the keg alone; read the
    /// keg's definitions too.
    @Test func aPythonBuildCheckoutUnderTheRootTakesTheClickAway() async throws {
        let host = try Self.homebrewsPyenv()
        host.directories[Self.pyenvRoot + "/plugins"] = ["python-build"]
        host.existing.insert(Self.pyenvRoot + "/plugins/python-build/bin/pyenv-install")
        host.directories[Self.pyenvRoot + "/plugins/python-build/share/python-build"] =
            try Self.names("python-build-2.8.14.txt").filter { $0 != "3.12.16" }
        let scan = await PyenvAdapter(home: Self.home, host: host.host).scan()
        #expect(scan.items.last?.latestOverall == "3.12.15")
        host.directories[Self.pyenvRoot + "/plugins/python-build/share/python-build"] = try Self.names("python-build-2.8.14.txt")
        let report = await Self.provider(PyenvAdapter(home: Self.home, host: host.host)).check()
        let py312 = try #require(Self.status(report, "3.12"))
        #expect(py312.oneClick == nil)
        #expect(py312.withheld == .unverified)
        #expect(py312.manualCommand?.display == "pyenv install 3.12.16")
    }

    /// CPython 2.x installs `python` and `python2`, never `python3`: its line
    /// reads its version. Mutation: require `bin/python3`.
    @Test func aPython2LineReadsItsVersion() async throws {
        let host = try FakeHost.pyenvCheckout()
        host.add(version: "2.7.18", root: Self.pyenvRoot, interpreter: "bin/python")
        let report = await Self.provider(PyenvAdapter(home: Self.home, host: host.host)).check()
        let py27 = try #require(Self.status(report, "2.7"))
        #expect(py27.managedItem?.installed == "2.7.18")
        #expect(py27.state == .upToDate)
    }

    /// A version directory without its interpreter is a build still writing:
    /// unreadable, never offered. Mutation: trust the directory name.
    @Test func aVersionWithoutItsInterpreterIsUnreadable() async throws {
        let host = try FakeHost.pyenvCheckout()
        host.existing.remove(Self.pyenvRoot + "/versions/3.13.9t/bin/python3")
        let report = await Self.provider(PyenvAdapter(home: Self.home, host: host.host)).check()
        #expect(Self.status(report, "3.13t")?.withheld == .versionUnreadable)
    }

    /// With no python-build anywhere the rows are unreadable, not current.
    /// Mutation: read "no definition" as "nothing newer".
    @Test func noDefinitionsIsNotCurrent() async throws {
        let host = try FakeHost.pyenvCheckout()
        host.directories[Self.pyenvRoot + "/plugins/python-build/share/python-build"] = nil
        let report = await Self.provider(PyenvAdapter(home: Self.home, host: host.host)).check()
        #expect(report.statuses.allSatisfy { $0.state == .unknown && $0.withheld == .channelUnreadable })
    }

    // MARK: rbenv

    /// Homebrew's rbenv and ruby-build: Ruby 3.4.11 → 3.4.12 offered with
    /// `rbenv install 3.4.12`; `-preview`, `-rc` and other Rubies are no
    /// newest. Mutation: read `3.5.0-preview1` as the 3.5 line's.
    @Test func rbenvKegsOfferTheNewestRuby() async throws {
        let host = try FakeHost.rbenvKegs()
        let report = await Self.provider(RbenvAdapter(home: Self.home, host: host.host)).check()
        let ruby = try #require(Self.status(report, "3.4"))
        #expect(ruby.name == "Ruby 3.4")
        #expect(ruby.state == .updateAvailable)
        #expect(ruby.latestVersion == "3.4.12")
        #expect(ruby.oneClick?.display == "rbenv install 3.4.12")
        #expect(ruby.managedItem?.facts.contains(.asKnownBy("ruby-build 20261023")) == true)
        #expect(DefinitionLines.newest(try Self.names("ruby-build-20261023.txt"))["3.5"] == nil)
    }

    /// A ruby-build checkout under the root is what rbenv runs, even beside
    /// Homebrew's: nothing verifies it, so the command is handed out to copy.
    /// Mutation: trust rbenv's keg alone.
    @Test func aRubyBuildCheckoutTakesTheClickAway() async throws {
        let host = try FakeHost.rbenvKegs()
        host.directories[Self.rbenvRoot + "/plugins/ruby-build/share/ruby-build"] = try Self.names("ruby-build-20261023.txt")
        host.files[Self.rbenvRoot + "/plugins/ruby-build/bin/ruby-build"] = Data("RUBY_BUILD_VERSION=\"20261023\"\n".utf8)
        let report = await Self.provider(RbenvAdapter(home: Self.home, host: host.host)).check()
        let ruby = try #require(Self.status(report, "3.4"))
        #expect(ruby.oneClick == nil)
        #expect(ruby.withheld == .unverified)
        #expect(ruby.manualCommand?.display == "rbenv install 3.4.12")
    }

    /// Both scans are disk only, read from the source. Mutation: run a
    /// manager from `scan()`.
    @Test func theScansNameNoSpawn() throws {
        for file in ["Build/PyenvAdapter.swift", "Build/RbenvAdapter.swift"] {
            let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Sources/DuoUpdaterCore/CLITools/Managed/\(file)"), encoding: .utf8)
            for spawn in ["ChildProcess", "Process(", "URLSession"] {
                #expect(!source.contains(spawn), "\(file) names \(spawn)")
            }
        }
    }
}
