import Foundation
import Testing
@testable import DuoUpdaterCore

struct SetappUpdateSessionTests {
    private let a = URL(fileURLWithPath: "/Applications/Setapp/A.app")
    private let b = URL(fileURLWithPath: "/Applications/Setapp/B.app")

    private func sample(
        _ policy: inout SetappUpdateSessionPolicy, _ seconds: Int,
        same: Bool = true, adopted: Bool = false, valid: Bool = true,
        busy: Bool = false, witnessed: Bool = true, activity: Bool = false,
        completed: Set<URL> = []
    ) -> SetappUpdateSessionPolicy.Decision {
        policy.sample(at: .seconds(seconds), sameInstance: same, adopted: adopted,
                      observationValid: valid, busy: busy, witnessedSession: witnessed,
                      activity: activity, completed: completed)
    }

    @Test func waitsForAllSessionsThenThirtySecondsOfQuiet() {
        var policy = SetappUpdateSessionPolicy(targets: [a, b])
        #expect(sample(&policy, 5, busy: true) == .wait)
        // One overlapping session has finished; the other is still downloading.
        #expect(sample(&policy, 35, busy: true, completed: [a]) == .wait)
        #expect(sample(&policy, 75, activity: true, completed: [a, b]) == .wait)
        #expect(sample(&policy, 104, completed: [a, b]) == .wait)
        #expect(sample(&policy, 105, completed: [a, b]) == .quit)
    }

    @Test func aCompletionExtendsOnceAndRepeatedReadsCannotKeepItAlive() {
        var policy = SetappUpdateSessionPolicy(targets: [a, b])
        #expect(sample(&policy, 29, completed: [a]) == .wait)
        #expect(sample(&policy, 58, completed: [a, b]) == .wait)
        #expect(sample(&policy, 87, completed: [a, b]) == .wait)
        #expect(sample(&policy, 88, completed: [a, b]) == .quit)
    }

    @Test func aNewSessionRestartsTheIdleWindow() {
        var policy = SetappUpdateSessionPolicy(targets: [a])
        #expect(sample(&policy, 29, busy: true, activity: true) == .wait)
        #expect(sample(&policy, 31, activity: true) == .wait)
        #expect(sample(&policy, 60) == .wait)
        #expect(sample(&policy, 61) == .quit)
    }

    @Test func noWitnessDoesNotTurnSilenceIntoPermissionToQuit() {
        var policy = SetappUpdateSessionPolicy(targets: [a])
        #expect(sample(&policy, 29, witnessed: false) == .wait)
        #expect(sample(&policy, 30, witnessed: false) == .relinquish)
    }

    @Test func diskCompletionCanWitnessWorkWhenNotificationsWereMissed() {
        var policy = SetappUpdateSessionPolicy(targets: [a])
        #expect(sample(&policy, 5, witnessed: false, completed: [a]) == .wait)
        #expect(sample(&policy, 35, witnessed: false, completed: [a]) == .quit)
    }

    @Test func unknownStateAndUserAdoptionNeverQuit() {
        for scenario in 0..<3 {
            var policy = SetappUpdateSessionPolicy(targets: [a])
            #expect(sample(&policy, 40, same: scenario != 0, adopted: scenario == 1,
                           valid: scenario != 2) == .relinquish)
        }
    }

    @Test func aStuckSessionIsLeftRunningInsteadOfWaitedOnForever() {
        var policy = SetappUpdateSessionPolicy(targets: [a])
        #expect(sample(&policy, 599, busy: true) == .wait)
        #expect(sample(&policy, 600, busy: true) == .relinquish)
    }

    @Test func processIdentityIncludesBirthTimeEvenIfPIDIsReused() {
        let first = SetappProcessIdentity(pid: 42, launchedAt: Date(timeIntervalSince1970: 100))
        let replacement = SetappProcessIdentity(pid: 42, launchedAt: Date(timeIntervalSince1970: 101))
        #expect(first != replacement)
    }

    @Test func activeMarkersAreReadBySessionIDAndOldMarkersAreUnknown() {
        let now = Date(timeIntervalSince1970: 1000)
        let first = "F06FA5D5-F1D6-40BC-9C3C-D65ECA8609F6"
        let second = "0F6B3E73-D034-4E8D-94E9-41AFF478EDC9"
        let prefix = "account-ActiveRefreshSession_-reason_internal"
        #expect(SetappActiveSessions.read([prefix + first: now, prefix + second: now], now: now) == [first, second])
        #expect(SetappActiveSessions.read([:], now: now) == [])
        #expect(SetappActiveSessions.read(nil, now: now) == nil)
        #expect(SetappActiveSessions.read([prefix + first: now.addingTimeInterval(-300)], now: now) == nil)
        #expect(SetappActiveSessions.read([prefix + first: now.addingTimeInterval(5)], now: now) == nil)
        #expect(SetappActiveSessions.read([prefix + first: "unexpected"], now: now) == nil)
        #expect(SetappActiveSessions.read([prefix + "unknown": now], now: now) == nil)
    }
}
