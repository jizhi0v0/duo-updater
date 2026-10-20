import Foundation
import Testing
import DuoUpdaterCore

/// What the popover's Homebrew row stands for, and what its one Cancel stops
/// (`BrewRowRuns`). Each case names the single-line mutation it fails under.
struct BrewRowRunsTests {

    private let t0 = ContinuousClock.now
    private func at(_ ms: Int) -> ContinuousClock.Instant { t0 + .milliseconds(ms) }

    private static let go = BrewRowRuns.formulaJobID("go")
    private static let jq = BrewRowRuns.formulaJobID("jq")
    private static let all = BrewRowRuns.upgradeAllJobID
    private static let update = BrewRowRuns.homebrewUpdateJobID

    /// A formula's own upgrade from the workbench is the row's, alone or beside
    /// Upgrade All (2026-10-20: the row showed nothing for it). `brew update`
    /// never is.
    ///
    /// Mutations: drop the formulae → `[]` for go alone, red; include Upgrade
    /// All whether or not it runs → `[all, go]`, red.
    @Test func theRowStandsForEveryUpgradeButBrewUpdate() {
        #expect(BrewRowRuns.jobIDs(upgradingAll: false, formulae: []) == [])
        #expect(BrewRowRuns.jobIDs(upgradingAll: false, formulae: ["go"]) == [Self.go])
        #expect(BrewRowRuns.jobIDs(upgradingAll: true, formulae: ["jq", "go"]) == [Self.all, Self.go, Self.jq])
        #expect(!BrewRowRuns.jobIDs(upgradingAll: true, formulae: ["go"]).contains(Self.update))
    }

    /// One formula upgrading, live: "Cancel update". With a second one queued
    /// behind it, one Cancel stops both: "Cancel 2 updates". A queued `brew
    /// update`'s live Cancel is not counted. Upgrade All past its start greys
    /// nothing while another can still be stopped, and greys the row's Cancel
    /// once nothing can; once every one says "Cancelling…" it is gone.
    ///
    /// Mutation: `cancel` over every key in `cancels` instead of the row's →
    /// `brew update` counted, `live` 2 then 3, red.
    @Test func itsCancelIsLiveWhileAnyRunCanBeStopped() {
        var s = InstallRowSmoothing<String>()
        let one = [Self.go]
        let rows1 = s.update(stages: [:], cancels: [Self.go: .available, Self.update: .available], now: at(0))
        #expect(BrewRowRuns.cancel(one, in: rows1) == .init(state: .available, pending: false, live: 1))

        let three = [Self.all, Self.go, Self.jq]
        let cancels: [String: InstallCancelState] = [
            Self.all: .committing, Self.go: .available, Self.jq: .available, Self.update: .available,
        ]
        let rows2 = s.update(stages: [:], cancels: cancels, now: at(10))
        #expect(BrewRowRuns.cancel(three, in: rows2) == .init(state: .available, pending: false, live: 2))

        let accepted: [String: InstallCancelState] = [
            Self.all: .committing, Self.go: .cancelling, Self.jq: .cancelling, Self.update: .available,
        ]
        _ = s.update(stages: [:], cancels: accepted, now: at(20))
        let shown = s.update(stages: [:], cancels: accepted, now: at(400))
        #expect(BrewRowRuns.cancel(three, in: shown) == .init(state: .committing, pending: false, live: 0))
        #expect(BrewRowRuns.cancel([Self.go, Self.jq], in: shown) == nil)
    }

    /// A click cancels the row's runs that still can be, and nothing else: not
    /// one past its start, nor one already cancelling, nor a queued `brew
    /// update`.
    ///
    /// Mutation: drop the `.available` filter → Upgrade All and jq cancelled
    /// too, red; filter `cancels` instead of the row's ids → `brew update`
    /// cancelled, red.
    @Test func aClickCancelsWhatStillCanBe() {
        let cancels: [String: InstallCancelState] = [
            Self.all: .committing, Self.go: .available, Self.jq: .cancelling, Self.update: .available,
        ]
        #expect(BrewRowRuns.cancellable([Self.all, Self.go, Self.jq], in: cancels) == [Self.go])
        #expect(BrewRowRuns.cancellable([], in: cancels) == [])
    }
}
