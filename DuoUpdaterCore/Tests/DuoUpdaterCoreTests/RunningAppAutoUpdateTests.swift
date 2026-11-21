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

    @Test func legacyDiskSpacePauseAdmitsTheSameOfferForAFreshMeasurement() throws {
        let json = #"""
            {"entries":{"_Applications_Discord.app":{"version":"0.0.423","firstSeen":816545450.055032,
            "failures":0,"gaveUp":false,"automaticFailure":{"disposition":"pauseVersion",
            "reason":"Not enough free space on this Mac to install this update: it has 4.05 GB free and needs 13.52 GB. Nothing was changed."}}}}
            """#
        var ledger = try JSONDecoder().decode(Policy.Ledger.self, from: Data(json.utf8))
        let key = "_Applications_Discord.app"
        let version = "0.0.423"
        let floor = BackupStore.freeSpaceFloorBytes
        for freeBytes: Int64? in [nil, floor - 1] {
            #expect(ledger.holdReason(for: key, version: version, now: now, freeBytes: freeBytes) == .waitingForSpace)
            let entry = ledger.observe(key, version: version, now: now, freeBytes: freeBytes)
            #expect(Policy.decide(entry: entry, now: now, freeBytes: freeBytes) == .wait(.waitingForSpace))
        }
        #expect(ledger.holdReason(for: key, version: version, now: now, freeBytes: floor) == nil)
        #expect(ledger.entries[key]?.automaticFailure?.disposition == .waitForSpace)
        let admitted = ledger.observe(key, version: version, now: now, freeBytes: floor)
        #expect(admitted.automaticFailure == nil)
        #expect(Policy.decide(entry: admitted, now: now, freeBytes: floor) == .quitAndUpdate)

        // A fresh typed refusal supplies the installer's actual requirement.
        let attempt = AutomaticUpdateFailurePolicy.Attempt()
        attempt.record(DiskSpaceGuard.InsufficientSpace(needed: floor + 123, free: floor))
        ledger.recordFailure(key, failure: try #require(attempt.failure(or: "missing")), now: now)
        ledger = try JSONDecoder().decode(Policy.Ledger.self, from: JSONEncoder().encode(ledger))
        let waiting = ledger.observe(key, version: version, now: now, freeBytes: floor + 122)
        #expect(waiting.automaticFailure?.requiredFreeBytes == floor + 123)
        #expect(Policy.decide(entry: waiting, now: now, freeBytes: floor + 122) == .wait(.waitingForSpace))
    }

    @Test func migratingLegacySpacePausesPreservesOtherPausesAndQuitHistory() throws {
        struct LegacyLedger: Encodable { let entries: [String: Policy.Entry] }
        let reason = DiskSpaceGuard.InsufficientSpace(needed: 12_000_000_000, free: 0).localizedDescription
        let pause = AutomaticUpdateFailurePolicy.Failure(disposition: .pauseVersion, reason: reason)
        let postQuit = Policy.Entry(version: "2.0", behindSince: now, lastQuit: now, automaticFailure: pause)
        let priorQuit = now.addingTimeInterval(-60)
        let earlier = Policy.Entry(version: "2.0", behindSince: now, failures: 1, lastQuit: priorQuit,
                                   automaticFailure: pause)
        let unrelated = Policy.Entry(version: "2.0", behindSince: now, automaticFailure:
            .init(disposition: .pauseVersion, reason: "Update failed. \(reason)"))
        let cooldown = Policy.Entry(version: "2.0", behindSince: now, automaticFailure:
            .init(disposition: .pauseVersion, reason: reason, retryNotBefore: now.addingTimeInterval(60)))

        let old = LegacyLedger(entries: ["postQuit": postQuit, "earlier": earlier,
                                         "unrelated": unrelated, "cooldown": cooldown])
        let migrated = try JSONDecoder().decode(Policy.Ledger.self, from: JSONEncoder().encode(old))
        #expect(migrated.entries["postQuit"] == postQuit)
        #expect(migrated.entries["unrelated"] == unrelated)
        #expect(migrated.entries["cooldown"] == cooldown)
        var earlierEntry = try #require(migrated.entries["earlier"])
        #expect(earlierEntry.automaticFailure?.disposition == .waitForSpace)
        earlierEntry.automaticFailure = pause
        #expect(earlierEntry == earlier)

        // A currently recorded pause can have the same text but carry no
        // evidence that it is a recoverable pre-install refusal.
        let current = Policy.Ledger(entries: ["earlier": earlier])
        #expect(try JSONDecoder().decode(Policy.Ledger.self, from: JSONEncoder().encode(current)) == current)
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
