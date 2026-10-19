import Testing
@testable import DuoUpdaterCore

/// What a row's Cancel says, from the registry's answers and its job's phase.
@Suite struct InstallCancelStateTests {

    /// Accepted → "Cancelling…"; refused past the commit → "already
    /// finishing", no error; a job that ended → nothing to say.
    @Test func aClickIsAnsweredAsTheRegistryAnswered() {
        #expect(InstallCancelState.after(.cancelled) == .cancelling)
        #expect(InstallCancelState.after(.tooLate(committing: "swap")) == .tooLate)
        #expect(InstallCancelState.after(.notFound) == nil)
    }

    /// Not found while the row is still claimed is a batch target whose task
    /// has not registered its job yet: the click must not be lost.
    /// Mutation: answer nil for `.notFound` whatever `claimed` says → red.
    @Test func aClickBeforeTheJobRegisteredWaitsForIt() {
        #expect(InstallCancelState.after(.notFound, claimed: true) == .cancelling)
    }

    /// A commit greys a live Cancel and one that did not land brings it back;
    /// an accepted click keeps its answer.
    /// Mutation: drop the `(.committing, .preparing)` case → red.
    @Test func theCancelFollowsTheJob() {
        #expect(InstallCancelState.available.following(.committing) == .committing)
        #expect(InstallCancelState.committing.following(.preparing) == .available)
        #expect(InstallCancelState.cancelling.following(.committing) == .cancelling)
        #expect(InstallCancelState.cancelling.following(.preparing) == .cancelling)
        #expect(InstallCancelState.tooLate.following(.committing) == .tooLate)
        #expect(InstallCancelState.available.following(nil) == .available)
    }

    /// A click refused while a commit ran is not kept by the registry
    /// (`InstallJobs.cancel` answers `.tooLate` and changes nothing), so when
    /// that commit did not land — a `mas install` attempt that exited non-zero,
    /// with a retry still to come — the Cancel is live again, not greyed with
    /// "already finishing" over an install that is preparing.
    /// Mutation: drop `(.tooLate, .preparing)` → red.
    @Test func aRefusedClickIsLiveAgainWhenTheCommitDidNotLand() {
        #expect(InstallCancelState.tooLate.following(.preparing) == .available)
        #expect(InstallCancelState.available.following(nil) == .available)
    }
}
