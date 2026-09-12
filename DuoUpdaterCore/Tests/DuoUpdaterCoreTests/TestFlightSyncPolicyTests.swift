import Testing
import Foundation
@testable import DuoUpdaterCore

/// #539: when a round may start a hidden TestFlight of its own, beyond the button.
///
/// Every case names the mutation it kills, and each was run against this suite.
/// Fixture paths are invented and the helper below refuses a real one — a path that
/// exists on the machine running the tests puts the file system into the equation
/// (`UpdatePolicy.runtimeBundlePath` resolves symlinks, which is the identity
/// transform only for paths that do not exist).
@Suite("TestFlightSyncPolicy")
struct TestFlightSyncPolicyTests {

    private func beta(
        _ bundleID: String, short: String?, build: String?, wrapped: Bool = false,
        testFlight: Bool = true
    ) -> InstalledApp {
        let path = URL(fileURLWithPath: "/Applications/ZZFixture-\(bundleID).app")
        #expect(!FileManager.default.fileExists(atPath: path.path))
        return InstalledApp(
            name: bundleID, bundleID: bundleID, shortVersion: short, buildVersion: build,
            path: path, isMASApp: false, isiOSAppOnMac: wrapped,
            isTestFlightApp: testFlight, sparkleFeedURL: nil)
    }

