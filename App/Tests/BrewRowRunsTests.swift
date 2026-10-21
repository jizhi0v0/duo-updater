import Foundation
import Testing
import DuoUpdaterCore

/// What the popover's Homebrew row stands for, and what its one Cancel stops
/// (`BrewRowRuns`). What the row draws is `BrewRowSnapshot`'s
/// (`BrewRowViewTests`, in Core). Each case names the single-line mutation it
/// fails under.
struct BrewRowRunsTests {

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

    /// The rows' lines, worded as they were before Core decided them: the
    /// count names the one being worked on.
    ///
    /// Mutation: word `.starting` as "Queued" (the click-time line kept) → red.
    @Test func theLinesAreWordedAsTheRowsSayThem() {
        #expect(BrewProgressLine.queued.text == "Queued")
        #expect(BrewProgressLine.starting.text == "Starting…")
        #expect(BrewProgressLine.count(current: 2, total: 3).text == "Upgrading… (2/3)")
        #expect(BrewProgressLine.note("Downloading…").text == "Downloading…")
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
