import Foundation
import Testing
@testable import DuoUpdaterCore

/// `RelaunchRecheck`: whether what we installed is still on disk after the
/// relaunch that put it into effect. The sleep is a no-op and the reads come
/// from a script, so nothing here waits on a clock.
struct RelaunchRecheckTests {

    private let chatGPT = InstalledApp(
        name: "ChatGPT", bundleID: "com.openai.codex",
        shortVersion: "1.0", buildVersion: "41705",
        path: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
        isMASApp: false, sparkleFeedURL: nil,
        hasSelfUpdater: false, hasSparkleUpdater: true)

    /// The script the fake disk and launchd play back, one entry per read.
    private final class World: @unchecked Sendable {
        var reads: [RelaunchRecheck.Reading?]
        var alive: Set<pid_t> = []
        /// Installer pids that die once this many reads have happened.
        var diesAfterRead: [pid_t: Int] = [:]
        var readCount = 0
        var sleeps = 0
        init(_ reads: [RelaunchRecheck.Reading?]) { self.reads = reads }
    }

    private func system(_ w: World) -> RelaunchRecheck.System {
        RelaunchRecheck.System(
            read: {
                defer { w.readCount += 1 }
                for (pid, after) in w.diesAfterRead where w.readCount + 1 >= after {
                    w.alive.remove(pid)
                }
                // Past the end of the script the disk keeps its last state.
                return w.reads.isEmpty ? nil : w.reads[min(w.readCount, w.reads.count - 1)]
            },
            sleep: { _ in w.sleeps += 1 },
            installer: ParkedInstallerProbe.System(
                isAlive: { w.alive.contains($0) },
                loadedJob: { _ in nil },
                sparkleInstallerPIDs: { _ in Array(w.alive) }))
    }

    private func reading(_ marketing: String?, _ build: String?, inode: UInt64 = 1) -> RelaunchRecheck.Reading {
        .init(side: VersionSide(marketing: marketing, build: build), inode: inode)
    }

    /// ChatGPT's builds as measured on the mini 2026-08-22 (41705 installed,
    /// 41509 back on disk after the relaunch). The marketing strings are not
    /// from that log; both sides carry the same one so the builds decide, as
    /// they did for a frozen-marketing app.
    private let ours = RelaunchRecheck.Reading(side: VersionSide(marketing: "1.0", build: "41705"), inode: 1)

    // MARK: - reverted

    /// The measured shape: ours holds for a while, then Autoupdate writes the
    /// older build in place (same inode). Decided on the first backward read,
    /// not at the end of the window. Mutation: compare by string inequality →
    /// a respelt "41705.0" would read as reverted; compare marketing only →
    /// held, red.
    @Test func revertToTheOlderBuildIsReported() async {
        var script = Array(repeating: Optional(ours), count: 17)
        script.append(reading("1.0", "41509"))
        let w = World(script)
        let verdict = await RelaunchRecheck.watch(expected: ours, installer: nil, system: system(w))
        #expect(verdict == .reverted(to: VersionSide(marketing: "1.0", build: "41509"), bundleSwapped: false))
        #expect(w.readCount == 18, "stops on the backward read")
    }

    /// ShipIt's shape: the bundle is moved away (unreadable for a read), then
    /// another, older bundle is moved into its place — new inode, lower version.
    @Test func aSwappedOlderBundleIsReported() async {
        let theirs = reading("0.14.3", "0.14.3", inode: 99)
        let mine = reading("0.14.4", "0.14.4", inode: 1)
        let w = World([mine, mine, nil, theirs])
        let verdict = await RelaunchRecheck.watch(expected: mine, installer: nil, system: system(w))
        #expect(verdict == .reverted(to: theirs.side, bundleSwapped: true))
    }

    /// A newer build showing up (the app moved on by itself) is not a revert;
    /// nor is a respelling of the same version.
    @Test func newerOrRespeltIsNotAReversion() async {
        let w = World([reading("1.0", "41705.0"), reading("1.1", "41800")])
        let verdict = await RelaunchRecheck.watch(expected: ours, installer: nil, system: system(w))
        #expect(verdict == .held)
    }

    // MARK: - held

    /// Nobody visible was waiting on the quit (Sparkle 1's case: its installer
    /// starts only after the quit) — so the whole window is read, and ours held.
    @Test func heldForTheWholeWindowWithNoInstallerInSight() async {
        let w = World([ours])
        let timing = RelaunchRecheck.Timing()
        let verdict = await RelaunchRecheck.watch(expected: ours, installer: nil, timing: timing, system: system(w))
        #expect(verdict == .held)
        #expect(w.readCount == timing.maxReads, "no installer seen → no early stop")
        #expect(timing.maxReads == 30, "60 s at one read every 2 s")
    }

    /// The installer was there at the quit, then exited, and ours stayed: stop
    /// after `settleReads` agreeing reads rather than the full window.
    @Test func installerGoneAndVersionHeldStopsEarly() async {
        let w = World([ours])
        w.alive = [50656]
        w.diesAfterRead = [50656: 4]
        let probe = await ParkedInstallerProbe.find(for: chatGPT, staged: nil, system: system(w).installer)
        #expect(probe != nil)
        let verdict = await RelaunchRecheck.watch(expected: ours, installer: probe, system: system(w))
        #expect(verdict == .held)
        // Alive through read 3, gone from read 4, which is the first of three
        // agreeing reads after it.
        #expect(w.readCount == 6)
    }

    /// The installer replaced the bundle with the same version (TablePlus's
    /// staged-equals-ours case) — a swap that landed on ours ends the watch
    /// once it settles, even with no installer probe.
    @Test func aSwapToTheSameVersionSettlesEarly() async {
        let same = reading("1.0", "41705", inode: 7)
        let w = World([ours, same])
        let verdict = await RelaunchRecheck.watch(expected: ours, installer: nil, system: system(w))
        #expect(verdict == .held)
        #expect(w.readCount == 4)
    }

    // MARK: - unknown

    /// The installer is still parked when the window closes: it may yet act,
    /// so nothing is concluded.
    @Test func installerStillAliveAtTimeoutIsUnknown() async {
        let w = World([ours])
        w.alive = [50656]
        let probe = await ParkedInstallerProbe.find(for: chatGPT, staged: nil, system: system(w).installer)
        let timing = RelaunchRecheck.Timing()
        let verdict = await RelaunchRecheck.watch(expected: ours, installer: probe, timing: timing, system: system(w))
        #expect(verdict == .unknown)
        #expect(w.readCount == timing.maxReads)
    }

    /// The bundle could not be read at the end of the window (moved away and
    /// not put back): unknown, not held.
    @Test func unreadableAtTimeoutIsUnknown() async {
        let w = World([ours, nil])
        let verdict = await RelaunchRecheck.watch(expected: ours, installer: nil, system: system(w))
        #expect(verdict == .unknown)
    }

    /// A cancelled watch (a new restart or install of the row) concludes
    /// nothing.
    @Test func cancelledWatchIsUnknown() async {
        let w = World([reading("1.0", "41509")])
        let sys = system(w)
        let expected = ours
        // Cancelled from inside before the watch starts, so there is no race
        // with the first read.
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await RelaunchRecheck.watch(expected: expected, installer: nil, system: sys)
        }
        #expect(await task.value == .unknown)
        #expect(w.readCount == 0)
    }
}
