import Foundation
import Testing
@testable import DuoUpdaterCore

/// The update line's two sides are formatted alike: a build in parentheses on one
/// side only is dropped, and when both sides carry theirs both stay.
///
/// The two shapes that showed it, on 2026-10-19:
/// - Arc's feed writes `shortVersionString` "1.169.0 (88758)" beside
///   `sparkle:version` 88758, while its bundle says "1.169.0":
///   "1.168.0 → 1.169.0 (88758)".
/// - The scanner names Xcode "27.0 (27A266a)", and the App Store answers "27.1":
///   "27.0 (27A266a) → 27.1".
@Suite struct OfferedVersionLineTests {

    private func result(
        id: String = "company.thebrowser.Browser", installedShort: String, installedBuild: String,
        offered: String, offeredBuild: String?, source: String = "Sparkle"
    ) -> UpdateResult {
        let app = InstalledApp(
            name: "ZZFixture", bundleID: id, shortVersion: installedShort,
            buildVersion: installedBuild, path: URL(fileURLWithPath: "/Applications/ZZFixture.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: true, hasSparkleUpdater: true)
        let remote = RemoteVersion(
            shortVersion: offered, version: offeredBuild,
            downloadURL: URL(string: "https://zzfixture.invalid/x.zip"), sourceName: source)
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: offered))
    }

    /// Arc: the marketing versions differ, so neither side shows a build.
    @Test func aBuildOnTheOfferedSideOnlyIsDropped() {
        let arc = result(installedShort: "1.168.0", installedBuild: "88413",
                         offered: "1.169.0 (88758)", offeredBuild: "88758")
        let sides = arc.updateLineSides(latest: "1.169.0 (88758)")
        #expect(sides.installed == "1.168.0")
        #expect(sides.offered == "1.169.0")
        #expect(arc.buildBump(latest: "1.169.0 (88758)") == nil)
    }

    /// Arc, same marketing version: the builds are what moved, so both sides
    /// show theirs, instead of "1.169.0 → 1.169.0 (88758)".
    @Test func aSameMarketingBumpShowsBothBuildsWhenTheFeedRepeatsItsBuild() throws {
        let arc = result(installedShort: "1.169.0", installedBuild: "88700",
                         offered: "1.169.0 (88758)", offeredBuild: "88758")
        let sides = arc.updateLineSides(latest: "1.169.0 (88758)")
        #expect(sides.installed == "1.169.0")
        #expect(sides.offered == "1.169.0")
        let bump = try #require(arc.buildBump(latest: "1.169.0 (88758)"))
        #expect(bump == (installed: "88700", remote: "88758"))
    }

    /// Xcode answered by the App Store: the build the scanner put on the
    /// installed side goes, since the store names none.
    @Test func aBuildOnTheInstalledSideOnlyIsDropped() {
        let xcode = result(id: "com.apple.dt.Xcode", installedShort: "27.0 (27A266a)",
                           installedBuild: "27A266a", offered: "27.1", offeredBuild: nil,
                           source: "App Store")
        let sides = xcode.updateLineSides(latest: "27.1")
        #expect(sides.installed == "27.0")
        #expect(sides.offered == "27.1")
    }

    /// Xcode answered by Xcode Releases names both betas with their builds on
    /// purpose ("27.0 beta 1" covers more than one build); both stay.
    @Test func buildsOnBothSidesStay() {
        let sides = UpdateResult.updateLineSides(
            installed: "27.0 beta 1 (27A5194q)", installedBuild: "27A5194q",
            offered: "27.0 beta 5 (27A5237l)", offeredBuild: "27A5237l")
        #expect(sides.installed == "27.0 beta 1 (27A5194q)")
        #expect(sides.offered == "27.0 beta 5 (27A5237l)")
    }

    /// Only a side's own build is taken off; anything else in parentheses is
    /// part of what the vendor calls the version.
    @Test func onlyASidesOwnBuildIsTakenOff() {
        #expect(UpdateResult.droppingTrailingBuild("2.0 (beta)", build: "200") == "2.0 (beta)")
        #expect(UpdateResult.droppingTrailingBuild("2.0 (200)", build: nil) == "2.0 (200)")
        #expect(UpdateResult.droppingTrailingBuild("2.0 (200)", build: "") == "2.0 (200)")
        #expect(UpdateResult.droppingTrailingBuild(" (200)", build: "200") == " (200)")
        #expect(UpdateResult.droppingTrailingBuild("2.0(200)", build: "200") == "2.0(200)")
        let sides = UpdateResult.updateLineSides(
            installed: "1.0", installedBuild: "10", offered: "2.0 (beta)", offeredBuild: "20")
        #expect(sides == (installed: "1.0", offered: "2.0 (beta)"))
    }

    /// The labels beside the row ("Update …", "Skip …", the confirmations) name
    /// the offered version as the line does: Arc's is "1.169.0", not the feed's
    /// "1.169.0 (88758)" the line just dropped.
    ///
    /// Mutation: `offeredDisplay` returns `remote.displayVersion` → red.
    @Test func theLabelsNameTheOfferedVersionAsTheLineDoes() {
        let arc = result(installedShort: "1.168.0", installedBuild: "88413",
                         offered: "1.169.0 (88758)", offeredBuild: "88758")
        #expect(arc.offeredDisplay == "1.169.0")
        let both = result(id: "com.apple.dt.Xcode", installedShort: "27.0 beta 1 (27A5194q)",
                          installedBuild: "27A5194q", offered: "27.0 beta 5 (27A5237l)",
                          offeredBuild: "27A5237l", source: "Xcode Releases")
        #expect(both.offeredDisplay == "27.0 beta 5 (27A5237l)")
        let none = UpdateResult(app: arc.app, remote: nil, status: .upToDate)
        #expect(none.offeredDisplay == nil)
    }
}