    private func inventory(
        mac: [(bundleID: String, shortVersion: String, build: String)] = [],
        ios: [(bundleID: String, shortVersion: String, build: String)] = [],
        frontiers: [String: TestFlightInventory.Frontier] = [:],
        testers: Set<String>? = nil,
        accessible: Bool = true
    ) -> TestFlightInventory {
        TestFlightInventory(
            macRows: mac, installedIOSRows: ios, frontiers: frontiers, testers: testers,
            accessible: accessible)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - evidence

    /// The shape #539 measured three of: TestFlight installed a build in the
    /// background and its own store never learned. Mutation: drop the
    /// `.testFlightManaged` branch — the three rows that started this issue produce
    /// no evidence and nothing ever syncs.
    @Test func aCopyAheadOfTheStoreIsEvidence() {
        let app = beta("zz.ahead", short: "1.0", build: "81")
        let found = TestFlightSyncPolicy.evidence(
            in: [app],
            inventory: inventory(mac: [("zz.ahead", "1.0", "75")]),
            announcements: nil)
        #expect(found == [.init(bundleID: "zz.ahead", installedBuild: "81")])
    }

    /// A beta the store holds no rows for at all. Mutation: return nil instead of
    /// evidence when the lookup misses — a beta installed while the store was stale
    /// can never prompt the sync that would explain it.
    @Test func aBundleTheStoreHasNoRowsForIsEvidence() {
        let found = TestFlightSyncPolicy.evidence(
            in: [beta("zz.unknown", short: "2.0", build: "9")],
            inventory: inventory(mac: [("zz.other", "1.0", "1")]),
            announcements: nil)
        #expect(found == [.init(bundleID: "zz.unknown", installedBuild: "9")])
    }

    /// The announcement witness, in the one direction it is allowed to speak.
    /// Mutation: drop the `isBehind` branch — a build TestFlight has already told
    /// the user about, past everything the store holds, buys no sync.
    @Test func anAnnouncementPastTheFrontierIsEvidence() {
        let inv = inventory(
            mac: [("zz.announced", "1.0", "10")],
            frontiers: ["zz.announced": .init(adamID: 42, maxBuildID: 100)])
        let found = TestFlightSyncPolicy.evidence(
            in: [beta("zz.announced", short: "1.0", build: "10")],
            inventory: inv,
            announcements: TestFlightAnnouncements(
                announcements: [.init(appAdamID: 42, buildID: 101)]))
        #expect(found == [.init(bundleID: "zz.announced", installedBuild: "10")])
    }

    /// A store that agrees with the disk says nothing, and neither does one that is
    /// simply offering an update — that row is already correct and needs no sync.
    /// Mutation: return evidence unconditionally — every round on every Mac starts a
    /// TestFlight, which is the 288-a-day outcome this policy exists to avoid.
    @Test func aBoundedRowIsNotEvidence() {
        let inv = inventory(mac: [("zz.current", "1.0", "10"), ("zz.offered", "1.0", "12")])
        let found = TestFlightSyncPolicy.evidence(
            in: [beta("zz.current", short: "1.0", build: "10"),
                 beta("zz.offered", short: "1.0", build: "11")],
            inventory: inv, announcements: nil)
        #expect(found.isEmpty)
    }

    /// A bundle the signed-in account is not testing has placeholder rows by design,
    /// not a store that fell behind. Mutation: drop the `isTesting` gate — signing
    /// out turns every installed beta into evidence, and each round then starts a
    /// TestFlight that can only ask the user to sign in.
    @Test func aBetaTheAccountIsNotTestingIsNotEvidence() {
        let found = TestFlightSyncPolicy.evidence(
            in: [beta("zz.stopped", short: "1.0", build: "81")],
            inventory: inventory(mac: [("zz.stopped", "1.0", "75")], testers: ["zz.other"]),
            announcements: nil)
        #expect(found.isEmpty)
    }

    /// Mutation: drop the `accessible` guard — a store that was never opened holds
    /// no rows, so every beta reads as "no rows for this bundle" and a Mac without
    /// Full Disk Access syncs on every round.
    @Test func anInaccessibleStoreIsNotEvidenceAboutAnything() {
        let found = TestFlightSyncPolicy.evidence(
            in: [beta("zz.blind", short: "1.0", build: "81")],
            inventory: inventory(accessible: false),
            announcements: nil)
        #expect(found.isEmpty)
    }

    /// A wrapped iPhone/iPad bundle is answered from the iOS rows, the same split
    /// `UpdateChecker` applies (#476). Mutation: call `latest(forBundleID:)` instead
    /// of `UpdateChecker.testFlightLatest` — a current wrapped beta has no mac rows,
    /// reads as "no rows", and syncs forever.
    @Test func aWrappedBundleIsBoundedByItsIOSRows() {
        let found = TestFlightSyncPolicy.evidence(
            in: [beta("zz.wrapped", short: "1.0", build: "1300", wrapped: true)],
            inventory: inventory(ios: [("zz.wrapped", "1.0", "1300")]),
            announcements: nil)
        #expect(found.isEmpty)
    }

    // MARK: - reason

    /// Evidence does not wait for the floor. Mutation: gate it behind the floor
    /// (`guard lastTouched == nil || now - lastTouched >= floorInterval else
    /// { return nil }`) — the three rows #539 opened on wait out six hours, on a
    /// store TestFlight itself wrote a minute earlier.
    ///
    /// ⚠️ This does **not** pin which reason wins when both hold — nothing can,
    /// because nothing observes it: the caller syncs and records the same evidence
    /// either way, so the two differ only in one log line. Reordering the two
    /// branches was tried as a mutation and survived, correctly.
    @Test func evidenceSyncsEvenWhenTheStoreWasJustWritten() {
        let evidence = [TestFlightSyncPolicy.Evidence(bundleID: "zz.a", installedBuild: "81")]
        #expect(TestFlightSyncPolicy.reason(
            evidence: evidence, storeStamp: now.addingTimeInterval(-60),
            ledger: .init(lastAttemptAt: now.addingTimeInterval(-60)), now: now)
            == .staleStore(evidence))
    }

    /// The guard that keeps evidence from becoming a timer: a build that expires out
    /// of the store leaves the inequality true forever. Mutation: drop the
    /// `syncedFor` filter — that row starts a TestFlight on every single round.
    @Test func aBuildAlreadySyncedForDoesNotAskAgain() {
        let evidence = [TestFlightSyncPolicy.Evidence(bundleID: "zz.a", installedBuild: "81")]
        #expect(TestFlightSyncPolicy.reason(
            evidence: evidence, storeStamp: now.addingTimeInterval(-60),
            ledger: .init(lastAttemptAt: now.addingTimeInterval(-60), syncedFor: ["zz.a": "81"]),
            now: now)
            == nil)
    }

    /// …but a genuinely new install is a new thing to learn. Mutation: key the
    /// ledger on the bundle id alone — the second and every later background install
    /// of the same app is swallowed, which on this machine's Amp is nine of ten
    /// builds a day.
    @Test func aNewBuildForTheSameBundleAsksAgain() {
        let evidence = [TestFlightSyncPolicy.Evidence(bundleID: "zz.a", installedBuild: "82")]
        #expect(TestFlightSyncPolicy.reason(
            evidence: evidence, storeStamp: now.addingTimeInterval(-60),
            ledger: .init(lastAttemptAt: now.addingTimeInterval(-60), syncedFor: ["zz.a": "81"]),
            now: now)
            == .staleStore(evidence))
    }

    /// The user opened TestFlight themselves, well inside the floor. Mutation: read
    /// only `lastAttemptAt` — the floor ignores the store's own freshness and syncs on
    /// top of a store somebody just synced.
    ///
    /// The age is derived from `floorInterval` rather than written out: a literal here
    /// was an hour, and changing the floor to an hour turned "recent" into "exactly
    /// due" and failed this case for a reason that had nothing to do with what it
    /// tests.
    @Test func aRecentlyWrittenStoreHoldsTheFloorOff() {
        #expect(TestFlightSyncPolicy.reason(
            evidence: [], storeStamp: now.addingTimeInterval(-TestFlightSyncPolicy.floorInterval / 2),
            ledger: .init(), now: now)
            == nil)
    }

    /// We tried inside the floor and TestFlight wrote nothing. Mutation: read only
    /// `storeStamp` — a store that never moves makes every later round attempt again,
    /// turning the floor into the per-tick launcher this whole type exists to prevent.
    /// Age derived from the constant, for the reason given just above.
    @Test func aRecentAttemptThatWroteNothingHoldsTheFloorOff() {
        #expect(TestFlightSyncPolicy.reason(
            evidence: [], storeStamp: nil,
            ledger: .init(lastAttemptAt: now.addingTimeInterval(-TestFlightSyncPolicy.floorInterval / 2)),
            now: now)
            == nil)
    }

    /// Mutation: return nil when nothing is known — a Mac whose store has never been
    /// written (and which therefore needs this most) never syncs at all.
    @Test func nothingKnownAboutTheStoreIsTheFloor() {
        #expect(TestFlightSyncPolicy.reason(
            evidence: [], storeStamp: nil, ledger: .init(), now: now) == .floor)
    }

    /// Mutation: use `>` rather than `>=`, or widen the interval — a store last
    /// written six hours ago is exactly what the floor is for.
    @Test func aStaleStoreWithNoEvidenceIsTheFloor() {
        #expect(TestFlightSyncPolicy.reason(
            evidence: [], storeStamp: now.addingTimeInterval(-TestFlightSyncPolicy.floorInterval),
            ledger: .init(), now: now)
            == .floor)
    }

    /// A stamp in the future is a clock that moved, not a store that was just
    /// written. Mutation: drop the `age >= 0` clause — a backwards clock jump parks
    /// the floor for as long as the jump lasted, silently, and nothing on the Mac
    /// says why TestFlight stopped being synced.
    @Test func aStampFromTheFutureIsNotFreshness() {
        #expect(TestFlightSyncPolicy.reason(
            evidence: [], storeStamp: now.addingTimeInterval(86_400),
            ledger: .init(), now: now)
            == .floor)
    }

    // MARK: - ledger

    /// An attempt that returned before spawning anything (signed out, TestFlight not
    /// installed) must not retire the evidence — but it must not re-fire on the very
    /// next round either, or a Mac where TestFlight can never be reached pays an
    /// accounts read and two log lines every tick, forever.
    ///
    /// Two mutations, one per half. Drop the `ran` guard in `finish`: the evidence is
    /// retired, and signing back in never produces the sync that would pick the store
    /// up. Drop `lastAttemptReachedTestFlight` from `reason`'s first branch: the
    /// immediate re-fire comes back.
    @Test func anAttemptThatNeverStartedTestFlightIsParkedNotRetired() {
        var ledger = TestFlightSyncPolicy.Ledger()
        let evidence = [TestFlightSyncPolicy.Evidence(bundleID: "zz.a", installedBuild: "81")]
        ledger.finish(evidence, ran: false, at: now)
        #expect(ledger.syncedFor.isEmpty)
        #expect(ledger.lastAttemptAt == now)
        // Parked: the next round does not try again.
        #expect(TestFlightSyncPolicy.reason(
            evidence: evidence, storeStamp: nil, ledger: ledger, now: now) == nil)
        // Not retired: once the floor comes round, it is still evidence, and it is
        // reported as such rather than as a bare `.floor`.
        #expect(TestFlightSyncPolicy.reason(
            evidence: evidence, storeStamp: nil, ledger: ledger,
            now: now.addingTimeInterval(TestFlightSyncPolicy.floorInterval))
            == .staleStore(evidence))
    }

    /// The other side of that gate: an attempt that DID reach TestFlight leaves the
    /// evidence branch armed, so a background install landing a minute later is acted
    /// on at the next round rather than waiting out the floor. Mutation: leave
    /// `lastAttemptReachedTestFlight` false in `finish` regardless of `ran` — every
    /// new build waits up to an hour, which is the freshness this whole change buys.
    @Test func anAttemptThatRanLeavesTheEvidenceBranchArmed() {
        var ledger = TestFlightSyncPolicy.Ledger()
        ledger.finish([], ran: true, at: now)
        let newBuild = [TestFlightSyncPolicy.Evidence(bundleID: "zz.a", installedBuild: "82")]
        #expect(TestFlightSyncPolicy.reason(
            evidence: newBuild, storeStamp: now, ledger: ledger,
            now: now.addingTimeInterval(60))
            == .staleStore(newBuild))
    }

    /// The other side of the same line. Mutation: record nothing at all — `finish`
    /// stops being the thing that ends a repeat and the guard case above passes for
    /// the wrong reason.
    @Test func anAttemptThatRanRetiresTheBuildItRanFor() {
        var ledger = TestFlightSyncPolicy.Ledger()
        let evidence = [TestFlightSyncPolicy.Evidence(bundleID: "zz.a", installedBuild: "81")]
        ledger.finish(evidence, ran: true, at: now)
        #expect(ledger.syncedFor == ["zz.a": "81"])
        #expect(TestFlightSyncPolicy.reason(
            evidence: evidence, storeStamp: now, ledger: ledger, now: now) == nil)
    }

    /// `noChange` means TestFlight ran and wrote nothing — a real answer about the
    /// store. Mutation: fold it in with the four that never spawned — a store that is
    /// genuinely current keeps producing evidence-driven launches.
    @Test func noChangeCountsAsHavingRun() {
        #expect(TestFlightRefresh.Outcome.noChange.testFlightRan)
        #expect(!TestFlightRefresh.Outcome.notSignedIn.testFlightRan)
        #expect(!TestFlightRefresh.Outcome.launchFailed.testFlightRan)
        #expect(!TestFlightRefresh.Outcome.notInstalled.testFlightRan)
        #expect(!TestFlightRefresh.Outcome.accountTestsNothing.testFlightRan)
    }

    /// An attempt that is still running already counts against the floor. Mutation:
    /// make `begin` a no-op — the round that starts a sync does not wait for it, so
    /// the next round reads a store nothing has written yet, sees the floor as still
    /// due, and starts a second hidden TestFlight on top of the first.
    @Test func anAttemptInFlightAlreadySatisfiesTheFloor() {
        var ledger = TestFlightSyncPolicy.Ledger()
        ledger.begin(at: now)
        #expect(TestFlightSyncPolicy.reason(
            evidence: [], storeStamp: nil, ledger: ledger, now: now.addingTimeInterval(30)) == nil)
    }
}
