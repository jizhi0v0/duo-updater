import Testing
import Foundation
@testable import DuoUpdaterCore

/// The announce-once ledger behind the "new updates available" banner. The one
/// property that matters is that it can still discriminate for an app whose
/// marketing string never moves — Amp shipped ten builds as "1.0" in a day, and
/// the marketing-keyed version announced the first and silently swallowed nine.
struct NotifiedUpdateVersionsTests {

    private let key = "/ZZFixture-Frozen.app"
    private let legacy = "zz.fixture.frozen"

    @Test func fixturePathsAreInvented() {
        #expect(!FileManager.default.fileExists(atPath: key))
    }

    /// The regression: same marketing version, new build, already-announced entry.
    @Test func aNewBuildUnderAFrozenMarketingVersionIsNotYetAnnounced() {
        let baseline = [key: NotifiedUpdateVersions.announceKey(
            VersionSide(marketing: "1.0", build: "2001"))]
        #expect(!NotifiedUpdateVersions.wasAnnounced(
            VersionSide(marketing: "1.0", build: "2002"), under: [key, legacy], in: baseline))
        // …and the build that WAS announced still reads as announced.
        #expect(NotifiedUpdateVersions.wasAnnounced(
            VersionSide(marketing: "1.0", build: "2001"), under: [key, legacy], in: baseline))
    }

    /// A baseline written by an older build stored the bare marketing string. It
    /// must not re-announce everything once — including under the legacy app key.
    @Test func aMarketingOnlyBaselineEntryStillCountsAsAnnounced() {
        #expect(NotifiedUpdateVersions.wasAnnounced(
            VersionSide(marketing: "1.0", build: "2001"),
            under: [key, legacy], in: [key: "1.0"]))
        #expect(NotifiedUpdateVersions.wasAnnounced(
            VersionSide(marketing: "1.0", build: "2001"),
            under: [key, legacy], in: [legacy: "1.0"]))
        // A different marketing version is a different update either way.
        #expect(!NotifiedUpdateVersions.wasAnnounced(
            VersionSide(marketing: "1.1", build: "2001"),
            under: [key, legacy], in: [key: "1.0"]))
    }

    /// Nothing recorded at all is never "announced", and a row whose offer names
    /// no version keeps the empty-string key the marketing-keyed ledger stored.
    @Test func anUnrecordedAppIsNotAnnouncedAndAVersionlessOfferKeepsItsKey() {
        #expect(!NotifiedUpdateVersions.wasAnnounced(
            VersionSide(marketing: "1.0", build: "2001"), under: [key, legacy], in: [:]))
        #expect(NotifiedUpdateVersions.announceKey(nil) == "")
        #expect(NotifiedUpdateVersions.announceKey(VersionSide()) == "")
        #expect(NotifiedUpdateVersions.wasAnnounced(nil, under: [key], in: [key: ""]))
    }

    /// A build equal to the marketing string is not repeated, so an app that
    /// stamps both fields identically keeps the key it always had.
    @Test func anIdenticalBuildIsNotAppendedToTheKey() {
        #expect(NotifiedUpdateVersions.announceKey(
            VersionSide(marketing: "1.2.3", build: "1.2.3")) == "1.2.3")
        #expect(NotifiedUpdateVersions.announceKey(
            VersionSide(marketing: "1.2.3", build: nil)) == "1.2.3")
        #expect(NotifiedUpdateVersions.announceKey(
            VersionSide(marketing: nil, build: "194")) == "194")
    }
}
