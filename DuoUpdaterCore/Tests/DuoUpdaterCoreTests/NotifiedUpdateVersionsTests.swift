import Testing
import Foundation
@testable import DuoUpdaterCore

/// The announce-once ledger behind the "new updates available" banner.
///
/// Two properties matter. It must still discriminate for an app whose marketing
/// string never moves — Amp shipped ten builds as "1.0" in a day, and the
/// marketing-keyed version announced the first and silently swallowed nine. And
/// it must stay quiet when a vendor endpoint names a version it has named before,
/// whichever direction that is: measured 2026-09-16, `center.qoder.sh` answers
/// `1.29.0` or `1.30.1` per request, and a ledger holding only the last version
/// posted a banner on every single check.
///
/// Each test names the mutation it is here to catch; every one was run and
/// confirmed red before this file was committed.
struct NotifiedUpdateVersionsTests {

    private let key = "/ZZFixture-Frozen.app"
    private let legacy = "zz.fixture.frozen"

    private func side(_ marketing: String?, _ build: String? = nil) -> VersionSide {
        VersionSide(marketing: marketing, build: build)
    }

    @Test func fixturePathsAreInvented() {
        #expect(!FileManager.default.fileExists(atPath: key))
    }

    /// The regression: same marketing version, new build, already-announced entry.
    ///
    /// Mutation: `announceKey` returning `offered.text(withBuild: false)`.
    @Test func aNewBuildUnderAFrozenMarketingVersionIsNotYetAnnounced() {
        var ledger = NotifiedUpdateVersions()
        ledger.record(side("1.0", "2001"), under: key)
        #expect(!ledger.wasAnnounced(side("1.0", "2002"), under: [key, legacy]))
        // …and the build that WAS announced still reads as announced.
        #expect(ledger.wasAnnounced(side("1.0", "2001"), under: [key, legacy]))
    }

