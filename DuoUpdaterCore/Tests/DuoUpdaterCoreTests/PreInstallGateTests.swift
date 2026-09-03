import Testing
@testable import DuoUpdaterCore

/// The re-check that runs when you click Update, and what each of its outcomes
/// means. The bug this pins: every non-`.updateAvailable` outcome used to be
/// reported as "already current on disk".
@Suite("PreInstallGate")
struct PreInstallGateTests {

    @Test("a confirmed newer version installs")
    func newerVersionProceeds() {
        #expect(PreInstallGate.decision(for: .updateAvailable(latest: "2.0")) == .proceed)
    }

    @Test("a current bundle is not a failure")
    func upToDateIsItsOwnAnswer() {
        #expect(PreInstallGate.decision(for: .upToDate) == .alreadyCurrent)
    }

    /// The conflation that motivated this. A source that was tried and failed says
    /// nothing about the disk, so it must not be reported as if it did — and it is
    /// retryable, which "already current" is not.
    @Test("a failed source is not 'already current'")
    func errorIsNotAlreadyCurrent() {
        let decision = PreInstallGate.decision(for: .error("The request timed out."))
        #expect(decision != .alreadyCurrent)
        #expect(decision == .cannotConfirm("The request timed out."))
    }

    /// The source's own message is carried through rather than replaced, so the
    /// reason survives to whoever reads it.
    @Test("the source's message is preserved", arguments: [
        "The request timed out.",
        "API rate limit exceeded for 1.2.3.4.",
        "appcast: 404",
    ])
    func messageSurvives(_ message: String) {
        #expect(PreInstallGate.decision(for: .error(message)) == .cannotConfirm(message))
    }

    /// "Nothing covers this app" and "a source failed" are both `cannotConfirm`,
    /// but only one has something to say about why — and neither is `alreadyCurrent`.
    @Test("no covering source is uncertainty without a message")
    func unknownCarriesNoMessage() {
        #expect(PreInstallGate.decision(for: .unknown) == .cannotConfirm(nil))
    }

    /// Managed apps are a third ending: nothing to install, but nothing wrong and
    /// nothing to retry.
    @Test("managed apps are neither current nor a failure", arguments: [
        UpdateStatus.appStoreManaged, .toolboxManaged, .testFlightManaged,
    ])
    func managedIsItsOwnAnswer(_ status: UpdateStatus) {
        #expect(PreInstallGate.decision(for: status) == .managedElsewhere)
    }

    /// Exactly one outcome may install. Everything else must not, whatever else it
    /// means — this is the safety half of the classification.
    @Test("only a confirmed update installs", arguments: [
        UpdateStatus.upToDate, .unknown, .appStoreManaged, .toolboxManaged,
        .testFlightManaged, .error("boom"),
    ])
    func nothingElseInstalls(_ status: UpdateStatus) {
        #expect(PreInstallGate.decision(for: status) != .proceed)
    }
}
