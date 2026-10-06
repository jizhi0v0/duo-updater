import Foundation
import Testing
@testable import DuoUpdaterCore

/// `ParkedInstallerProbe`: what the Relaunch wait counts as an installer still
/// at work. Every fake system here is a launchd state seen or read for real —
/// ShipIt's job comes back after a failed attempt (`KeepAlive` on a failed
/// exit), Sparkle's does not.
struct ParkedInstallerProbeTests {

    private let claude = InstalledApp(
        name: "Claude", bundleID: "com.anthropic.claudefordesktop",
        shortVersion: "1.0", buildVersion: "100",
        path: URL(fileURLWithPath: "/Applications/Claude.app"),
        isMASApp: false, sparkleFeedURL: nil,
        hasSelfUpdater: true, hasSparkleUpdater: false)

    private let chatGPT = InstalledApp(
        name: "ChatGPT", bundleID: "com.openai.codex",
        shortVersion: "26.924.22138", buildVersion: "11645",
        path: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
        isMASApp: false, sparkleFeedURL: nil,
        hasSelfUpdater: false, hasSparkleUpdater: true)

    private func staged(_ updater: StagedUpdater?) -> StagedSelfUpdate {
        StagedSelfUpdate(version: "1.1", buildVersion: "110",
                         stagedBundlePath: URL(fileURLWithPath: "/ZZFixture/Staged.app"),
                         updater: updater)
    }

    /// Mutable launchd state the fake system reads on every call.
    private final class World: @unchecked Sendable {
        var alive: Set<pid_t> = []
        var jobs: [String: ParkedInstallerProbe.LoadedJob] = [:]
        var sparklePIDs: [pid_t] = []
        var jobQueries = 0
    }

    private func system(_ w: World) -> ParkedInstallerProbe.System {
        ParkedInstallerProbe.System(
            isAlive: { w.alive.contains($0) },
            loadedJob: { w.jobQueries += 1; return w.jobs[$0] },
            sparkleInstallerPIDs: { _ in w.sparklePIDs })
    }

    private let label = "com.anthropic.claudefordesktop.ShipIt"

    // MARK: - find