    /// A ledger written by an older build stored the bare marketing string. It
    /// must not re-announce everything once — including under the legacy app key.
    ///
    /// Mutation: dropping the `key.legacy` arm of `wasAnnounced`.
    @Test func aMarketingOnlyEntryStillCountsAsAnnounced() {
        #expect(NotifiedUpdateVersions([key: ["1.0"]])
            .wasAnnounced(side("1.0", "2001"), under: [key, legacy]))
        #expect(NotifiedUpdateVersions([legacy: ["1.0"]])
            .wasAnnounced(side("1.0", "2001"), under: [key, legacy]))
        // A different marketing version is a different update either way.
        #expect(!NotifiedUpdateVersions([key: ["1.0"]])
            .wasAnnounced(side("1.1", "2001"), under: [key, legacy]))
    }

    /// The migration's leniency has to expire, or it becomes the very defect the
    /// build-aware key was introduced to fix. A ledger holding the pre-upgrade
    /// "1.0" covers the first build offered after the upgrade — and then that pass
    /// records "1.0 (2001)" and the bare spelling is gone, so "1.0 (2002)" is news.
    ///
    /// Mutation: dropping the `marketing` removal from `record`. Amp's ten builds
    /// called "1.0" are then all swallowed and the last expectation fails.
    @Test func theMarketingOnlyLeniencyExpiresAfterOnePass() {
        var ledger = NotifiedUpdateVersions([key: ["1.0"]])
        #expect(ledger.wasAnnounced(side("1.0", "2001"), under: [key]))
        ledger.record(side("1.0", "2001"), under: key)
        #expect(ledger.entries[key] == ["1.0 (2001)"])
        #expect(!ledger.wasAnnounced(side("1.0", "2002"), under: [key]))
    }

    /// Nothing recorded at all is never "announced", and a row whose offer names
    /// no version keeps the empty-string key the marketing-keyed ledger stored.
    @Test func anUnrecordedAppIsNotAnnouncedAndAVersionlessOfferKeepsItsKey() {
        #expect(!NotifiedUpdateVersions().wasAnnounced(side("1.0", "2001"), under: [key, legacy]))
        #expect(NotifiedUpdateVersions.announceKey(nil) == "")
        #expect(NotifiedUpdateVersions.announceKey(VersionSide()) == "")
        #expect(NotifiedUpdateVersions([key: [""]]).wasAnnounced(nil, under: [key]))
    }

    /// A build equal to the marketing string is not repeated, so an app that
    /// stamps both fields identically keeps the key it always had.
    @Test func anIdenticalBuildIsNotAppendedToTheKey() {
        #expect(NotifiedUpdateVersions.announceKey(side("1.2.3", "1.2.3")) == "1.2.3")
        #expect(NotifiedUpdateVersions.announceKey(side("1.2.3", nil)) == "1.2.3")
        #expect(NotifiedUpdateVersions.announceKey(side(nil, "194")) == "194")
    }

    /// The Qoder shape: an endpoint alternating between two versions per request.
    /// Both are announced once; neither is ever announced again, in either
    /// direction, however long it flips.
    ///
    /// Mutation: `record` keeping only the newest entry (`suffix(1)`) — the
    /// pre-change behaviour. Then the second `wasAnnounced` below is false.
    @Test func anEndpointFlippingBetweenTwoVersionsAnnouncesEachOnce() {
        var ledger = NotifiedUpdateVersions()
        ledger.record(side("1.29.0"), under: key)
        ledger.record(side("1.30.1"), under: key)
        for _ in 0..<50 {
            ledger.record(side("1.29.0"), under: key)
            ledger.record(side("1.30.1"), under: key)
        }
        #expect(ledger.wasAnnounced(side("1.29.0"), under: [key]))
        #expect(ledger.wasAnnounced(side("1.30.1"), under: [key]))
        // A third version the endpoint has not served yet is still news.
        #expect(!ledger.wasAnnounced(side("1.31.0"), under: [key]))
    }

    /// Re-recording a version already held must not consume a slot, or a
    /// two-version flap would evict its own earlier announcements and start
    /// re-announcing after `capacity` flips.
    ///
    /// Mutation: dropping `list.removeAll { $0 == version }` from `record`. The
    /// duplicates then push "0.1" out and the first expectation fails.
    @Test func reRecordingAHeldVersionDoesNotConsumeCapacity() {
        var ledger = NotifiedUpdateVersions()
        ledger.record(side("0.1"), under: key)
        for _ in 0..<(NotifiedUpdateVersions.capacity * 4) {
            ledger.record(side("9.0"), under: key)
        }
        #expect(ledger.wasAnnounced(side("0.1"), under: [key]))
        #expect(ledger.entries[key]?.count == 2)
    }

    /// The deepest recurrence the 117 committed `verify/baseline.json` sweeps
    /// contain: ToDesk went `4.10.1.0 → 5.0.0.0 → 5.0.2.0 → 5.1.0.0` and then back
    /// to `4.10.1.0`, where it still sits — three other versions in between. That
    /// return must be silent, which is what sets the floor under `capacity`.
    ///
    /// Mutation: `capacity` at 3 or less. This is the test that makes the constant
    /// answerable rather than a taste.
    @Test func aVersionReturningAfterThreeOthersIsStillAnnounced() {
        var ledger = NotifiedUpdateVersions()
        for v in ["4.10.1.0", "5.0.0.0", "5.0.2.0", "5.1.0.0"] {
            ledger.record(side(v), under: key)
        }
        #expect(ledger.wasAnnounced(side("4.10.1.0"), under: [key]))
        #expect(NotifiedUpdateVersions.capacity >= 4)
    }

    /// Capacity is a bound, not a suggestion: the preference this persists into
    /// would otherwise grow for the lifetime of an app that keeps shipping.
    ///
    /// Mutation: dropping the `suffix(Self.capacity)` in `record`.
    @Test func anAppThatKeepsShippingStaysBounded() {
        var ledger = NotifiedUpdateVersions()
        for i in 0..<200 { ledger.record(side("1.\(i).0"), under: key) }
        #expect(ledger.entries[key]?.count == NotifiedUpdateVersions.capacity)
        // The oldest are gone, the newest are held.
        #expect(!ledger.wasAnnounced(side("1.0.0"), under: [key]))
        #expect(ledger.wasAnnounced(side("1.199.0"), under: [key]))
    }

    /// The persisted shape was a bare string per app before it became a list.
    /// Reading it as anything else re-announces every pending update at once on
    /// the first launch after the upgrade.
    ///
    /// Mutation: dropping the `stored as? String` branch of `init(persisted:)`.
    @Test func aLedgerPersistedInTheOldSingleStringShapeStillReads() {
        let migrated = NotifiedUpdateVersions(persisted: [key: "1.0 (2001)", legacy: "0.9"])
        #expect(migrated.wasAnnounced(side("1.0", "2001"), under: [key]))
        #expect(migrated.wasAnnounced(side("0.9"), under: [legacy]))
        #expect(!migrated.wasAnnounced(side("1.0", "2002"), under: [key]))
    }

    /// And the new shape round-trips through the plist form, capped on the way in
    /// so a hand-edited or downgraded-then-upgraded preference cannot smuggle an
    /// unbounded list back.
    ///
    /// Mutation: dropping the `suffix(Self.capacity)` in `init(persisted:)`.
    @Test func theListShapeRoundTripsAndIsCappedOnRead() {
        var ledger = NotifiedUpdateVersions()
        for i in 0..<5 { ledger.record(side("2.\(i).0"), under: key) }
        #expect(NotifiedUpdateVersions(persisted: ledger.persistable) == ledger)

        let oversized = (0..<40).map { "3.\($0).0" }
        let capped = NotifiedUpdateVersions(persisted: [key: oversized])
        #expect(capped.entries[key]?.count == NotifiedUpdateVersions.capacity)
        #expect(capped.wasAnnounced(side("3.39.0"), under: [key]))
    }

    /// The actual first launch after the upgrade: the list key does not exist yet
    /// and the whole ledger arrives through the fold. Everything already announced
    /// stays announced, and a build offered since is still news.
    ///
    /// Mutation: dropping `mergeLastAnnounced` from the startup read — the shape
    /// the correction to `init(persisted:)`'s documentation exists to prevent.
    @Test func theFirstLaunchAfterTheUpgradeAdoptsTheSingleVersionKey() {
        var ledger = NotifiedUpdateVersions(persisted: [:])
        ledger.mergeLastAnnounced([key: "1.0 (2001)", legacy: "0.9"])
        #expect(ledger.wasAnnounced(side("1.0", "2001"), under: [key]))
        #expect(ledger.wasAnnounced(side("0.9"), under: [legacy]))
        #expect(!ledger.wasAnnounced(side("1.0", "2002"), under: [key]))
    }

    /// The single-version projection an older build reads has to name the version
    /// announced LAST, or that build re-announces whatever came after it.
    ///
    /// Mutation: `lastAnnounced` mapping `\.first`. The old build then believes
    /// "1.0" was the last thing announced and posts a banner for "1.2".
    @Test func theLegacyProjectionNamesTheNewestVersion() {
        var ledger = NotifiedUpdateVersions()
        for v in ["1.0", "1.1", "1.2"] { ledger.record(side(v), under: key) }
        #expect(ledger.lastAnnounced == [key: "1.2"])
    }

    /// The ping-pong this two-key scheme exists for: a build predating the list
    /// runs in between, announces something, and writes only the single-version
    /// key. That announcement must not be repeated when the list build comes back.
    ///
    /// Mutation: dropping the `mergeLastAnnounced` call — or its whole body. "9.9"
    /// is then absent from the ledger and announced a second time.
    @Test func aVersionAnnouncedByAnOlderBuildIsNotAnnouncedAgain() {
        var ledger = NotifiedUpdateVersions()
        ledger.record(side("1.0"), under: key)
        // What the older build left behind: it overwrote the single-version key.
        var reloaded = NotifiedUpdateVersions(persisted: ledger.persistable)
        reloaded.mergeLastAnnounced([key: "9.9"])
        #expect(reloaded.wasAnnounced(side("9.9"), under: [key]))
        // …without losing what the list already held.
        #expect(reloaded.wasAnnounced(side("1.0"), under: [key]))
    }

    /// And the ordinary case — this build wrote both keys — must be a no-op, not a
    /// second copy that eats a slot and reorders the list.
    ///
    /// Mutation: dropping the `list.contains(version)` guard in
    /// `mergeLastAnnounced`.
    @Test func mergingThisBuildsOwnProjectionChangesNothing() {
        var ledger = NotifiedUpdateVersions()
        for v in ["1.0", "1.1", "1.2"] { ledger.record(side(v), under: key) }
        var reloaded = NotifiedUpdateVersions(persisted: ledger.persistable)
        reloaded.mergeLastAnnounced(ledger.lastAnnounced)
        #expect(reloaded == ledger)
    }

    /// A non-string value under the legacy key (a hand-edited preference, or a
    /// future shape) is skipped rather than crashing or poisoning the list.
    @Test func mergingIgnoresValuesThatAreNotStrings() {
        var ledger = NotifiedUpdateVersions()
        ledger.record(side("1.0"), under: key)
        ledger.mergeLastAnnounced([key: 42, legacy: ["not", "a", "version"]])
        #expect(ledger.entries[key] == ["1.0"])
        #expect(ledger.entries[legacy] == nil)
    }

    /// Apps that left the scan are dropped; apps still in it keep every version
    /// they were announced for.
    ///
    /// Mutation: `prune` inverting its predicate, or filtering on the wrong side.
    @Test func pruningForgetsOnlyAppsThatLeftTheScan() {
        var ledger = NotifiedUpdateVersions()
        ledger.record(side("1.0"), under: key)
        ledger.record(side("1.1"), under: key)
        ledger.record(side("7.0"), under: legacy)
        ledger.prune(liveKeys: [key])
        #expect(ledger.wasAnnounced(side("1.0"), under: [key]))
        #expect(ledger.wasAnnounced(side("1.1"), under: [key]))
        #expect(!ledger.wasAnnounced(side("7.0"), under: [legacy]))
    }
}
