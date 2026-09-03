import Testing
@testable import DuoUpdaterCore

/// Pins the one guard `AppListModel.failedCheckResults` leans on to decide
/// whether a chronically-failing row still drives the aggregate surfaces (the
/// failed-check banner, the header's "N not checked" line, the bulk-retry
/// target list). See `CheckFailureRules` and issue #264 for why this predicate
/// exists and, just as importantly, why `RowActionState` — the per-row ladder
/// both windows draw from — never reads it. `RowActionStateTests
/// .checkFailureIsExplained` is the other half of that pin: it fixes
/// `RowAction.state(for:)` for an `.error` status as a function of the message
/// and the rate-limit flag ONLY, with no parameter for a streak to arrive
/// through in the first place.
@Suite("CheckFailureRules")
struct CheckFailureRulesTests {

    /// The boundary is the whole content of this guard: one round short of the
    /// threshold is not chronic yet, exactly at it is. Delete the `>=` in favor
    /// of `>` and this goes red at the threshold; delete it in favor of `<` (or
    /// hardcode `true`/`false`) and one side or the other goes red.
    @Test("chronic starts exactly at the threshold, not one round early or late")
    func boundary() {
        #expect(CheckFailureRules.isChronic(consecutiveFailures: 0) == false)
        #expect(CheckFailureRules.isChronic(
            consecutiveFailures: CheckFailureRules.chronicThreshold - 1) == false)
        #expect(CheckFailureRules.isChronic(
            consecutiveFailures: CheckFailureRules.chronicThreshold) == true)
        #expect(CheckFailureRules.isChronic(
            consecutiveFailures: CheckFailureRules.chronicThreshold + 10) == true)
    }
}