    /// A ShipIt staging is watched through `<bundle id>.ShipIt`, and only when
    /// that job is loaded. Mutations: another label → nil, red; skip the loaded
    /// check → a probe for a job that is not there, red.
    @Test func findsShipItByItsJobLabel() async {
        let w = World()
        #expect(await ParkedInstallerProbe.find(
            for: claude, staged: staged(.shipIt), system: system(w)) == nil,
            "job not loaded (e.g. submitted to the system domain) — no probe, full wait")
        w.jobs[label] = .init(pid: 44580)
        let probe = await ParkedInstallerProbe.find(
            for: claude, staged: staged(.shipIt), system: system(w))
        #expect(probe?.target == .shipIt(label: label))
        #expect(probe?.shipItPID == 44580)
    }

    /// ChatGPT's case: nothing readable staged, a Sparkle app, Autoupdate found.
    /// No pids → no probe.
    @Test func findsSparkleByItsInstallerPIDs() async {
        let w = World()
        #expect(await ParkedInstallerProbe.find(for: chatGPT, staged: nil, system: system(w)) == nil)
        w.sparklePIDs = [54075]
        #expect(await ParkedInstallerProbe.find(for: chatGPT, staged: nil, system: system(w))?.target
                == .sparkle(pids: [54075]))
        #expect(await ParkedInstallerProbe.find(for: claude, staged: nil, system: system(w)) == nil,
                "neither a ShipIt staging nor a Sparkle app")
    }

    // MARK: - isAlive, ShipIt

    /// A failed attempt exits non-zero and launchd runs ShipIt again (VS Code
    /// 2026-10-06: ~15 ms later, three times). In that gap the job is loaded
    /// with no pid and a failed last exit — still alive. Judging by the pid
    /// alone would give up here and reopen the app, which makes the respawned
    /// ShipIt abort with "App Still Running". Mutation: return `false` when the
    /// pid is dead without asking for the job → red.
    @Test func aShipItWaitingToBeRunAgainIsAlive() async throws {
        let w = World()
        w.jobs[label] = .init(pid: 40929)
        var probe = try #require(await ParkedInstallerProbe.find(for: claude, staged: staged(.shipIt), system: system(w)))
        w.jobs[label] = .init(pid: nil, lastExitStatus: 256)
        #expect(await probe.isAlive(system: system(w)))
    }

    /// VS Code 2026-10-06, after "Too many attempts to install, aborting
    /// update": the job stays loaded (it has a Mach service) with
    /// `LastExitStatus = 0` and no pid. Nothing runs it again — that is the
    /// verdict. Before this test the probe read "still loaded" as alive and the
    /// wait ran its full 200 s. Mutation: drop the exit-status check (loaded is
    /// alive) → red.
    @Test func aShipItThatExitedCleanlyIsDoneThoughStillLoaded() async throws {
        let w = World()
        w.jobs[label] = .init(pid: 96605)
        var probe = try #require(await ParkedInstallerProbe.find(for: claude, staged: staged(.shipIt), system: system(w)))
        w.jobs[label] = .init(pid: nil, lastExitStatus: 0)
        #expect(!(await probe.isAlive(system: system(w))))
    }

    /// The respawned ShipIt is followed: once its job is unloaded (macOS 27
    /// stopping the app's background activity), the process it left still
    /// counts until it actually exits. Mutation: drop `shipItPID = pid` → the
    /// second expectation goes red.
    @Test func followsTheRespawnedShipItAfterItsJobIsUnloaded() async throws {
        let w = World()
        w.jobs[label] = .init(pid: 40929)
        var probe = try #require(await ParkedInstallerProbe.find(for: claude, staged: staged(.shipIt), system: system(w)))
        w.jobs[label] = .init(pid: 77598)
        #expect(await probe.isAlive(system: system(w)))
        w.alive = [77598]
        w.jobs[label] = nil
        #expect(await probe.isAlive(system: system(w)), "unloaded, but its process has not exited yet")
        w.alive = []
        #expect(!(await probe.isAlive(system: system(w))))
    }

    /// No `launchctl` while the ShipIt process runs — the wait asks every
    /// 200 ms. Mutation: query the job first → red.
    @Test func aRunningShipItCostsNoLaunchctl() async throws {
        let w = World()
        w.jobs[label] = .init(pid: 65955)
        var probe = try #require(await ParkedInstallerProbe.find(for: claude, staged: staged(.shipIt), system: system(w)))
        let before = w.jobQueries
        w.alive = [65955]
        #expect(await probe.isAlive(system: system(w)))
        #expect(w.jobQueries == before)
    }

    // MARK: - isAlive, Sparkle

    /// Any of the watched pids still running is alive; all gone is not.
    @Test func sparkleIsAliveWhileAnyPIDRuns() async throws {
        let w = World()
        w.sparklePIDs = [802, 803]
        var probe = try #require(await ParkedInstallerProbe.find(for: chatGPT, staged: nil, system: system(w)))
        w.alive = [803]
        #expect(await probe.isAlive(system: system(w)))
        w.alive = []
        #expect(!(await probe.isAlive(system: system(w))))
    }

    // MARK: - launchctl list parsing

    /// `launchctl list <label>` as it prints a running job and one between runs
    /// (shape copied from this machine, 2026-10-06).
    @Test func readsTheFieldsOfAJobDescription() {
        let running = """
        {
        \t"LimitLoadToSessionType" = "Aqua";
        \t"Label" = "com.apple.progressd";
        \t"LastExitStatus" = 0;
        \t"PID" = 5270;
        \t"Program" = "/System/Library/Frameworks/ClassKit.framework/Versions/A/progressd";
        };
        """
        #expect(ParkedInstallerProbe.field("PID", inJobDescription: running) == 5270)
        #expect(ParkedInstallerProbe.field("LastExitStatus", inJobDescription: running) == 0)
        let killed = """
        {
        \t"Label" = "com.apple.intelligenceplatformd";
        \t"LastExitStatus" = 9;
        };
        """
        #expect(ParkedInstallerProbe.field("PID", inJobDescription: killed) == nil)
        #expect(ParkedInstallerProbe.field("LastExitStatus", inJobDescription: killed) == 9)
        #expect(ParkedInstallerProbe.field("LastExitStatus", inJobDescription: "{\n\t\"LastExitStatus\" = -1;\n};") == -1)
    }
}
