import Foundation
import Testing
@testable import DuoUpdaterCore

/// nvm's and fnm's Node versions as managed lines (`NvmNodeAdapter`,
/// `FnmNodeAdapter`, design §4.5/§4.6). `Fixtures/managed/node/` holds
/// nodejs.org's `index.json` as read on 2026-10-27, trimmed to its first 40
/// releases plus the 22.1x/22.2x ones and to the fields read, and the head of
/// `CHANGELOG_V22.md` (the table and the 22.23.4 and 22.23.3 sections). The
/// layouts below are what nvm 0.40.8 and fnm 1.39.0 made in isolated roots.
///
/// The host is scripted (`FakeHost`): nothing here lists the real home, runs
/// a manager or reaches the network. Each case names the mutation it fails under.
struct NodeAdapterTests {

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let nvmDir = "/ZZFixture-home/.nvm"
    static let fnmDir = "/ZZFixture-home/.local/share/fnm"

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/node/\(name)"))
    }

    final class FakeHost: @unchecked Sendable {
        let lock = NSLock()
        var files: [String: Data] = [:]
        var directories: [String: [String]] = [:]
        var existing: Set<String> = []
        var links: [String: String] = [:]
        var quarantined: Set<String> = []
        var index: Data?
        private var _indexReads = 0
        var indexReads: Int { lock.withLock { _indexReads } }

        init() throws {
            index = try NodeAdapterTests.fixture("index-trimmed.json")
            // nvm: Homebrew's, linked from the directory as on this Mac.
            let nvm = NodeAdapterTests.nvmDir
            directories[nvm] = ["alias", "nvm.sh", "versions"]
            directories[nvm + "/versions/node"] = ["v22.21.1", "v22.20.0", "v24.22.1", "v0.12.18", ".cache"]
            links[nvm + "/nvm.sh"] = "/opt/homebrew/Cellar/nvm/0.40.8/libexec/nvm.sh"
            files["/opt/homebrew/Cellar/nvm/0.40.8/INSTALL_RECEIPT.json"] = Data("{}".utf8)
            files[nvm + "/alias/default"] = Data("22.21.1\n".utf8)
            for version in ["v22.21.1", "v22.20.0", "v24.22.1", "v0.12.18"] {
                existing.insert(nvm + "/versions/node/\(version)/bin/node")
            }
            // fnm: Homebrew's keg, default on 24.
            let fnm = NodeAdapterTests.fnmDir
            directories[fnm] = ["aliases", "node-versions"]
            directories[fnm + "/node-versions"] = [".downloads", "v22.21.1", "v24.12.0"]
            for version in ["v22.21.1", "v24.12.0"] {
                existing.insert(fnm + "/node-versions/\(version)/installation/bin/node")
            }
            links[fnm + "/aliases/default"] = fnm + "/node-versions/v24.12.0/installation"
            links["/opt/homebrew/bin/fnm"] = "/opt/homebrew/Cellar/fnm/1.39.0/bin/fnm"
            files["/opt/homebrew/Cellar/fnm/1.39.0/INSTALL_RECEIPT.json"] = Data("{}".utf8)
        }

        func install(_ path: String) {
            lock.withLock {
                let directory = (path as NSString).deletingLastPathComponent
                let name = (path as NSString).lastPathComponent
                directories[directory, default: []].append(name)
                existing.insert(path + (directory.hasSuffix("node-versions") ? "/installation/bin/node" : "/bin/node"))
            }
        }

        var host: NvmNodeAdapter.Host {
            NvmNodeAdapter.Host(
                contents: { path in self.lock.withLock { self.files[path] } },
                directories: { path in self.lock.withLock { self.directories[path] } },
                exists: { path in self.lock.withLock { self.existing.contains(path) } },
                resolve: { path in
                    self.lock.withLock {
                        if let target = self.links[path] { return target }
                        let parent = (path as NSString).deletingLastPathComponent
                        let known = self.directories[path] != nil || self.files[path] != nil
                            || self.directories[parent]?.contains((path as NSString).lastPathComponent) == true
                        return known ? path : nil
                    }
                },
                isQuarantined: { path in self.lock.withLock { self.quarantined.contains(path) } },
                index: {
                    try self.lock.withLock {
                        self._indexReads += 1
                        guard let data = self.index else { throw NodeDistIndex.Failure.http(503) }
                        return data
                    }
                })
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

    static func provider(
        _ adapter: any ManagerAdapter, runs: Runs = Runs(), afterRun: @escaping @Sendable () -> Void = {}
    ) -> ManagedProvider {
        ManagedProvider(
            adapter, home: home, proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { command, environment, _, _, _ in
                await runs.record(command, environment)
                afterRun()
                return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: [])
            })
    }

    static func nvm(_ host: FakeHost) -> NvmNodeAdapter {
        NvmNodeAdapter(home: home, host: host.host, platform: "osx-arm64-tar")
    }

    static func fnm(_ host: FakeHost) -> FnmNodeAdapter {
        FnmNodeAdapter(home: home, host: host.host, platform: "osx-arm64-tar")
    }

    static func status(_ report: CLIToolReport, _ key: String) -> CLIToolStatus? {
        report.statuses.first { $0.managedItem?.key == key }
    }

    // MARK: nvm

    /// One row per major at its newest patch, older patches beside it; v0.x,
    /// dot directories and the alias text make no row. Homebrew's `nvm.sh`
    /// behind the directory's link is a keg (D5.1). Mutation: one row per
    /// patch; read `v0.12.18` as Node 0; trust a link out of the directory as
    /// the directory's own (exempt).
    @Test func nvmScanMakesOneRowPerMajor() async throws {
        let host = try FakeHost()
        let scan = await Self.nvm(host).scan()
        #expect(scan.items.map(\.key) == ["v24", "v22"])
        let node22 = try #require(scan.items.last)
        #expect(node22.name == "Node 22")
        #expect(node22.installed == "22.21.1")
        #expect(node22.alsoInstalled == ["22.20.0"])
        #expect(node22.installPath == Self.nvmDir + "/versions/node/v22.21.1")
        #expect(node22.effects == [.oldKept(for: nil), .defaultStays("22.21.1")])
        #expect(node22.facts.contains(.defaultAlias("22.21.1")))
        #expect(scan.items[0].effects == [.oldKept(for: nil)])
        #expect(scan.roots == [ManagedRoot(
            manager: NvmNodeAdapter.id, path: Self.nvmDir,
            binary: ManagedRoot.Binary(path: Self.nvmDir + "/nvm.sh", version: "0.40.8", trust: .homebrewKeg))])
        #expect(host.indexReads == 0)
    }

    /// 22.21.1 → 22.23.4, the newest 22 with a macOS arm64 build, with the
    /// security releases skipped counted (22.22.0, .2, 22.23.0, .2, .4) and
    /// the command that moves `default` after; 24.22.1 is current. Mutation:
    /// take nodejs.org's first entry (26.x) for every line; count releases at
    /// or below the installed one.
    @Test func nvmLinesAreCheckedOnNodejsOrg() async throws {
        let host = try FakeHost()
        let report = await Self.provider(Self.nvm(host)).check()
        let node22 = try #require(Self.status(report, "v22"))
        #expect(node22.state == .updateAvailable)
        #expect(node22.latestVersion == "22.23.4")
        let facts = try #require(node22.managedItem?.facts)
        #expect(facts.contains(.note("LTS 'Jod'")))
        #expect(facts.contains(.note("5 of the newer releases are security releases")))
        #expect(facts.contains(.note("to move default afterwards: nvm alias default 22.23.4")))
        let node24 = try #require(Self.status(report, "v24"))
        #expect(node24.state == .upToDate)
        #expect(host.indexReads == 1)
    }

    /// A release without this Mac's build is one nvm would compile: never
    /// offered. Mutation: drop the `files` test.
    @Test func aReleaseWithoutAMacBuildIsNotOffered() async throws {
        let host = try FakeHost()
        var list = try #require(try JSONSerialization.jsonObject(with: try Self.fixture("index-trimmed.json")) as? [[String: Any]])
        let index = try #require(list.firstIndex { $0["version"] as? String == "v22.23.4" })
        list[index]["files"] = ["linux-x64", "src"]
        host.index = try JSONSerialization.data(withJSONObject: list)
        let report = await Self.provider(Self.nvm(host)).check()
        #expect(Self.status(report, "v22")?.latestVersion == "22.23.3")
    }

    /// nodejs.org not answering leaves every line unknown, never current.
    /// Mutation: read a failed fetch as an empty list.
    @Test func anUnreadableIndexIsNotCurrent() async throws {
        let host = try FakeHost()
        host.index = nil
        let report = await Self.provider(Self.nvm(host)).check()
        #expect(report.statuses.allSatisfy { $0.state == .unknown && $0.withheld == .channelUnreadable })
    }

    /// The click sources the root's `nvm.sh` and runs `nvm install 22
    /// --reinstall-packages-from=22.21.1` with `NVM_DIR` the root — nothing
    /// else: no `--save`, no mirror — then reads the major's newest patch.
    /// Mutation: pass `--save`; leave `NVM_DIR` out (Homebrew's nvm would use
    /// whatever the user's profile set).
    @Test func nvmClickInstallsTheMajorAndCarriesThePackages() async throws {
        let host = try FakeHost()
        let runs = Runs()
        let provider = Self.provider(Self.nvm(host), runs: runs) { host.install(Self.nvmDir + "/versions/node/v22.23.4") }
        let report = await provider.check()
        let node22 = try #require(Self.status(report, "v22"))
        #expect(node22.oneClick?.display == "nvm install 22 --reinstall-packages-from=22.21.1")
        let outcome = await provider.update(node22) { _ in }
        #expect(outcome == .updated(version: "22.23.4"))
        let command = try #require(await runs.commands.first)
        #expect(command.executable == "/bin/bash")
        #expect(command.arguments == ["-c", NvmNodeAdapter.script, "nvm", Self.nvmDir + "/nvm.sh", "22", "22.21.1"])
        let environment = try #require(await runs.environments.first)
        #expect(environment["NVM_DIR"] == Self.nvmDir)
        #expect(!environment.keys.contains { $0.hasPrefix("NVM_NODEJS_ORG") })
        #expect(!command.arguments.contains { $0.contains("--save") })
    }

    /// The directory's own `nvm.sh` (the installer's checkout) runs under the
    /// user's exemption; one quarantined does not. Mutation: drop the
    /// quarantine check.
    @Test func nvmOwnScriptIsExemptUnlessQuarantined() async throws {
        let host = try FakeHost()
        host.links[Self.nvmDir + "/nvm.sh"] = nil
        host.files[Self.nvmDir + "/nvm.sh"] = Data("""
            nvm() {
              case $1 in
                "--version" | "-v")
                  nvm_echo '0.40.8'
            """.utf8)
        var scan = await Self.nvm(host).scan()
        #expect(scan.roots.first?.binary?.trust == .exempt(reason: NvmNodeAdapter.exemption))
        #expect(scan.roots.first?.binary?.version == "0.40.8")
        host.quarantined = [Self.nvmDir + "/nvm.sh"]
        scan = await Self.nvm(host).scan()
        #expect(scan.roots.first?.binary?.trust == .quarantined)
    }

    // MARK: fnm

    /// fnm's rows, its `default` read from the alias link, the dropped
    /// globals said before the click (D7's warning), Homebrew's keg found.
    /// Mutation: read `.downloads` as a version; forget `.packagesNotCarried`.
    @Test func fnmScanReadsVersionsAndTheDefaultLink() async throws {
        let host = try FakeHost()
        let scan = await Self.fnm(host).scan()
        #expect(scan.items.map(\.key) == ["v24", "v22"])
        let node24 = try #require(scan.items.first)
        #expect(node24.installed == "24.12.0")
        #expect(node24.effects == [.oldKept(for: nil), .defaultStays("24.12.0"), .packagesNotCarried])
        #expect(scan.items[1].effects == [.oldKept(for: nil), .packagesNotCarried])
        #expect(scan.roots.first?.binary == ManagedRoot.Binary(
            path: "/opt/homebrew/bin/fnm", version: "1.39.0", trust: .homebrewKeg))
    }

    /// `fnm --fnm-dir <root> install 24`, and the new patch read back.
    /// Mutation: leave `--fnm-dir` out (fnm would pick its own root).
    @Test func fnmClickInstallsTheMajorInItsRoot() async throws {
        let host = try FakeHost()
        let runs = Runs()
        let provider = Self.provider(Self.fnm(host), runs: runs) { host.install(Self.fnmDir + "/node-versions/v24.22.1") }
        let report = await provider.check()
        let node24 = try #require(Self.status(report, "v24"))
        #expect(node24.state == .updateAvailable)
        #expect(node24.managedItem?.facts.contains(.note("to move default afterwards: fnm default 24.22.1")) == true)
        let outcome = await provider.update(node24) { _ in }
        #expect(outcome == .updated(version: "24.22.1"))
        #expect(await runs.commands.map(\.arguments) == [["--fnm-dir", Self.fnmDir, "install", "24"]])
    }

    /// The fnm its installer left in the root has nothing to verify (ad hoc
    /// signed): the command is handed out to copy (D5.2). Mutation: run it.
    @Test func anInstallerFnmIsHandedOutToCopy() async throws {
        let host = try FakeHost()
        host.links["/opt/homebrew/bin/fnm"] = nil
        host.directories[Self.fnmDir]?.append("fnm")
        let report = await Self.provider(Self.fnm(host)).check()
        let node24 = try #require(Self.status(report, "v24"))
        #expect(node24.state == .updateAvailable)
        #expect(node24.oneClick == nil)
        #expect(node24.withheld == .unverified)
        #expect(node24.manualCommand?.arguments == ["--fnm-dir", Self.fnmDir, "install", "24"])
    }

    // MARK: notes

    /// Each `## <date>, Version <x.y.z>` section is an entry with its date;
    /// the anchors and the table above are not. Mutation: keep `<a id>`
    /// lines; read the table's links as versions.
    @Test func nodeChangelogReadsEachReleaseSection() throws {
        let markdown = String(decoding: try Self.fixture("CHANGELOG_V22-head.md"), as: UTF8.self)
        let changelog = try #require(NodeChangelog.parse(markdown))
        #expect(changelog.entries.map(\.version) == ["22.23.4", "22.23.3"])
        #expect(changelog.entries.map(\.date) == ["2026-10-21", "2026-09-23"])
        #expect(!(changelog.entries.first?.items ?? []).contains { $0.contains("<a id") })
        let content = String(describing: changelog.entries.first?.content ?? [])
        #expect(!content.contains("<a id"))
        #expect(NodeChangelog.source(major: 22).absoluteString
            == "https://raw.githubusercontent.com/nodejs/node/main/doc/changelogs/CHANGELOG_V22.md")
    }

    /// Both scans are disk only, read from the source. Mutation: fetch the
    /// index or run a manager from `scan()`.
    @Test func theScansNameNoSpawnOrFetch() throws {
        for file in ["Node/NvmNodeAdapter.swift", "Node/FnmNodeAdapter.swift"] {
            let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Sources/DuoUpdaterCore/CLITools/Managed/\(file)"), encoding: .utf8)
            let start = try #require(source.range(of: "public func scan() async -> ManagedScan {"))
            let end = try #require(source.range(of: "public func check(", range: start.upperBound..<source.endIndex))
            let body = source[start.upperBound..<end.lowerBound]
            for spawn in ["ChildProcess", "host.index", "Process(", "URLSession"] {
                #expect(!body.contains(spawn), "\(file): scan names \(spawn)")
            }
        }
    }
}
