import Testing
@testable import DuoUpdaterCore

struct StagingRecheckTests {
    @Test func ordinarySweepsKeepDeadlineAndBudget() throws {
        var recheck = StagingRecheck()
        let now = ContinuousClock().now
        let initial = recheck.begin(retry: false, at: now)
        recheck.complete(initial, unsettled: ["App"], at: now)
        let firstDeadline = try #require(recheck.deadline)
        #expect(firstDeadline == now.advanced(by: .seconds(1)))

        for _ in 0..<10 {
            let time = now.advanced(by: .milliseconds(500))
            let ordinary = recheck.begin(retry: false, at: time)
            recheck.complete(ordinary, unsettled: ["App"], at: time)
            #expect(recheck.deadline == firstDeadline)
        }

        var deadline = firstDeadline
        for delay in [Duration.seconds(1), .seconds(2), .seconds(2), .seconds(4), .seconds(4)] {
            let retry = recheck.begin(retry: true, at: deadline)
            recheck.complete(retry, unsettled: ["App"], at: deadline)
            let next = try #require(recheck.deadline)
            #expect(next == deadline.advanced(by: delay))
            deadline = next
        }
        let last = recheck.begin(retry: true, at: deadline)
        recheck.complete(last, unsettled: ["App"], at: deadline)
        #expect(recheck.deadline == nil)

        let exhausted = recheck.begin(retry: false, at: deadline)
        recheck.complete(exhausted, unsettled: ["App"], at: deadline)
        #expect(recheck.deadline == nil)
        let settled = recheck.begin(retry: false, at: deadline)
        recheck.complete(settled, unsettled: [], at: deadline)
        let newEpisode = recheck.begin(retry: false, at: deadline)
        recheck.complete(newEpisode, unsettled: ["App"], at: deadline)
        #expect(recheck.deadline == deadline.advanced(by: .seconds(1)))
    }

    @Test func aStaleSweepCannotReplaceTheNewerObservation() throws {
        var recheck = StagingRecheck()
        let now = ContinuousClock().now
        let initial = recheck.begin(retry: false, at: now)
        recheck.complete(initial, unsettled: ["App"], at: now)
        let deadline = try #require(recheck.deadline)

        let stale = recheck.begin(retry: true, at: deadline)
        let newer = recheck.begin(retry: false, at: deadline)
        recheck.complete(newer, unsettled: [], at: deadline)
        #expect(recheck.isCurrent(newer))
        #expect(!recheck.isCurrent(stale))
        recheck.complete(stale, unsettled: ["App"], at: deadline)
        #expect(recheck.deadline == nil)
    }

    @Test func anUnpublishedRetryDoesNotSpendTheDeadline() throws {
        var recheck = StagingRecheck()
        let now = ContinuousClock().now
        let initial = recheck.begin(retry: false, at: now)
        recheck.complete(initial, unsettled: ["App"], at: now)
        let deadline = try #require(recheck.deadline)

        // A cancelled sweep returns without publishing.
        _ = recheck.begin(retry: true, at: deadline)
        #expect(recheck.deadline == deadline)
        let completed = recheck.begin(retry: true, at: deadline)
        recheck.complete(completed, unsettled: ["App"], at: deadline)
        #expect(recheck.deadline == deadline.advanced(by: .seconds(1)))
    }

    @Test func probingOneRowEarlyDoesNotSpendAnotherRowsRetry() throws {
        var recheck = StagingRecheck()
        let now = ContinuousClock().now
        let initial = recheck.begin(retry: false, at: now)
        recheck.complete(initial, unsettled: ["A"], at: now)
        let firstDeadline = try #require(recheck.deadline)

        let next = now.advanced(by: .milliseconds(500))
        let withSecond = recheck.begin(retry: false, at: next)
        recheck.complete(withSecond, unsettled: ["A", "B"], at: next)
        #expect(recheck.deadline == firstDeadline)

        let retry = recheck.begin(retry: true, at: firstDeadline)
        recheck.complete(retry, unsettled: ["A", "B"], at: firstDeadline)
        #expect(recheck.deadline == next.advanced(by: .seconds(1)))
    }
}
