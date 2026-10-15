import Testing
@testable import DuoUpdaterCore

/// Which CLI-tab changes wait for which (`CLIConcurrency`, #1312).
@Suite struct CLIConcurrencyTests {

    static let brewRuns: [CLIOperation] = [.homebrewUpdate, .upgradeAll, .upgradeFormula]

    /// brew takes one global lock: any brew run blocks every other.
    @Test func brewRunsExcludeEachOther() {
        for running in Self.brewRuns {
            for operation in Self.brewRuns {
                #expect(CLIConcurrency.start(operation, running: [running]) == .blocked(by: running))
            }
        }
    }

    /// A tool's update and a brew run never overlap, either way round.
    ///
    /// Mutation: let `.tool` through against brew → both expectations fail.
    @Test func brewAndToolsExcludeEachOther() {
        for brew in Self.brewRuns {
            #expect(CLIConcurrency.start(.tool, running: [brew]) == .blocked(by: brew))
            #expect(CLIConcurrency.start(brew, running: [.tool]) == .blocked(by: .tool))
        }
    }

    /// Tool against tool is each tool's own rule, not this one's.
    @Test func toolsAreLeftToTheirOwnRules() {
        #expect(CLIConcurrency.start(.tool, running: [.tool, .tool]) == .now)
    }

    @Test func nothingRunningStartsNow() {
        for operation in Self.brewRuns + [.tool] {
            #expect(CLIConcurrency.start(operation, running: []) == .now)
        }
    }
}
