import Foundation
import Testing
@testable import DuoUpdaterCore

struct RunningAppAutoUpdateTests {
    typealias Policy = RunningAppAutoUpdate
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let delayMinutes = 30
    var delay: TimeInterval { TimeInterval(delayMinutes * 60) }

    func decide(_ entry: Policy.Entry, _ signals: Policy.Signals) -> Policy.Verdict {
        Policy.decide(entry: entry, signals: signals, now: now, delayMinutes: delayMinutes)
    }

    /// An entry and signals that pass every rule, so each test below changes
    /// exactly one thing and the verdict it gets is that rule's.
    var eligibleEntry: Policy.Entry {
        .init(version: "2.0", behindSince: now.addingTimeInterval(-delay - 1))
    }
    var eligibleSignals: Policy.Signals {
        .init(isFrontmost: false, lastUsed: now.addingTimeInterval(-Policy.idleThreshold - 1),
              userIdle: Policy.userAwayThreshold + 1, screenLocked: false,
              busyAssertion: nil, hasForeignChild: false)
    }

    @Test func baselineIsEligible() {
        #expect(decide(eligibleEntry, eligibleSignals) == .quitAndUpdate)
    }

    @Test func eachRuleHoldsTheQuitBack() {
        var entry = eligibleEntry
        entry.gaveUp = true
        #expect(decide(entry, eligibleSignals) == .wait(.gaveUp))

        entry = eligibleEntry
        entry.retryAfter = now.addingTimeInterval(60)
        #expect(decide(entry, eligibleSignals) == .wait(.retryLater))

        entry = eligibleEntry
        entry.behindSince = now.addingTimeInterval(-delay + 60)
        #expect(decide(entry, eligibleSignals) == .wait(.delay(30)))

        entry = eligibleEntry
        entry.lastQuit = now.addingTimeInterval(-delay + 60)
        #expect(decide(entry, eligibleSignals) == .wait(.recentlyQuit(30)))

        var signals = eligibleSignals
        signals.isFrontmost = true
        #expect(decide(eligibleEntry, signals) == .wait(.frontmost))

        signals = eligibleSignals
        signals.lastUsed = now.addingTimeInterval(-Policy.idleThreshold + 60)
        #expect(decide(eligibleEntry, signals) == .wait(.recentlyUsed))

        signals = eligibleSignals
        signals.userIdle = Policy.userAwayThreshold - 60
        #expect(decide(eligibleEntry, signals) == .wait(.personPresent))

        signals = eligibleSignals
        signals.busyAssertion = "Video call"
        #expect(decide(eligibleEntry, signals) == .wait(.busy("Video call")))

        signals = eligibleSignals
        signals.hasForeignChild = true
        #expect(decide(eligibleEntry, signals) == .wait(.childProcess))
    }

    @Test func lockedScreenStandsInForAnAbsentPerson() {
        var signals = eligibleSignals
        signals.userIdle = 0
        signals.screenLocked = true
        #expect(decide(eligibleEntry, signals) == .quitAndUpdate)
    }

    @Test func newVersionKeepsTheCountButClearsFailures() {
        var ledger = Policy.Ledger()
        let first = ledger.observe("k", version: "1.0", now: now)
        #expect(first.behindSince == now)
        #expect(ledger.observe("k", version: "1.0", now: now.addingTimeInterval(3600)).behindSince == now)

        ledger.recordQuit("k", now: now)
        ledger.recordQuitRefused("k", now: now)
        #expect(ledger.entries["k"]?.gaveUp == true)

        // A newer release while still behind: the count started with the first one.
        let later = now.addingTimeInterval(7200)
        let next = ledger.observe("k", version: "1.1", now: later)
        #expect(next.version == "1.1")
        #expect(next.behindSince == now)
        #expect(!next.gaveUp)
        #expect(next.failures == 0)
        #expect(next.lastQuit == now)
        #expect(next.retryAfter == now.addingTimeInterval(Policy.retryBackoff))
    }

    /// A refused quit holds every later version back for the back-off, so an
    /// app that releases every few minutes is not asked again over its own
    /// save prompt.
    @Test func refusedQuitHoldsNewerVersionsBackForTheBackOff() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1", now: now.addingTimeInterval(-3600))
        ledger.recordQuit("k", now: now)
        ledger.recordQuitRefused("k", now: now)
        let later = now.addingTimeInterval(Policy.retryBackoff - 60)
        var entry = ledger.observe("k", version: "2", now: later)
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: later, delayMinutes: 30) == .wait(.retryLater))
        let after = now.addingTimeInterval(Policy.retryBackoff)
        entry = ledger.observe("k", version: "3", now: after)
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: after, delayMinutes: 30) == .quitAndUpdate)
    }

    @Test func failedUpdateHoldsTheNextTryBack() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1", now: now.addingTimeInterval(-3600))
        ledger.recordQuit("k", now: now)
        ledger.recordFailure("k", now: now)
        let at = now.addingTimeInterval(3600)
        let entry = ledger.observe("k", version: "2", now: at)
        #expect(entry.failures == 0)
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: at, delayMinutes: 30) == .wait(.retryLater))
    }

    /// An app that releases every few minutes is still updated once the delay is
    /// up: each release used to restart a day-long count, so it never was.
    @Test func frequentReleasesDoNotPostponeTheUpdate() {
        var ledger = Policy.Ledger()
        var entry = ledger.observe("k", version: "1", now: now)
        for minute in stride(from: 4, through: 28, by: 4) {
            let at = now.addingTimeInterval(TimeInterval(minute * 60))
            entry = ledger.observe("k", version: "\(minute)", now: at)
            #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: at, delayMinutes: 30) == .wait(.delay(30)))
        }
        let due = now.addingTimeInterval(delay)
        entry = ledger.observe("k", version: "30", now: due)
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: due, delayMinutes: 30) == .quitAndUpdate)
    }

    /// The next quit waits the delay after the last one, even when the entry
    /// survived (the next check already saw a newer version) and so still
    /// carries the old `behindSince`.
    @Test func quitsAreSpacedByTheDelay() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1", now: now.addingTimeInterval(-3600))
        ledger.recordQuit("k", now: now)
        let soon = now.addingTimeInterval(delay - 60)
        var entry = ledger.observe("k", version: "2", now: soon)
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: soon, delayMinutes: 30) == .wait(.recentlyQuit(30)))
        let due = now.addingTimeInterval(delay)
        entry = ledger.observe("k", version: "2", now: due)
        #expect(Policy.decide(entry: entry, signals: eligibleSignals, now: due, delayMinutes: 30) == .quitAndUpdate)
    }

    /// Ledgers written before the rename stored the start as `firstSeen`.
    @Test func decodesTheOldFieldName() throws {
        let json = #"{"entries":{"k":{"firstSeen":815801466.5,"gaveUp":false,"failures":0,"version":"0.43.2"}}}"#
        let ledger = try JSONDecoder().decode(Policy.Ledger.self, from: Data(json.utf8))
        #expect(ledger.entries["k"]?.behindSince == Date(timeIntervalSinceReferenceDate: 815801466.5))
    }

    @Test func givesUpOnlyAtTheFailureLimit() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1.0", now: now)
        for _ in 1..<Policy.maxFailures { ledger.recordFailure("k", now: now) }
        #expect(ledger.entries["k"]?.gaveUp == false)
        ledger.recordFailure("k", now: now)
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
