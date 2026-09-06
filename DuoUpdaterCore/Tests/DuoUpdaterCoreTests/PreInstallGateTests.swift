import Testing
@testable import DuoUpdaterCore

/// The re-check that runs when you click Update, and what each of its outcomes
/// means. The bug this pins: every non-`.updateAvailable` outcome used to be
/// reported as "already current on disk".
@Suite("PreInstallGate")
struct PreInstallGateTests {

    /// The two versions the gate compares, for the cases that don't exercise the
    /// comparison. Empty is incomparable, so it can never read as regressed —
    /// which is what every pre-existing case here assumes.
    private static let nothing = VersionSide()

    @Test("a confirmed newer version installs")
    func newerVersionProceeds() {
        #expect(PreInstallGate.decision(
            for: .updateAvailable(latest: "2.0"),
            offered: Self.nothing, confirmed: Self.nothing) == .proceed)
    }

    @Test("a current bundle is not a failure")
    func upToDateIsItsOwnAnswer() {
        #expect(PreInstallGate.decision(
            for: .upToDate, offered: Self.nothing, confirmed: Self.nothing) == .alreadyCurrent)
    }

    /// The conflation that motivated this. A source that was tried and failed says
    /// nothing about the disk, so it must not be reported as if it did — and it is
    /// retryable, which "already current" is not.
    @Test("a failed source is not 'already current'")
    func errorIsNotAlreadyCurrent() {
        let decision = PreInstallGate.decision(
            for: .error("The request timed out."),
            offered: Self.nothing, confirmed: Self.nothing)
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
        #expect(PreInstallGate.decision(
            for: .error(message),
            offered: Self.nothing, confirmed: Self.nothing) == .cannotConfirm(message))
    }

    /// "Nothing covers this app" and "a source failed" are both `cannotConfirm`,
    /// but only one has something to say about why — and neither is `alreadyCurrent`.
    @Test("no covering source is uncertainty without a message")
    func unknownCarriesNoMessage() {
        #expect(PreInstallGate.decision(
            for: .unknown, offered: Self.nothing, confirmed: Self.nothing) == .cannotConfirm(nil))
    }

    /// Managed apps are a third ending: nothing to install, but nothing wrong and
    /// nothing to retry.
    @Test("managed apps are neither current nor a failure", arguments: [
        UpdateStatus.appStoreManaged, .toolboxManaged, .testFlightManaged,
    ])
    func managedIsItsOwnAnswer(_ status: UpdateStatus) {
        #expect(PreInstallGate.decision(
            for: status, offered: Self.nothing, confirmed: Self.nothing) == .managedElsewhere)
    }

    /// Exactly one outcome may install. Everything else must not, whatever else it
    /// means — this is the safety half of the classification.
    @Test("only a confirmed update installs", arguments: [
        UpdateStatus.upToDate, .unknown, .appStoreManaged, .toolboxManaged,
        .testFlightManaged, .error("boom"),
    ])
    func nothingElseInstalls(_ status: UpdateStatus) {
        #expect(PreInstallGate.decision(
            for: status, offered: Self.nothing, confirmed: Self.nothing) != .proceed)
    }

    // MARK: - A re-check that walks backwards

    /// Nowdex, 2026-09-06: the row offered 1.0.9, the click's re-check answered
    /// 1.0.8 and called the app current, and the row filtered out of the list as
    /// if the update had been installed. The disk was still 1.0.8 the whole time.
    ///
    /// Mutation: return `.alreadyCurrent` unconditionally for `.upToDate` (i.e.
    /// delete the comparison) — this case goes red, and so does
    /// `anAgreeingAnswerIsStillCurrent` below.
    @Test("an answer older than the offer is not 'already current'")
    func aBackwardsAnswerIsRefused() {
        let decision = PreInstallGate.decision(
            for: .upToDate,
            offered: VersionSide(marketing: "1.0.9"),
            confirmed: VersionSide(marketing: "1.0.8"))
        #expect(decision == .answerRegressed)
        #expect(decision != .alreadyCurrent)
    }

    /// The other half, and the reason this can't just be "refuse `.upToDate` after
    /// a click": installing by hand between the scan and the click is the case the
    /// branch was written for, and it still has to read as `alreadyCurrent`.
    ///
    /// Mutation: return `.answerRegressed` unconditionally for `.upToDate` — this
    /// case goes red while `aBackwardsAnswerIsRefused` stays green, so the pair
    /// pins the comparison rather than the branch.
    @Test("a re-check that agrees with the offer is still 'already current'", arguments: [
        // Same version: the app was updated by hand or by its own updater.
        ("1.0.9", "1.0.9"),
        // The store moved on WHILE the click was in flight. Newer than the offer,
        // and the bundle is current against it — nothing regressed.
        ("1.0.9", "1.1.0"),
    ])
    func anAgreeingAnswerIsStillCurrent(_ pair: (offered: String, confirmed: String)) {
        #expect(PreInstallGate.decision(
            for: .upToDate,
            offered: VersionSide(marketing: pair.offered),
            confirmed: VersionSide(marketing: pair.confirmed)) == .alreadyCurrent)
    }

    /// The comparison is a `VersionSide` pair, not a marketing string. Amp ships
    /// ten builds a day all called "1.0"; comparing the display strings would make
    /// every one of its re-checks read as "same version, not regressed", which is
    /// the exact failure mode `VersionComparator` exists to prevent.
    ///
    /// Mutation: compare `offered.marketing` against `confirmed.marketing` — this
    /// case goes red (both sides are "1.0"), the two above stay green.
    @Test("a build-only regression is caught on a frozen marketing string")
    func frozenMarketingIsDecidedOnTheBuild() {
        #expect(PreInstallGate.decision(
            for: .upToDate,
            offered: VersionSide(marketing: "1.0", build: "51"),
            confirmed: VersionSide(marketing: "1.0", build: "50")) == .answerRegressed)
    }

    /// Fail closed, and keep the old answer when there is nothing to compare. A
    /// caller with no offer in hand (a batch row whose source reported no version,
    /// a hand-built result) must not have its click turned into an error.
    ///
    /// Mutation: treat an incomparable pair as regressed — this case goes red.
    @Test("an incomparable pair is not a regression", arguments: [
        (VersionSide(), VersionSide(marketing: "1.0.8")),
        (VersionSide(marketing: "1.0.9"), VersionSide()),
        (VersionSide(), VersionSide()),
        // Never across namespaces: a build against a marketing string is not an
        // ordering, so it cannot be a regression either.
        (VersionSide(build: "45830"), VersionSide(marketing: "1.96.0")),
    ])
    func anIncomparablePairIsNotRegressed(_ pair: (offered: VersionSide, confirmed: VersionSide)) {
        #expect(PreInstallGate.decision(
            for: .upToDate, offered: pair.offered, confirmed: pair.confirmed) == .alreadyCurrent)
    }

    /// The comparison belongs to `.upToDate` alone. A source that failed, or one
    /// that reports the app managed elsewhere, keeps its own ending even when the
    /// versions in hand happen to look backwards — those endings are not claims
    /// about the disk, so there is nothing for this to correct.
    ///
    /// Mutation: run the comparison before the `switch` and return
    /// `.answerRegressed` for any status — this case goes red.
    @Test("only 'up to date' is second-guessed", arguments: [
        (UpdateStatus.error("boom"), PreInstallDecision.cannotConfirm("boom")),
        (.unknown, .cannotConfirm(nil)),
        (.appStoreManaged, .managedElsewhere),
        (.updateAvailable(latest: "1.0.8"), .proceed),
    ])
    func otherEndingsAreUntouched(_ pair: (status: UpdateStatus, expected: PreInstallDecision)) {
        #expect(PreInstallGate.decision(
            for: pair.status,
            offered: VersionSide(marketing: "1.0.9"),
            confirmed: VersionSide(marketing: "1.0.8")) == pair.expected)
    }

    /// And it installs nothing, like every other non-`proceed` ending.
    @Test("a regressed answer does not install")
    func aRegressedAnswerDoesNotInstall() {
        #expect(PreInstallGate.decision(
            for: .upToDate,
            offered: VersionSide(marketing: "1.0.9"),
            confirmed: VersionSide(marketing: "1.0.8")) != .proceed)
    }
}
