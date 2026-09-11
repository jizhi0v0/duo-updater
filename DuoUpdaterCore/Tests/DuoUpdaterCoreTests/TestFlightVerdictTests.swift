import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite("UpdateChecker.testFlightVerdict")
struct TestFlightVerdictTests {
    /// Invented path: the verdict reads versions only.
    private func beta(_ short: String?, _ build: String?) -> InstalledApp {
        InstalledApp(
            name: "Beta", bundleID: "zz.fixture.beta", shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Beta.app"),
            isMASApp: false, isTestFlightApp: true, sparkleFeedURL: nil)
    }

    /// A newer build on offer is an update, labelled with the marketing version
    /// even though it did not move. Mutation: swap the sides of the second compare
    /// — no update is ever offered.
    @Test func aNewerBuildIsAnUpdate() {
        #expect(UpdateChecker.testFlightVerdict(
            installed: beta("1.2", "344"), latestShortVersion: "1.2", latestBuild: "345")
            == .updateAvailable(latest: "1.2"))
    }

    /// Mutation: answer `.updateAvailable` for the last line instead of
    /// `.upToDate` — a copy at the offered build keeps being offered it.
    @Test func theBuildOnOfferIsCurrent() {
        #expect(UpdateChecker.testFlightVerdict(
            installed: beta("1.2", "345"), latestShortVersion: "1.2", latestBuild: "345")
            == .upToDate)
    }

    /// An installed build newer than the store's latest cannot be bounded by it
    /// (#478). Mutation: drop the first compare — this reads as up to date.
    @Test func aCopyAheadOfTheStoreCannotBeBounded() {
        #expect(UpdateChecker.testFlightVerdict(
            installed: beta("1.2", "346"), latestShortVersion: "1.2", latestBuild: "345")
            == .testFlightManaged)
    }

    /// Mutation: label with the marketing string unconditionally — the row names
    /// an empty version.
    @Test func aBlankMarketingVersionLabelsWithTheBuild() {
        #expect(UpdateChecker.testFlightVerdict(
            installed: beta(nil, "344"), latestShortVersion: "", latestBuild: "345")
            == .updateAvailable(latest: "345"))
    }

    /// A major version that restarts build numbering is still an update.
    /// Mutation: compare the builds alone — 500 beside 1 reads the copy as ahead
    /// of the store, and the update is swallowed as unbounded.
    @Test func aRestartedBuildNumberUnderANewVersionIsStillAnUpdate() {
        #expect(UpdateChecker.testFlightVerdict(
            installed: beta("1.0", "500"), latestShortVersion: "2.0", latestBuild: "1")
            == .updateAvailable(latest: "2.0"))
    }
}
