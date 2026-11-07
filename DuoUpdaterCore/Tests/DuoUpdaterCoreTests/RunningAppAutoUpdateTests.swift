import Foundation
import Testing
@testable import DuoUpdaterCore

struct RunningAppAutoUpdateTests {
    typealias Policy = RunningAppAutoUpdate
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    /// An entry and signals that pass every rule, so each test below changes
    /// exactly one thing and the verdict it gets is that rule's.
    var eligibleEntry: Policy.Entry {
        .init(version: "2.0", firstSeen: now.addingTimeInterval(-Policy.releaseCooldown - 1))
    }
    var eligibleSignals: Policy.Signals {
        .init(isFrontmost: false, lastUsed: now.addingTimeInterval(-Policy.idleThreshold - 1),
              userIdle: Policy.userAwayThreshold + 1, screenLocked: false,
              busyAssertion: nil, hasForeignChild: false)
    }

    @Test func baselineIsEligible() {
        #expect(Policy.decide(entry: eligibleEntry, signals: eligibleSignals, now: now) == .quitAndUpdate)
    }

    @Test func eachRuleHoldsTheQuitBack() {
        var entry = eligibleEntry
        entry.gaveUp = true
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: now) == .wait(.gaveUp))

        entry = eligibleEntry
        entry.firstSeen = now.addingTimeInterval(-Policy.releaseCooldown + 60)
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: now) == .wait(.cooldown))

        entry = eligibleEntry
        entry.lastQuit = now.addingTimeInterval(-Policy.quitSpacing + 60)
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: now) == .wait(.quitToday))

        var signals = eligibleSignals
        signals.isFrontmost = true
        #expect(Policy.decide(entry: eligibleEntry, signals: signals, now: now) == .wait(.frontmost))

        signals = eligibleSignals
        signals.lastUsed = now.addingTimeInterval(-Policy.idleThreshold + 60)
        #expect(Policy.decide(entry: eligibleEntry, signals: signals, now: now) == .wait(.recentlyUsed))

        signals = eligibleSignals
        signals.userIdle = Policy.userAwayThreshold - 60
        #expect(Policy.decide(entry: eligibleEntry, signals: signals, now: now) == .wait(.personPresent))

        signals = eligibleSignals
        signals.busyAssertion = "Video call"
        #expect(Policy.decide(entry: eligibleEntry, signals: signals, now: now) == .wait(.busy("Video call")))

        signals = eligibleSignals
        signals.hasForeignChild = true
        #expect(Policy.decide(entry: eligibleEntry, signals: signals, now: now) == .wait(.childProcess))
    }

    @Test func lockedScreenStandsInForAnAbsentPerson() {
        var signals = eligibleSignals
        signals.userIdle = 0
        signals.screenLocked = true
        #expect(Policy.decide(entry: eligibleEntry, signals: signals, now: now) == .quitAndUpdate)
    }

    @Test func newVersionResetsCooldownAndFailuresButKeepsTheDailyCap() {
        var ledger = Policy.Ledger()
        let first = ledger.observe("k", version: "1.0", now: now)
        #expect(first.firstSeen == now)
        // Same version later: the first sighting stands, or the cooldown never ends.
        #expect(ledger.observe("k", version: "1.0", now: now.addingTimeInterval(3600)).firstSeen == now)

        ledger.recordQuit("k", now: now)
        ledger.recordQuitRefused("k")
        #expect(ledger.entries["k"]?.gaveUp == true)

        let later = now.addingTimeInterval(7200)
        let next = ledger.observe("k", version: "1.1", now: later)
        #expect(next.firstSeen == later)
        #expect(!next.gaveUp)
        #expect(next.failures == 0)
        #expect(next.lastQuit == now)
    }

    @Test func givesUpOnlyAtTheFailureLimit() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1.0", now: now)
        for _ in 1..<Policy.maxFailures { ledger.recordFailure("k") }
        #expect(ledger.entries["k"]?.gaveUp == false)
        ledger.recordFailure("k")
        #expect(ledger.entries["k"]?.gaveUp == true)
    }

    @Test func retainDropsOnlyUnlistedInstalls() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("a", version: "1", now: now)
        _ = ledger.observe("b", version: "1", now: now)
        ledger.retain(keys: ["a"])
        #expect(Set(ledger.entries.keys) == ["a"])
    }

    @Test func ledgerRoundTripsThroughJSON() throws {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1.0", now: now)
        ledger.recordQuit("k", now: now)
        let data = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(Policy.Ledger.self, from: data) == ledger)
    }

    // MARK: - Assertions

    @Test func assertionsCountForOwnerAndOnBehalfButNotUserActivity() {
        let byPID: [Int: [[String: Any]]] = [
            100: [["AssertType": "UserIsActive", "AssertName": "tickle"]],
            200: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Downloading"]],
            314: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "audio",
                   "AssertionOnBehalfOfPID": NSNumber(value: 511)]],
        ]
        #expect(Policy.busyAssertion(in: byPID, pids: [100]) == nil)
        #expect(Policy.busyAssertion(in: byPID, pids: [200]) == "Downloading")
        #expect(Policy.busyAssertion(in: byPID, pids: [511]) == "audio")
        #expect(Policy.busyAssertion(in: byPID, pids: [999]) == nil)
    }

    // MARK: - Child processes

    private func process(_ pid: pid_t, parent: pid_t, _ path: String) -> NestedAppGuard.RunningProcess {
        .init(pid: pid, parentPID: parent, executablePath: path, isRegularApp: false)
    }

    /// Children by parent, as the kernel would list them, from the fixtures.
    private func children(of processes: [NestedAppGuard.RunningProcess]) -> (pid_t) -> [pid_t] {
        { parent in processes.filter { $0.parentPID == parent }.map(\.pid) }
    }

    @Test func foreignChildIsAProcessOutsideTheBundleStartedByIt() {
        let bundle = URL(fileURLWithPath: "/Applications/Term.app")
        let app = process(10, parent: 1, "/Applications/Term.app/Contents/MacOS/Term")
        let helper = process(11, parent: 10, "/Applications/Term.app/Contents/Frameworks/Helper")
        let shell = process(12, parent: 10, "/bin/zsh")
        let unrelated = process(13, parent: 1, "/bin/zsh")
        let quiet = [app, helper, unrelated]
        #expect(!Policy.hasForeignChild(of: bundle, processes: quiet, children: children(of: quiet)))
        let busy = [app, helper, shell]
        #expect(Policy.hasForeignChild(of: bundle, processes: busy, children: children(of: busy)))
        // A shell started by an in-bundle helper counts too.
        let viaHelper = [app, helper, process(14, parent: 11, "/bin/sh")]
        #expect(Policy.hasForeignChild(of: bundle, processes: viaHelper, children: children(of: viaHelper)))
    }

    /// The real-machine miss: a root `login` the process list cannot place (it
    /// is absent, or carries parent 0) is still the app's child to the kernel.
    @Test func childMissingFromTheProcessListStillCounts() {
        let bundle = URL(fileURLWithPath: "/Applications/Term.app")
        let app = process(10, parent: 1, "/Applications/Term.app/Contents/MacOS/Term")
        let login = process(20, parent: 0, "/usr/bin/login")
        #expect(Policy.hasForeignChild(of: bundle, processes: [app, login], children: { $0 == 10 ? [20] : [] }))
        #expect(Policy.hasForeignChild(of: bundle, processes: [app], children: { $0 == 10 ? [20] : [] }))
    }

    @Test func kernelListsALiveChild() async throws {
        let (pids, continuation) = AsyncStream.makeStream(of: pid_t.self)
        let child = Task {
            try await ChildProcess.run("/bin/sleep", ["30"], standardOutput: .discard, standardError: .discard,
                                       onCancel: .terminateChild, onLaunch: { continuation.yield($0) })
        }
        defer { child.cancel() }
        var iterator = pids.makeAsyncIterator()
        let pid = try #require(await iterator.next())
        #expect(Policy.childPIDs(getpid()).contains(pid))
    }
}
