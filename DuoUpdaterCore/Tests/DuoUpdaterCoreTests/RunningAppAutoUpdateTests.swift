import Foundation
import Testing
@testable import DuoUpdaterCore

struct RunningAppAutoUpdateTests {
    typealias Policy = RunningAppAutoUpdate
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func keepLatestStartsOnFirstObservation() {
        var ledger = Policy.Ledger()
        let entry = ledger.observe("k", version: "2.0", now: now)
        #expect(Policy.decide(entry: entry, now: now) == .quitAndUpdate)
    }

    @Test func keepLatestDoesNotSpaceSuccessfulUpdatesApart() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1", now: now)
        ledger.recordQuit("k", now: now)
        let next = ledger.observe("k", version: "2", now: now.addingTimeInterval(1))
        #expect(Policy.decide(entry: next, now: now.addingTimeInterval(1)) == .quitAndUpdate)
    }

    @Test func refusedQuitAndFailureHistoryStillHoldTheQuitBack() {
        var entry = Policy.Entry(version: "2.0", behindSince: now, gaveUp: true)
        #expect(Policy.decide(entry: entry, now: now) == .wait(.gaveUp))
        entry.gaveUp = false
        entry.retryAfter = now.addingTimeInterval(60)
        #expect(Policy.decide(entry: entry, now: now) == .wait(.retryLater))
        #expect(Policy.decide(entry: entry, now: now.addingTimeInterval(60)) == .quitAndUpdate)
    }

    @Test func newVersionKeepsHistoryButClearsFailures() {
        var ledger = Policy.Ledger()
        let first = ledger.observe("k", version: "1.0", now: now)
        #expect(first.behindSince == now)
        ledger.recordQuit("k", now: now)
        ledger.recordQuitRefused("k", now: now)
        let next = ledger.observe("k", version: "1.1", now: now.addingTimeInterval(1))
        #expect(next.version == "1.1")
        #expect(next.behindSince == now)
        #expect(next.lastQuit == now)
        #expect(!next.gaveUp)
        #expect(next.failures == 0)
        #expect(next.retryAfter == now.addingTimeInterval(Policy.retryBackoff))
    }

    @Test func refusedQuitHoldsNewerVersionsBackForTheBackOff() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1", now: now)
        ledger.recordQuitRefused("k", now: now)
        let later = now.addingTimeInterval(Policy.retryBackoff - 60)
        var entry = ledger.observe("k", version: "2", now: later)
        #expect(Policy.decide(entry: entry, now: later) == .wait(.retryLater))
        let after = now.addingTimeInterval(Policy.retryBackoff)
        entry = ledger.observe("k", version: "3", now: after)
        #expect(Policy.decide(entry: entry, now: after) == .quitAndUpdate)
    }

    @Test func failedUpdateHoldsTheNextTryBack() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("k", version: "1", now: now)
        ledger.recordFailure("k", now: now)
        let later = now.addingTimeInterval(3600)
        let entry = ledger.observe("k", version: "2", now: later)
        #expect(entry.failures == 0)
        #expect(Policy.decide(entry: entry, now: later) == .wait(.retryLater))
    }

    @Test func frequentReleasesAreEligibleAsSoonAsObserved() {
        var ledger = Policy.Ledger()
        for second in 0..<10 {
            let at = now.addingTimeInterval(TimeInterval(second))
            let entry = ledger.observe("k", version: "\(second)", now: at)
            #expect(Policy.decide(entry: entry, now: at) == .quitAndUpdate)
            ledger.recordQuit("k", now: at)
        }
    }

    @Test func oldDelayFieldsDecodeWithoutPostponingTheUpdate() throws {
        let json = #"{"entries":{"k":{"firstSeen":815801466.5,"lastQuit":815801467,"gaveUp":false,"failures":0,"version":"0.43.2"}}}"#
        let ledger = try JSONDecoder().decode(Policy.Ledger.self, from: Data(json.utf8))
        let entry = try #require(ledger.entries["k"])
        #expect(entry.behindSince == Date(timeIntervalSinceReferenceDate: 815801466.5))
        // Even a clock change that puts both old timestamps in the future no
        // longer makes a successful update wait for the former delay.
        #expect(Policy.decide(entry: entry, now: .distantPast) == .quitAndUpdate)
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
        ledger.recordFailure("k", now: now)
        let data = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(Policy.Ledger.self, from: data) == ledger)
    }

    @Test func currentHoldComesFromThePersistedLedger() throws {
        let json = #"{"entries":{"_Applications_Discord.app":{"version":"0.0.423","firstSeen":816545450.055032,"failures":0,"gaveUp":false,"automaticFailure":{"disposition":"pauseVersion","reason":"Not enough free space on this Mac to install this update: it has 723.7 MB free and needs 11.82 GB. Nothing was changed."}}}}"#
        let ledger = try JSONDecoder().decode(Policy.Ledger.self, from: Data(json.utf8))
        let key = "_Applications_Discord.app"
        #expect(ledger.holdReason(for: key, version: "0.0.423", now: now, freeBytes: 0) != nil)
        #expect(ledger.holdReason(for: key, version: "0.0.424", now: now, freeBytes: nil) == nil)
        #expect(ledger.holdReason(for: "other", version: "0.0.423", now: now, freeBytes: nil) == nil)
    }

    @Test func currentHoldExpiresWhenTheCooldownOrSpaceRequirementClears() {
        var ledger = Policy.Ledger()
        _ = ledger.observe("space", version: "2", now: now)
        ledger.recordFailure("space", failure: .init(disposition: .waitForSpace, reason: "Low space",
                                                     requiredFreeBytes: 200), now: now)
        #expect(ledger.holdReason(for: "space", version: "2", now: now, freeBytes: 199) == .waitingForSpace)
        #expect(ledger.holdReason(for: "space", version: "2", now: now, freeBytes: 200) == nil)
        #expect(ledger.entries["space"]?.automaticFailure?.disposition == .waitForSpace)

        _ = ledger.observe("cooldown", version: "2", now: now)
        ledger.recordQuitRefused("cooldown", now: now)
        #expect(ledger.holdReason(for: "cooldown", version: "2", now: now, freeBytes: nil) == .gaveUp)
        #expect(ledger.holdReason(for: "cooldown", version: "3", now: now, freeBytes: nil) == .retryLater)
        let deadline = now.addingTimeInterval(Policy.retryBackoff)
        #expect(ledger.holdReason(for: "cooldown", version: "3", now: deadline, freeBytes: nil) == nil)
        #expect(ledger.entries["cooldown"]?.version == "2")
    }
}
