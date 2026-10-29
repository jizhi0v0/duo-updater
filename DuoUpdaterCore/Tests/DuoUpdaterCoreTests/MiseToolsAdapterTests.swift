import Foundation
import Testing
@testable import DuoUpdaterCore

/// mise's tools as managed rows (`MiseToolsAdapter`, design §4.1), driven by
/// mise's own output: the fixtures in `Fixtures/managed/mise/` are what mise
/// 2026.10.7 printed on 2026-10-23 in an isolated home whose global config
/// held `jq = "1.6"`, `node = "20"`, `"npm:prettier" = "2.0.0"` (jq 1.6, node
/// 20.10.0 and prettier 2.0.0 installed), with the home's path rewritten to
/// `/ZZFixture-home`:
/// - `ls.json`, `outdated.json`, `outdated-bump.json`: before any upgrade;
/// - `upgrade-node.txt`, `ls-after-upgrade.json`: `mise upgrade -y node`
///   and the list after it (20.10.0 waiting in purgatory);
/// - `two-requests-*.json`: the config changed to `node = ["20", "22"]`, 22.1.0
///   installed — both outdated outputs name the "22" request alone.
///
/// The host is scripted (`FakeHost`): nothing here lists the real home, runs
/// mise or reaches the network. Each case names the mutation it fails under.
struct MiseToolsAdapterTests {

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let data = "/ZZFixture-home/.local/share/mise"
    static let installs = data + "/installs"
    static let mise = "/ZZFixture-home/.local/bin/mise"

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/managed/mise/\(name)"))
    }

    /// The Mac as the adapter sees it, every answer scripted; what it was asked
    /// to run, in order.
    final class FakeHost: @unchecked Sendable {
        private let lock = NSLock()
        private var _responses: [String: MiseToolsAdapter.Output] = [:]
        private var _runs: [(arguments: [String], environment: [String: String])] = []
        private var _versionReads = 0
        var install: MiseInstall? = MiseInstall(path: MiseToolsAdapterTests.mise, version: nil)
        var homebrew: ManagedRoot.Binary?
        var executable = MiseToolsAdapterTests.mise
        var binaryVersion: String? = "2026.10.7"
        var processes: [NpmActivity.Process] = []
        var files: [String: Data] = [
            installs + "/jq/.mise.backend.toml": Data("short = \"jq\"\nfull = \"aqua:jqlang/jq\"\nexplicit_backend = false".utf8),
            installs + "/node/.mise.backend.toml": Data("short = \"node\"\nfull = \"core:node\"\nexplicit_backend = true".utf8),
            installs + "/npm-prettier/.mise.backend.toml":
                Data("short = \"npm:prettier\"\nfull = \"npm:prettier\"\nexplicit_backend = true".utf8),
            installs + "/npm-prettier/2.0.0/node_modules/prettier/package.json":
                Data(#"{"name": "prettier", "version": "2.0.0", "repository": "prettier/prettier"}"#.utf8),
        ]
        /// Real subdirectories only, as `Host.live` lists them: the alias links
        /// (`20 -> ./20.10.0`, `latest`) are not here.
        var directories: [String: [String]] = [
            installs: ["jq", "node", "npm-prettier", ".mise-installs.toml"],
            installs + "/jq": ["1.6"],
            installs + "/node": ["20.10.0"],
            installs + "/npm-prettier": ["2.0.0"],
        ]

        func respond(_ arguments: [String], with data: Data?, exitStatus: Int32 = 0) {
            lock.withLock {
                _responses[arguments.joined(separator: " ")] = data.map { MiseToolsAdapter.Output(stdout: $0, exitStatus: exitStatus) }
            }
        }
        var runs: [(arguments: [String], environment: [String: String])] { lock.withLock { _runs } }
        var versionReads: Int { lock.withLock { _versionReads } }

        init(ls: Data, outdated: Data?, bump: Data?) {
            respond(["ls", "--json"], with: ls)
            respond(["outdated", "--json"], with: outdated)
            respond(["outdated", "--bump", "--json"], with: bump)
            // What `mise latest` printed online for the fixtures' home
            // (2026.10.7, 2026-10-23).
            for (argument, version) in [
                ("jq@1.6", "1.6"), ("jq", "1.8.2"), ("node@20", "20.20.2"), ("node@22", "22.23.4"), ("node", "26.12.1"),
                ("npm:prettier@2.0.0", "2.0.0"), ("npm:prettier", "3.9.10"),
            ] {
                respond(["latest", argument], with: Data((version + "\n").utf8))
            }
        }

        var host: MiseToolsAdapter.Host {
            MiseToolsAdapter.Host(
                binary: { self.install },
                homebrewBinary: { self.homebrew },
                version: { _ in self.lock.withLock { self._versionReads += 1 }; return self.binaryVersion },
                contents: { self.files[$0] },
                directories: { self.directories[$0] },
                modified: { _ in Date(timeIntervalSince1970: 1_792_750_000) },
                run: { executable, arguments, environment in
                    #expect(executable == self.executable)
                    return self.lock.withLock {
                        self._runs.append((arguments, environment))
                        return self._responses[arguments.joined(separator: " ")]
                    }
                },
                proxyEnvironment: { ["https_proxy": "http://zz.invalid:3128"] },
                processes: { self.processes })
        }
    }

    static func standard() throws -> FakeHost {
        FakeHost(ls: try fixture("ls.json"), outdated: try fixture("outdated.json"), bump: try fixture("outdated-bump.json"))
    }

    static func adapter(_ host: FakeHost) -> MiseToolsAdapter {
        MiseToolsAdapter(home: home, host: host.host)
    }

    /// What the provider asked the runner to run.
    actor Runs {
        struct Run: Sendable { let command: CLIToolCommand; let environment: [String: String]; let directory: URL }
        private(set) var runs: [Run] = []
        var results: [ManagedProvider.RunResult] = [ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: [])]
        func record(_ run: Run) -> ManagedProvider.RunResult {
            runs.append(run)
            return results.count > 1 ? results.removeFirst() : results[0]
        }
        func set(_ results: [ManagedProvider.RunResult]) { self.results = results }
    }

    static func provider(
        _ host: FakeHost, runs: Runs = Runs(), token: String? = nil,
        afterRun: @escaping @Sendable () -> Void = {}
    ) -> ManagedProvider {
        ManagedProvider(
            adapter(host), home: home,
            proxyEnvironment: { ["https_proxy": "http://zz.invalid:3128"] },
            processes: { [] },
            token: { token },
            runner: { command, environment, directory, _, _ in
                let result = await runs.record(Runs.Run(command: command, environment: environment, directory: directory))
                afterRun()
                return result
            })
    }

    static func status(_ report: CLIToolReport, _ key: String) -> CLIToolStatus? {
        report.statuses.first { $0.managedItem?.key == key }
    }

    // MARK: scan

    /// The scan reads the disk and runs nothing: not mise's commands, not its
    /// `--version`. One item per tool directory, named by its
    /// `.mise.backend.toml`, at its newest real version. Mutation: read the
    /// version in `scan` (`host.version`), or name an item by its directory
    /// ("npm-prettier").
    @Test func theScanReadsTheDiskAndRunsNothing() async throws {
        let host = try Self.standard()
        host.directories[Self.installs + "/node"] = ["20.10.0", "20.20.2"]
        let scan = await Self.adapter(host).scan()
        #expect(host.runs.isEmpty)
        #expect(host.versionReads == 0)
        #expect(scan.items.map(\.key) == ["jq", "node", "npm:prettier"])
        #expect(scan.items.map(\.installed) == ["1.6", "20.20.2", "2.0.0"])
        #expect(scan.items.map(\.backend) == ["aqua:jqlang/jq", "core:node", "npm:prettier"])
        #expect(scan.roots.map(\.path) == [Self.data])
        #expect(scan.roots.first?.binary?.trust == .vendorSigned(team: MiseScanner.teamIdentifier))
        #expect(scan.roots.first?.binary?.version == nil)
        // What a `mise use` or an install in a terminal changes, the next
        // scan sees: the version set and the backend.
        let node = try #require(scan.items.first { $0.key == "node" })
        #expect(scan.states[node.identity]?.hasPrefix("core:node|20.10.0,20.20.2|") == true)
        // No installs directory: nothing to list.
        host.directories[Self.installs] = nil
        #expect(await Self.adapter(host).scan() == .empty)
    }

    /// Homebrew's mise runs the tools when there is no standalone mise, and the
    /// child's `PATH` gets Homebrew's `bin` for the backends it starts.
    /// Mutation: keep the binary from `MiseScanner` alone, or drop the keg's
    /// directory from `PATH`.
    @Test func aHomebrewMiseRunsTheToolsWhenNoStandaloneMiseExists() async throws {
        let host = try Self.standard()
        host.install = nil
        host.homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/mise", version: "2026.10.23", trust: .homebrewKeg)
        host.executable = "/opt/homebrew/bin/mise"
        let scan = await Self.adapter(host).scan()
        #expect(scan.roots.first?.binary?.trust == .homebrewKeg)
        let report = await Self.provider(host).check()
        let node = try #require(Self.status(report, "node@20"))
        #expect(node.state == .updateAvailable)
        #expect(node.oneClick == CLIToolCommand(
            executable: "/opt/homebrew/bin/mise", arguments: ["upgrade", "-y", "node"],
            pathPrefix: Self.data + "/shims:/ZZFixture-home/.local/bin:/opt/homebrew/bin"))
        #expect(host.runs.first?.environment["PATH"] == Self.data + "/shims:/ZZFixture-home/.local/bin:/opt/homebrew/bin:"
            + CLIToolCommandRunner.systemPath)
    }

    /// The same, read from the source: `scan()` names no spawn at all (design
    /// §10's "no `ChildProcess` in any adapter's scan"). Mutation: call
    /// `host.run`, `host.version` or `ChildProcess` from `scan()`.
    @Test func theScanSourceNamesNoSpawn() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/DuoUpdaterCore/CLITools/Managed/Mise/MiseToolsAdapter.swift"),
            encoding: .utf8)
        let start = try #require(source.range(of: "public func scan() async -> ManagedScan {"))
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
        for spawn in ["ChildProcess", "host.run", "host.version", "runVersion", "Process("] {
            #expect(!body.contains(spawn), "scan() names \(spawn)")
        }
    }

    // MARK: check

    /// The acceptance rows of §8.1, from mise's own output: node follows "20"
    /// and is offered 20.10.0 → 20.20.2 with `mise upgrade -y node`; jq and
    /// prettier are held at exact pins, `.pinned`, never offered, with `mise
    /// upgrade --bump <tool>` to copy. Mutation: offer a `.pinned` row; take
    /// `latestVersion` from `--bump` for a range; key rows by tool, not request.
    @Test func theChecksRowsAreTheConfigsRequests() async throws {
        let host = try Self.standard()
        let report = await Self.provider(host).check()
        #expect(report.statuses.map { $0.managedItem?.key } == ["jq@1.6", "node@20", "npm:prettier@2.0.0"])

        let node = try #require(Self.status(report, "node@20"))
        #expect(node.state == .updateAvailable)
        #expect(node.installedVersion == "20.10.0")
        #expect(node.latestVersion == "20.20.2")
        #expect(node.oneClick == CLIToolCommand(
            executable: Self.mise, arguments: ["upgrade", "-y", "node"],
            pathPrefix: Self.data + "/shims:/ZZFixture-home/.local/bin"))
        #expect(node.identity == "mise|\(Self.data)|node@20")
        #expect(node.path == Self.installs + "/node/20.10.0")
        #expect(node.name == "node")
        #expect(node.managedItem?.request == ManagedItem.Request(kind: .range, spelled: "20",
                                                                source: "/ZZFixture-home/.config/mise/config.toml"))
        #expect(node.managedItem?.latestOverall == "26.12.1")
        #expect(node.managedItem?.backend == "core:node")
        #expect(node.managedItem?.effects == [.oldKept(for: "24h")])

        for (key, latest) in [("jq@1.6", "1.8.2"), ("npm:prettier@2.0.0", "3.9.10")] {
            let pinned = try #require(Self.status(report, key))
            #expect(pinned.state == .pinned, "\(key)")
            #expect(pinned.oneClick == nil)
            #expect(pinned.latestVersion == latest)
            #expect(pinned.managedItem?.request?.kind == .exact)
            #expect(pinned.manualCommand?.arguments == ["upgrade", "--bump", pinned.name ?? ""])
            #expect(pinned.commandToCopy == pinned.manualCommand)
        }
    }

    /// The check's commands, exactly — the three reads, then `mise latest`
    /// for each request plain `outdated` left out — with an environment built from
    /// scratch: the proxy, `HOME`, a `PATH` led by mise's shims, `NO_COLOR` —
    /// no `MISE_*` of a terminal's, no token. And the binary's version is read
    /// once, for the header and the effect. Mutation: inherit the environment;
    /// pass `--global` or `-y` to a read; skip `resolve`.
    @Test func theCheckRunsThreeReadsWithABuiltEnvironment() async throws {
        let host = try Self.standard()
        let report = await Self.provider(host).check()
        #expect(host.runs.map(\.arguments) == [
            ["ls", "--json"], ["outdated", "--json"], ["outdated", "--bump", "--json"],
            ["latest", "jq@1.6"], ["latest", "npm:prettier@2.0.0"],
        ])
        for run in host.runs {
            #expect(Set(run.environment.keys) == ["https_proxy", "HOME", "PATH", "NO_COLOR"])
            #expect(run.environment["HOME"] == "/ZZFixture-home")
            #expect(run.environment["PATH"] == Self.data + "/shims:/ZZFixture-home/.local/bin:" + CLIToolCommandRunner.systemPath)
        }
        #expect(host.versionReads == 1)
        guard case .managed(let context) = report.context else { Issue.record("no managed context"); return }
        #expect(context.headerSummary(home: "/ZZFixture-home") == "mise 2026.10.7")
        #expect(context.headerTooltip(home: "/ZZFixture-home")
            == "Binary: ~/.local/bin/mise\nData: ~/.local/share/mise")
        // The report's sightings are the scan's, so the next open's scan
        // agrees with it while the disk is unchanged.
        #expect(Set(report.sightings) == Set(await Self.adapter(host).scan().sightings()))
    }

    /// Before 2025.2.8 mise printed nothing when nothing was outdated (MISE-56):
    /// that is "nothing outdated", not an unreadable channel; garbage is not.
    /// With nothing outdated inside its request, node is current, and what
    /// lies beyond `20` rides along with the command that lifts it (D2).
    /// Mutation: parse empty stdout as a failure; count a range held at its
    /// top as outdated.
    @Test func emptyOutdatedIsNothingOutdated() async throws {
        #expect(MiseToolsOutdated.parse(Data())?.entries.isEmpty == true)
        #expect(MiseToolsOutdated.parse(Data("\n".utf8))?.entries.isEmpty == true)
        #expect(MiseToolsOutdated.parse(Data("{}".utf8))?.entries.isEmpty == true)
        #expect(MiseToolsOutdated.parse(Data("mise ERROR".utf8)) == nil)

        let host = FakeHost(ls: try Self.fixture("ls.json"), outdated: Data(), bump: try Self.fixture("outdated-bump.json"))
        host.respond(["latest", "node@20"], with: Data("20.10.0\n".utf8))
        let report = await Self.provider(host).check()
        let node = try #require(Self.status(report, "node@20"))
        #expect(node.state == .upToDate)
        #expect(node.latestVersion == "20.10.0")
        #expect(node.oneClick == nil)
        #expect(ManagedCheck.beyondRequest(node) == "26.12.1")
        #expect(node.manualCommand?.arguments == ["upgrade", "--bump", "node"])
        #expect(node.commandToCopy == nil)
    }

    /// The network came back between `mise outdated` (which could read
    /// nothing, `{}`) and `mise latest node@20` (which printed 20.20.2): the
    /// printed version is the answer, so node is offered, not called current
    /// for a quarter of an hour. Mutation: check only that `mise latest`
    /// printed something.
    @Test func aNewerVersionMiseLatestPrintedIsOffered() async throws {
        let host = FakeHost(ls: try Self.fixture("ls.json"), outdated: Data("{}".utf8), bump: Data("{}".utf8))
        let node = try #require(Self.status(await Self.provider(host).check(), "node@20"))
        #expect(node.state == .updateAvailable)
        #expect(node.latestVersion == "20.20.2")
        #expect(node.oneClick?.arguments == ["upgrade", "-y", "node"])
    }

    /// Offline, mise prints `{}` to both reads and exits 0 (mise 2026.10.7,
    /// its proxy pointed at a closed port, `offline-outdated*`); what it warns
    /// depends on the backend and on `quiet`, so the rows the maps leave out
    /// are read again with `mise latest`, which printed nothing for any of
    /// them. No row reads as current then — not node's range, not the exact
    /// pins, not a range on aqua's jq (`jq = "1"`, which warns no "Error
    /// getting latest version" at all). Mutation: read an absence from the
    /// maps as "nothing newer"; let a pin with nothing read beyond it fall
    /// through to current.
    @Test func offlineIsNeverCurrent() async throws {
        let ls = String(decoding: try Self.fixture("ls.json"), as: UTF8.self)
            .replacingOccurrences(of: #""requested_version": "1.6""#, with: #""requested_version": "1""#)
        #expect(ls.contains(#""requested_version": "1""#))
        let host = FakeHost(ls: Data(ls.utf8), outdated: try Self.fixture("offline-outdated.json"),
                            bump: try Self.fixture("offline-outdated-bump.json"))
        for argument in ["jq@1", "node@20", "npm:prettier@2.0.0", "jq", "node", "npm:prettier"] {
            host.respond(["latest", argument], with: Data(), exitStatus: argument.hasPrefix("jq") ? 0 : 1)
        }
        let report = await Self.provider(host).check()
        #expect(report.statuses.map { $0.managedItem?.key } == ["jq@1", "node@20", "npm:prettier@2.0.0"])
        for status in report.statuses {
            #expect(status.state == .unknown, "\(status.name ?? "")")
            #expect(status.withheld == .channelUnreadable)
            #expect(status.oneClick == nil)
        }

        // A `mise latest` that ran into the deadline stops the rest: each
        // would wait as long.
        let stalled = FakeHost(ls: try Self.fixture("ls.json"), outdated: Data("{}".utf8), bump: Data("{}".utf8))
        stalled.respond(["latest", "jq@1.6"], with: nil)
        _ = await Self.provider(stalled).check()
        #expect(stalled.runs.filter { $0.arguments.first == "latest" }.map(\.arguments) == [["latest", "jq@1.6"]])

        // `--bump` failing alone (it times out: mise's own 20 s is past the
        // 15 s deadline) leaves the pins to `mise latest <tool>`: read, jq is
        // pinned; not read, prettier is unknown. node stays current inside
        // its request.
        let bumpless = try Self.standard()
        bumpless.respond(["outdated", "--json"], with: Data("{}".utf8))
        bumpless.respond(["outdated", "--bump", "--json"], with: nil)
        bumpless.respond(["latest", "npm:prettier"], with: Data(), exitStatus: 1)
        bumpless.respond(["latest", "node@20"], with: Data("20.10.0\n".utf8))
        let partial = await Self.provider(bumpless).check()
        #expect(Self.status(partial, "node@20")?.state == .upToDate)
        #expect(Self.status(partial, "jq@1.6")?.state == .pinned)
        #expect(Self.status(partial, "npm:prettier@2.0.0")?.state == .unknown)
    }

    /// After `mise upgrade -y node`: the row is 20.20.2 and current; the
    /// version it left waits in purgatory (`scheduled_for_pruning`), is no row
    /// of its own and is listed under the row as also installed. Mutation:
    /// treat a purgatory entry as a row.
    @Test func afterTheUpgradeTheOldVersionIsAlsoInstalled() async throws {
        let bump = Data(#"""
            {"node": {"name": "node", "requested": "20", "current": "20.20.2", "bump": "26", "latest": "26.12.1"},
             "jq": {"name": "jq", "requested": "1.6", "current": "1.6", "bump": "1.8", "latest": "1.8.2"},
             "npm:prettier": {"name": "npm:prettier", "requested": "2.0.0", "current": "2.0.0", "bump": "3.9.10", "latest": "3.9.10"}}
            """#.utf8)
        let host = FakeHost(ls: try Self.fixture("ls-after-upgrade.json"), outdated: Data("{}".utf8), bump: bump)
        host.directories[Self.installs + "/node"] = ["20.10.0", "20.20.2"]
        let report = await Self.provider(host).check()
        #expect(report.statuses.compactMap { $0.managedItem?.key }.filter { $0.hasPrefix("node") } == ["node@20"])
        let node = try #require(Self.status(report, "node@20"))
        #expect(node.state == .upToDate)
        #expect(node.installedVersion == "20.20.2")
        #expect(node.path == Self.installs + "/node/20.20.2")
        #expect(node.managedItem?.alsoInstalled == ["20.10.0"])
    }

    /// `mise outdated` is keyed by tool name, so of `node = ["20", "22"]` only
    /// the "22" request is reported (MISE-23): that row is offered, the "20"
    /// row says it was not checked and why, and never reads as current.
    /// Mutation: give the "20" row the "22" entry; call it current for want
    /// of an entry.
    @Test func twoRequestsOfOneToolCollapseInOutdated() async throws {
        let host = FakeHost(
            ls: try Self.fixture("two-requests-ls.json"), outdated: try Self.fixture("two-requests-outdated.json"),
            bump: try Self.fixture("two-requests-outdated-bump.json"))
        host.directories[Self.installs + "/node"] = ["20.10.0", "20.20.2", "22.1.0"]
        let report = await Self.provider(host).check()
        let nodes = report.statuses.filter { $0.name == "node" }
        #expect(nodes.compactMap { $0.managedItem?.key } == ["node@20", "node@22"])

        let twentyTwo = try #require(Self.status(report, "node@22"))
        #expect(twentyTwo.state == .updateAvailable)
        #expect(twentyTwo.installedVersion == "22.1.0")
        #expect(twentyTwo.latestVersion == "22.23.4")

        let twenty = try #require(Self.status(report, "node@20"))
        #expect(twenty.state == .unknown)
        #expect(twenty.oneClick == nil)
        #expect(twenty.withheld == .unsupportedInstaller)
        #expect(twenty.note?.contains("one request per tool") == true)
        // Purgatory's 20.10.0 is the "20" request's, not the "22" one's.
        #expect(twenty.managedItem?.alsoInstalled == ["20.10.0"])
        #expect(twentyTwo.managedItem?.alsoInstalled == [])
        // Both say that one click moves both.
        #expect(twentyTwo.managedItem?.facts.contains(.note("mise upgrade node moves every request of node: 22, 20")) == true)
    }

    /// Rows are requests that are installed: an `installed: false` request
    /// (nothing to update yet, MISE-24) and a version nothing requests (D4)
    /// make none. Mutation: make a row of either.
    @Test func onlyInstalledRequestsAreRows() throws {
        let ls = try #require(MiseToolsLs.parse(Data(#"""
            {"jq": [{"version": "1.6", "install_path": "/z/installs/jq/1.6", "installed": true, "active": false},
                    {"version": "1.7", "requested_version": "1.7", "install_path": "/z/installs/jq/1.7",
                     "source": {"type": "mise.toml", "path": "/z/config.toml"}, "installed": false, "active": true}],
             "node": [{"version": "20.20.2", "requested_version": "20", "install_path": "/z/installs/node/20.20.2",
                       "installed": true, "active": true, "a_field_of_a_newer_mise": [1, 2]}]}
            """#.utf8)))
        let reading = MiseToolsOutdated.Reading(
            ls: ls, outdated: .init(entries: [:]), bump: .init(entries: [:]), latest: ["node@20": "20.20.2", "node": "26.12.1"])
        let verdicts = MiseToolsOutdated.verdicts(reading) {
            tool, entry, decided in
            ManagedItem(
                descriptor: MiseToolsAdapter.descriptor, root: "/z", key: MiseToolsAdapter.key(tool: tool, requested: entry.requestedVersion ?? ""),
                name: tool, installPath: entry.installPath, shape: .request, request: decided.request, installed: entry.version,
                latestWithinRequest: decided.latestWithinRequest)
        }
        #expect(verdicts.map(\.item.key) == ["node@20"])
        #expect(verdicts.first?.vendorWouldUpgrade == false)
    }

    /// How a request follows releases. Mutation: call "20" exact (its row
    /// would read pinned), or "1.6" a range when 1.6 is what is installed.
    @Test func requestKinds() {
        let cases: [(String, String, ManagedItem.Request.Kind?)] = [
            ("20", "20.10.0", .range), ("1.6", "1.6", .exact), ("2.0.0", "2.0.0", .exact), ("20.10.0", "20.10.0", .exact),
            ("1.6", "1.6.1", .range), ("latest", "1.8.2", .alias), ("lts", "24.1.0", .alias), ("lts/iron", "20.20.2", .alias),
            ("prefix:1.2", "1.2.9", .range), ("ref:main", "ref-main", nil), ("path:/opt/x", "path", nil), ("system", "system", nil),
        ]
        for (requested, version, kind) in cases {
            #expect(MiseToolsOutdated.requestKind(requested, version: version) == kind, "\(requested)")
        }
    }

    // MARK: the binary's trust

    /// No mise the trust rule lets run: nothing is run at all, the installs
    /// are listed from disk, and each row says why — another signer's build,
    /// a quarantined one, none at the installer's path. Mutation: run a
    /// binary whose trust is `.untrusted`.
    @Test func anUntrustedMiseIsNeverRun() async throws {
        let cases: [(MiseInstall?, CLIToolWithheld)] = [
            (MiseInstall(path: Self.mise, version: nil, signature: .otherSigner), .wrongSigner),
            (MiseInstall(path: Self.mise, version: nil, signature: .adHoc), .unverified),
            (MiseInstall(path: Self.mise, version: nil, quarantined: true), .unverified),
            (nil, .updaterMissing),
        ]
        for (install, withheld) in cases {
            let host = try Self.standard()
            host.install = install
            let report = await Self.provider(host).check()
            #expect(host.runs.isEmpty)
            #expect(host.versionReads == 0)
            #expect(report.statuses.map { $0.managedItem?.key } == ["jq", "node", "npm:prettier"])
            #expect(report.statuses.allSatisfy { $0.state == .unknown && $0.oneClick == nil && $0.withheld == withheld },
                    "\(String(describing: install))")
        }
    }

    /// `mise ls` not answering leaves every install unknown with the reason;
    /// `outdated` not answering leaves every row unknown. Mutation: read a
    /// failed command's silence as "nothing outdated".
    @Test func aFailedReadIsAnUnreadableChannel() async throws {
        let silent = try Self.standard()
        silent.respond(["ls", "--json"], with: nil)
        let none = await Self.provider(silent).check()
        #expect(none.statuses.count == 3)
        #expect(none.statuses.allSatisfy { $0.withheld == .channelUnreadable })

        let noOutdated = try Self.standard()
        noOutdated.respond(["outdated", "--json"], with: nil)
        let rows = await Self.provider(noOutdated).check()
        #expect(rows.statuses.map { $0.managedItem?.key } == ["jq@1.6", "node@20", "npm:prettier@2.0.0"])
        #expect(rows.statuses.allSatisfy { $0.state == .unknown && $0.withheld == .channelUnreadable })
    }

    /// mise's own install or upgrade running holds every row's click.
    /// Mutation: drop the busy gate from `check`.
    @Test func aRunningMiseUpgradeHoldsTheClick() async throws {
        let host = try Self.standard()
        host.processes = [NpmActivity.Process(pid: 4242, arguments: [Self.mise, "upgrade", "jq"], executable: Self.mise)]
        let node = try #require(Self.status(await Self.provider(host).check(), "node@20"))
        #expect(node.state == .updateAvailable)
        #expect(node.oneClick == nil)
        #expect(node.withheld == .busy)
        #expect(node.note == "mise upgrade is running (pid 4242)")
    }

    // MARK: update

    /// The click: the request re-read with `mise ls` (still 20.10.0), then
    /// `mise upgrade -y node` and nothing else — from `/`, where mise trusts
    /// no config for the user (measured: from `$HOME`, `-y` trusted an
    /// untrusted `~/mise.toml`), with no token handed on — then the version
    /// read back from `mise ls`. Mutation: run from the inherited directory;
    /// pass `--bump` or `node@20.20.2`; settle on the scan's directory.
    @Test func theClickUpgradesFromRootAndReadsTheVersionBack() async throws {
        let host = try Self.standard()
        let after = try Self.fixture("ls-after-upgrade.json")
        let runs = Runs()
        let provider = Self.provider(host, runs: runs, token: "ghp_zz") { host.respond(["ls", "--json"], with: after) }
        let node = try #require(Self.status(await provider.check(), "node@20"))
        let outcome = await provider.update(node) { _ in }
        #expect(outcome == .updated(version: "20.20.2"))
        let ran = await runs.runs
        #expect(ran.map(\.command.arguments) == [["upgrade", "-y", "node"]])
        #expect(ran.first?.directory.path == "/")
        #expect(ran.first?.environment["MISE_GITHUB_TOKEN"] == nil)
        #expect(ran.first?.environment["HOME"] == "/ZZFixture-home")
        #expect(ran.first?.environment["PATH"]?.hasPrefix(Self.data + "/shims:") == true)
        #expect(MiseToolsAdapter(home: Self.home, host: host.host).workingDirectory(home: Self.home).path == "/")
    }

    /// Between the check and the click the request moved — another version
    /// installed in a terminal — or went from the config: nothing is run.
    /// Mutation: skip the `current` gate.
    @Test func aRequestThatMovedIsNotRun() async throws {
        let host = try Self.standard()
        let runs = Runs()
        let provider = Self.provider(host, runs: runs)
        let node = try #require(Self.status(await provider.check(), "node@20"))
        host.respond(["ls", "--json"], with: try Self.fixture("ls-after-upgrade.json"))
        guard case .failed = await provider.update(node, progress: { _ in }) else {
            Issue.record("a moved request was run"); return
        }
        host.respond(["ls", "--json"], with: Data(#"{"jq": []}"#.utf8))
        guard case .failed = await provider.update(node, progress: { _ in }) else {
            Issue.record("a request gone from the config was run"); return
        }
        #expect(await runs.runs.isEmpty)
    }

    /// mise's token handoff, shared: a second run with the app's token only
    /// after mise said it found none of its own. Mutation: hand the token on
    /// up front; retry on any failure.
    @Test func theTokenIsHandedOnOnlyAfterMiseFoundNone() async throws {
        let host = try Self.standard()
        let runs = Runs()
        await runs.set([
            ManagedProvider.RunResult(succeeded: false, failureMessage: "403", lines: [
                "mise WARN  No GitHub token was found, so mise is making unauthenticated requests to GitHub which have a much lower rate limit.",
            ]),
            ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: []),
        ])
        let provider = Self.provider(host, runs: runs, token: "ghp_zz")
        let node = try #require(Self.status(await provider.check(), "node@20"))
        _ = await provider.update(node) { _ in }
        let ran = await runs.runs
        #expect(ran.map { $0.environment["MISE_GITHUB_TOKEN"] } == [nil, "ghp_zz"])
    }

    // MARK: effects and notes

    /// The old version kept 24 h from 2026.8.15 (purgatory), removed at once
    /// before; nothing said when the version is unknown. Mutation: compare
    /// as text ("2026.10.7" < "2026.8.15").
    @Test func whatTheUpgradeDoesFollowsTheMiseVersion() {
        #expect(MiseToolsAdapter.effects(binaryVersion: "2026.10.7") == [.oldKept(for: "24h")])
        #expect(MiseToolsAdapter.effects(binaryVersion: "2026.8.15") == [.oldKept(for: "24h")])
        #expect(MiseToolsAdapter.effects(binaryVersion: "2026.8.14") == [.oldRemoved])
        #expect(MiseToolsAdapter.effects(binaryVersion: "2024.12.6") == [.oldRemoved])
        #expect(MiseToolsAdapter.effects(binaryVersion: nil) == [])
    }

    /// Where a row's notes are: the release mise names (jq's tags carry a
    /// "jq-" prefix), a GitHub-shaped backend, an npm package's repository;
    /// nothing for `core:node` or `asdf:` (a plugin's repository is not the
    /// tool's). Mutation: read jq's tags without the prefix; take an asdf id
    /// as the tool's repository.
    @Test func notesComeFromTheReleaseOrTheBackend() async throws {
        let report = await Self.provider(try Self.standard()).check()
        #expect(Self.status(report, "jq@1.6")?.managedItem?.notes == .gitHubReleases(owner: "jqlang", repo: "jq", tagPrefix: "jq-"))
        #expect(Self.status(report, "npm:prettier@2.0.0")?.managedItem?.notes
            == .gitHubReleases(owner: "prettier", repo: "prettier", tagPrefix: ""))
        #expect(Self.status(report, "node@20")?.managedItem?.notes == nil)

        let none: (String) -> Data? = { _ in nil }
        #expect(MiseToolsAdapter.notes(releaseURL: nil, newest: nil, backend: "github:BurntSushi/ripgrep[exe=rg]",
                                       tool: "rg", installPath: "/z", contents: none)
            == .gitHubReleases(owner: "BurntSushi", repo: "ripgrep", tagPrefix: ""))
        #expect(MiseToolsAdapter.notes(releaseURL: nil, newest: nil, backend: "asdf:mise-plugins/mise-poetry",
                                       tool: "poetry", installPath: "/z", contents: none) == nil)
        // `pipx:` packages: PyPI's project URLs, read with the notes (P2's rule).
        #expect(MiseToolsAdapter.notes(releaseURL: nil, newest: nil, backend: "pipx:black[extras=d]",
                                       tool: "pipx:black", installPath: "/z", contents: none) == .pypiProject("black"))
        #expect(MiseToolsAdapter.notes(releaseURL: nil, newest: nil, backend: "pipx:psf/black",
                                       tool: "pipx:psf/black", installPath: "/z", contents: none)
            == .gitHubReleases(owner: "psf", repo: "black", tagPrefix: ""))
        #expect(MiseToolsAdapter.gitHubRelease("https://github.com/cli/cli/releases/tag/v2.80.0", version: "2.80.0")
            == .gitHubReleases(owner: "cli", repo: "cli", tagPrefix: ""))
        #expect(MiseToolsAdapter.gitHubRelease("https://example.com/x/y/releases/tag/1.0", version: "1.0") == nil)
    }

    /// The manager is registered, first of the managers and after every
    /// standalone provider, in its own lane with mise's self-update, and pauses
    /// with GitHub's budget (D12, §3.4). Mutation: leave the registry empty;
    /// give the rows a lane of their own.
    @Test func miseToolsAreRegistered() {
        #expect(ManagerRegistry.adapters.map(\.descriptor.id) == [MiseToolsAdapter.id, UvToolAdapter.id, UvPythonAdapter.id, PipxAdapter.id, NvmNodeAdapter.id, FnmNodeAdapter.id,
                                                                    PyenvAdapter.id, RbenvAdapter.id, CargoAdapter.id, GoAdapter.id])
        #expect(MiseToolsAdapter.descriptor.lane == "mise")
        #expect(MiseToolsAdapter.descriptor.updaterSpendsGitHubAPI == .ourTokenIfAny)
        #expect(MiseToolsAdapter.descriptor.providerID == "managed:mise")
        #expect(CLITools.providers().suffix(10).map(\.id)
            == ["managed:mise", "managed:uv-tool", "managed:uv-python", "managed:pipx", "managed:nvm-node", "managed:fnm-node",
                "managed:pyenv", "managed:rbenv", "managed:cargo", "managed:go"])
    }
}
