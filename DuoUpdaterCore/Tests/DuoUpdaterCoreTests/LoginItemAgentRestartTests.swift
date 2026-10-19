import Darwin
import Foundation
import Testing
@testable import DuoUpdaterCore

/// `LoginItemAgentRestart` over invented bundles on disk and a fake process
/// list: which processes count as the agent running from the bundle being
/// replaced, and what a restart reports. The fake list plays launchd — a
/// `SIGTERM` to the old agent removes it and, unless told not to, adds a new
/// process running from the same path.
@Suite struct LoginItemAgentRestartTests {

    static let agentID = "com.example.zzhost.agent"

    // MARK: - Which processes count

    /// Mutation: in `isExecutable(_:ofAgentAt:)`, accept anything below the
    /// agent (`hasPrefix(agentPath + "/")`) → the agent's own XPC service is
    /// recorded, red.
    @Test func onlyTheAgentsOwnExecutableCounts() throws {
        let fixture = try Fixture()
        let agent = fixture.agentExecutable
        let xpc = fixture.agentPath + "/Contents/XPCServices/ZZParser.xpc/Contents/MacOS/ZZParser"
        let host = fixture.hostPath + "/Contents/MacOS/ZZHost"
        let snapshot = LoginItemAgentRestart.snapshot(
            bundle: fixture.host, agentBundleIDs: [Self.agentID],
            processes: { [Self.process(10, agent), Self.process(11, xpc), Self.process(12, host)] })
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.processes.map(\.pid) == [10])
    }

    /// The same agent id running from another copy of the host is not ours.
    /// Mutation: in `snapshot`, keep every process whose executable ends in the
    /// agent's name, or drop the path filter → pid 20 recorded, red.
    @Test func anAgentOutsideTheSwappedBundleIsLeftAlone() throws {
        let fixture = try Fixture()
        let other = try Fixture()
        let snapshot = LoginItemAgentRestart.snapshot(
            bundle: fixture.host, agentBundleIDs: [Self.agentID],
            processes: { [Self.process(20, other.agentExecutable)] })
        #expect(snapshot.first?.processes.isEmpty == true)
    }

    /// A login item the recipe does not name is not found at all, and an id
    /// is matched case-insensitively.
    @Test func onlyDeclaredLoginItemsAreFound() throws {
        let fixture = try Fixture()
        #expect(LoginItemAgentRestart.snapshot(
            bundle: fixture.host, agentBundleIDs: ["com.example.other"],
            processes: { [Self.process(10, fixture.agentExecutable)] }).isEmpty)
        #expect(LoginItemAgentRestart.snapshot(
            bundle: fixture.host, agentBundleIDs: [Self.agentID.uppercased()],
            processes: { [Self.process(10, fixture.agentExecutable)] }).count == 1)
        #expect(LoginItemAgentRestart.snapshot(
            bundle: fixture.host, agentBundleIDs: [],
            processes: { [Self.process(10, fixture.agentExecutable)] }).isEmpty)
    }

    // MARK: - Restart

    @Test func anAgentLaunchdBringsBackIsRestarted() async throws {
        let fixture = try Fixture()
        let launchd = FakeLaunchd([Self.process(10, fixture.agentExecutable)],
                                  relaunch: (pid: 30, path: fixture.agentExecutable))
        let results = await restart(fixture, launchd)
        #expect(results == [.restarted(bundleID: Self.agentID, newPID: 30)])
        #expect(launchd.signals == [.init(pid: 10, signal: SIGTERM)])
    }

    /// A pid that exited after the snapshot and now belongs to another process
    /// (same pid, later start time) is never signalled.
    /// Mutation: match old processes on pid alone (`Identity` without
    /// `startTime`) → pid 10 is signalled, red.
    @Test func aReusedPidIsNeverSignalled() async throws {
        let fixture = try Fixture()
        let snapshot = LoginItemAgentRestart.snapshot(
            bundle: fixture.host, agentBundleIDs: [Self.agentID],
            processes: { [Self.process(10, fixture.agentExecutable)] })
        let launchd = FakeLaunchd(
            [LoginItemAgentRestart.Process(pid: 10, startTime: 999, executablePath: "/usr/bin/zzother")],
            relaunch: nil)
        let results = await LoginItemAgentRestart.restart(
            snapshot, processes: launchd.list, signal: launchd.send,
            exitTimeout: .milliseconds(100), relaunchTimeout: .milliseconds(100),
            pollInterval: .milliseconds(10))
        #expect(launchd.signals.isEmpty)
        #expect(results == [.notRelaunched(bundleID: Self.agentID)])
    }

    @Test func anAgentThatIgnoresSIGTERMIsReported() async throws {
        let fixture = try Fixture()
        let launchd = FakeLaunchd([Self.process(10, fixture.agentExecutable)],
                                  relaunch: nil, exitsOnSignal: false)
        let results = await restart(fixture, launchd)
        #expect(results == [.stillRunning(bundleID: Self.agentID)])
    }

    @Test func anAgentNobodyRelaunchesIsReported() async throws {
        let fixture = try Fixture()
        let launchd = FakeLaunchd([Self.process(10, fixture.agentExecutable)], relaunch: nil)
        let results = await restart(fixture, launchd)
        #expect(results == [.notRelaunched(bundleID: Self.agentID)])
    }

    /// The old process being gone is not enough: the new one must run from the
    /// agent's path in the live bundle.
    /// Mutation: accept any new process in the relaunch wait → `.restarted`, red.
    @Test func aNewProcessElsewhereDoesNotCountAsTheAgent() async throws {
        let fixture = try Fixture()
        let launchd = FakeLaunchd([Self.process(10, fixture.agentExecutable)],
                                  relaunch: (pid: 30, path: "/usr/bin/zzunrelated"))
        let results = await restart(fixture, launchd)
        #expect(results == [.notRelaunched(bundleID: Self.agentID)])
    }

    /// An agent that was not running stays off: nothing is signalled and
    /// nothing is reported.
    @Test func anAgentThatWasNotRunningIsLeftOff() async throws {
        let fixture = try Fixture()
        let launchd = FakeLaunchd([], relaunch: (pid: 30, path: fixture.agentExecutable))
        let results = await restart(fixture, launchd)
        #expect(results.isEmpty)
        #expect(launchd.signals.isEmpty)
    }

    /// Mutation: spell the bundle with `resolvingSymlinksInPath` in
    /// `agentBundles` → under `/private/tmp` it reads `/tmp/…`, no process
    /// matches, red.
    @Test func aBundleUnderPrivateIsMatchedAsTheKernelSpellsIt() throws {
        let fixture = try Fixture()
        #expect(fixture.hostPath.hasPrefix("/private/"))
        let snapshot = LoginItemAgentRestart.snapshot(
            bundle: URL(fileURLWithPath: fixture.hostPath), agentBundleIDs: [Self.agentID],
            processes: { [Self.process(10, fixture.agentExecutable)] })
        #expect(snapshot.first?.processes.map(\.pid) == [10])
    }

    /// The real process list carries this test process with its own path and
    /// a start time, and keeps listing pids whatever their path.
    @Test func theLiveListHasThisProcess() throws {
        let me = try #require(LoginItemAgentRestart.liveProcesses().first { $0.pid == getpid() })
        #expect(me.startTime > 0)
        #expect(!me.executablePath.isEmpty)
    }

    // MARK: - Registry and install path

    @Test func secretiveDeclaresItsAgent() {
        let app = InstalledApp(
            name: "Secretive", bundleID: "com.maxgoedjen.Secretive.Host",
            shortVersion: "3.0.4", buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Secretive.app"),
            isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: nil)
        #expect(LoginItemAgentRestart.declaredAgents(for: app) == ["com.maxgoedjen.Secretive.SecretAgent"])
        let other = InstalledApp(
            name: "ZZ", bundleID: "com.example.zz", shortVersion: "1", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/ZZ.app"),
            isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: nil)
        #expect(LoginItemAgentRestart.declaredAgents(for: other) == nil)
    }

    /// Through `InstallCoordinator.fetchThenSwap` for a host whose recipe
    /// declares an agent (Secretive's id on an invented bundle): the agent is
    /// signalled only after the apply.
    /// Mutation: drop the `restartLoginItemAgents` call in `swap` → no signal,
    /// red; call it before `apply` → `signalledBeforeApply`, red.
    @Test func theInstallPathRestartsTheAgentAfterTheSwap() async throws {
        let fixture = try Fixture(agentID: "com.maxgoedjen.Secretive.SecretAgent")
        let launchd = FakeLaunchd([Self.process(10, fixture.agentExecutable)],
                                  relaunch: (pid: 30, path: fixture.agentExecutable))
        let (outcome, signalledBeforeApply) = try await swap(fixture, launchd)
        #expect(outcome.applied)
        #expect(launchd.signals == [.init(pid: 10, signal: SIGTERM)])
        #expect(!signalledBeforeApply)
        #expect(outcome.agentsNotRestarted.isEmpty)
    }

    /// One that does not come back is in the outcome, and the install still
    /// counts as applied. (About 5 s: the coordinator's own exit wait.)
    /// Mutation: return `[]` from `restartLoginItemAgents` → red.
    @Test func theInstallPathReportsAnAgentThatDidNotComeBack() async throws {
        let fixture = try Fixture(agentID: "com.maxgoedjen.Secretive.SecretAgent")
        let launchd = FakeLaunchd([Self.process(10, fixture.agentExecutable)],
                                  relaunch: nil, exitsOnSignal: false)
        let (outcome, _) = try await swap(fixture, launchd)
        #expect(outcome.applied)
        #expect(outcome.agentsNotRestarted == ["com.maxgoedjen.Secretive.SecretAgent"])
    }

    private func swap(
        _ fixture: Fixture, _ launchd: FakeLaunchd
    ) async throws -> (InstallCoordinator.Outcome, signalledBeforeApply: Bool) {
        let applied = Flag()
        let signalledBeforeApply = Flag()
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1),
            runningProcesses: { [] },
            agentProcesses: launchd.list,
            signalAgent: { pid, signal in
                if !applied.value { signalledBeforeApply.set() }
                launchd.send(pid, signal)
            })
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let result = UpdateResult(
            app: InstalledApp(
                name: "ZZHost", bundleID: "com.maxgoedjen.Secretive.Host",
                shortVersion: "1.0", buildVersion: "1", path: fixture.host,
                isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: nil),
            remote: RemoteVersion(shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "GitHub"),
            status: .updateAvailable(latest: "1.1"))
        let outcome = try await coordinator.fetchThenSwap(
            result, spaceToApply: 0, progress: { _ in }, releaseAfterDownload: {},
            download: { _, _ in
                DownloadedUpdate(
                    archiveURL: workDir.appendingPathComponent("ZZ.zip"), bytesDownloaded: 1, workDir: workDir)
            },
            apply: { _, _, _ in
                applied.set()
                launchd.swapDeletesExecutables()
            })
        return (outcome, signalledBeforeApply.value)
    }

    // MARK: - Naming an agent in a notice

    /// What the app's notice calls an agent that did not come back: the last
    /// component of its id, the id as given when that component is empty.
    @Test func displayNameIsTheLastComponentOfTheID() {
        #expect(LoginItemAgentRestart.displayName(
            forAgentBundleID: "com.maxgoedjen.Secretive.SecretAgent") == "SecretAgent")
        #expect(LoginItemAgentRestart.displayName(forAgentBundleID: "SecretAgent") == "SecretAgent")
        #expect(LoginItemAgentRestart.displayName(forAgentBundleID: "com.example.") == "com.example.")
        #expect(LoginItemAgentRestart.displayName(forAgentBundleID: "") == "")
    }

    // MARK: - Helpers

    private func restart(_ fixture: Fixture, _ launchd: FakeLaunchd) async -> [LoginItemAgentRestart.Result] {
        let snapshot = LoginItemAgentRestart.snapshot(
            bundle: fixture.host, agentBundleIDs: [Self.agentID], processes: launchd.list)
        launchd.swapDeletesExecutables()
        return await LoginItemAgentRestart.restart(
            snapshot, processes: launchd.list, signal: launchd.send,
            exitTimeout: .milliseconds(200), relaunchTimeout: .milliseconds(200),
            pollInterval: .milliseconds(10))
    }

    static func process(_ pid: pid_t, _ path: String) -> LoginItemAgentRestart.Process {
        LoginItemAgentRestart.Process(pid: pid, startTime: UInt64(pid) * 1000, executablePath: path)
    }

    /// `ZZHost.app` with `Contents/Library/LoginItems/ZZAgent.app` (id
    /// `agentID`) and an undeclared `ZZOther.app` beside it.
    struct Fixture {
        let host: URL
        var hostPath: String { host.path }
        var agentPath: String { hostPath + "/Contents/Library/LoginItems/ZZAgent.app" }
        var agentExecutable: String { agentPath + "/Contents/MacOS/ZZAgent" }

        init(agentID: String = LoginItemAgentRestartTests.agentID) throws {
            let created = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZZFixture-agents-\(UUID().uuidString)/ZZHost.app", isDirectory: true)
            let items = created.appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)
            for (name, id) in [("ZZAgent", agentID), ("ZZOther", "com.example.zzhost.other")] {
                let contents = items.appendingPathComponent("\(name).app/Contents", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
                let plist = try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": id, "CFBundleExecutable": name],
                    format: .xml, options: 0)
                try plist.write(to: contents.appendingPathComponent("Info.plist"))
            }
            // Spelled as the kernel spells it, now that it exists: `/var/…` →
            // `/private/var/…` (`resolvingSymlinksInPath` would strip it).
            host = URL(fileURLWithPath: LoginItemAgentRestart.kernelPath(created.path), isDirectory: true)
        }
    }

    /// A process table and launchd in one: `SIGTERM` removes the process and,
    /// when `relaunch` is set, starts a new one.
    final class FakeLaunchd: @unchecked Sendable {
        struct Sent: Equatable { let pid: pid_t; let signal: Int32 }
        private let lock = NSLock()
        private var table: [LoginItemAgentRestart.Process]
        private var sent: [Sent] = []
        private let relaunch: (pid: pid_t, path: String)?
        private let exitsOnSignal: Bool

        init(_ table: [LoginItemAgentRestart.Process], relaunch: (pid: pid_t, path: String)?,
             exitsOnSignal: Bool = true) {
            self.table = table
            self.relaunch = relaunch
            self.exitsOnSignal = exitsOnSignal
        }

        var signals: [Sent] { lock.withLock { sent } }

        /// What a real swap does to the old processes' listing: their
        /// executables are deleted, so the kernel has no path for them.
        func swapDeletesExecutables() {
            lock.withLock {
                table = table.map {
                    LoginItemAgentRestart.Process(pid: $0.pid, startTime: $0.startTime, executablePath: "")
                }
            }
        }

        var list: @Sendable () -> [LoginItemAgentRestart.Process] {
            { [self] in lock.withLock { table } }
        }

        var send: @Sendable (pid_t, Int32) -> Void {
            { [self] pid, signal in
                lock.withLock {
                    sent.append(Sent(pid: pid, signal: signal))
                    guard exitsOnSignal else { return }
                    table.removeAll { $0.pid == pid }
                    if let relaunch {
                        table.append(LoginItemAgentRestartTests.process(relaunch.pid, relaunch.path))
                    }
                }
            }
        }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var on = false
        func set() { lock.withLock { on = true } }
        var value: Bool { lock.withLock { on } }
    }
}
