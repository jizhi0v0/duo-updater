import Testing
@testable import DuoUpdaterCore

@Suite("OncePerBatchPrompt")
struct OncePerBatchPromptTests {
    /// The answers to failures in this order (`true` for a batch run), with a
    /// `nil` for a batch starting.
    private func answers(_ runs: [Bool?]) -> [Bool] {
        var prompt = OncePerBatchPrompt()
        var shown: [Bool] = []
        for run in runs {
            guard let run else { prompt.reset(); continue }
            shown.append(prompt.shouldPresent(batchRun: run))
        }
        return shown
    }

    @Test("the batch's runs show the dialog once")
    func batchRunsShowOnce() {
        #expect(answers([true, true, true]) == [true, false, false])
    }

    /// The #1503 review finding: a row clicked by hand while a batch runs was
    /// swallowed once the batch had shown the dialog.
    @Test("a hand run during a batch still asks after the batch did")
    func handRunAfterBatchShowed() {
        #expect(answers([true, false, false]) == [true, true, true])
    }

    @Test("a hand run does not use up the batch's dialog")
    func handRunLeavesTheBatchItsDialog() {
        #expect(answers([false, true, true]) == [true, true, false])
    }

    @Test("the next batch asks again")
    func resetAllowsTheNextBatch() {
        #expect(answers([true, nil, true]) == [true, true])
    }
}
