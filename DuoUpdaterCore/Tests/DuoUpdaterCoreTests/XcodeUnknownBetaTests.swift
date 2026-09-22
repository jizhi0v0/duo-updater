import Testing
import Foundation
@testable import DuoUpdaterCore

/// An installed Xcode beta whose build the index does not list yet — the window
/// after Apple ships a seed and before xcodereleases.com catches up. The bundle's
/// own `BetaVersion.plist` ranks it; these pin that it is never offered a
/// downgrade, never read as "up to date" by accident, and that the engine can
/// order the pair (the installed build is placed in the lineage).
///
/// Builds that the index does not list are invented (`27A9…z`); host macOS is
/// passed in; no test reads a real bundle outside its own scratch directory.
@Suite struct XcodeUnknownBetaTests {

    static let host = "26.6.0"

    /// The live `_versionOrder`s of 2026-09-22 for these entries.
    static let feed = Data("""
    [
      {"name":"Xcode","_versionOrder":27000000901,"requires":"26.6",
       "version":{"number":"27.0","build":"27A266a","release":{"rc":1}}},
      {"name":"Xcode","_versionOrder":27000000006,"requires":"26.4",
       "version":{"number":"27.0","build":"27A5252f","release":{"beta":6}}},
      {"name":"Xcode","_versionOrder":27000000005,"requires":"26.4",
       "version":{"number":"27.0","build":"27A5237l","release":{"beta":5}}},
      {"name":"Xcode","_versionOrder":26006000999,"requires":"26.2",
       "version":{"number":"26.6","build":"17F113","release":{"release":true}}}
    ]
    """.utf8)

    static func releases(droppingRC: Bool = false) -> [XcodeReleasesSource.Release] {
        XcodeReleasesSource.parse(feed).filter { !droppingRC || $0.stability != .releaseCandidate }
    }

    static func remote(
        build: String, beta: XcodeReleasesSource.InstalledBeta?,
        in releases: [XcodeReleasesSource.Release] = releases(), osVersion: String = host
    ) -> RemoteVersion? {
        XcodeReleasesSource.remote(
            forBuild: build, in: releases, osVersion: osVersion, host: .arm64,
            followsBetaLine: false, installedBeta: beta)
    }

    static func app(build: String) -> InstalledApp {
        InstalledApp(
            name: "Xcode", bundleID: XcodeReleasesSource.bundleID, shortVersion: "27.0",
            buildVersion: build, path: URL(fileURLWithPath: "/ZZFixture/Xcode-beta.app"),
            isMASApp: false, sparkleFeedURL: nil)
    }

    // MARK: - Rank

    @Test func theRankReproducesTheIndexOrder() {
        #expect(XcodeReleasesSource.rank(ofBetaSeed: 5, version: "27.0") == 27_000_000_005)
        #expect(XcodeReleasesSource.rank(ofBetaSeed: 1, version: "27.1") == 27_001_000_001)
        #expect(XcodeReleasesSource.rank(ofBetaSeed: 3, version: "26.4.1") == 26_004_001_003)
        #expect(XcodeReleasesSource.rank(ofBetaSeed: 2, version: "27") == 27_000_000_002)
        // Every beta in the fixture, against the index's own number.
        for release in Self.releases() where release.stability == .beta {
            let seed = Int(release.displayVersion.split(separator: " ")[2])!
            #expect(XcodeReleasesSource.rank(ofBetaSeed: seed, version: release.number) == release.order)
        }
    }

    @Test(arguments: [("27.0", 0), ("27.0", 900), ("27.0.1.2", 1), ("27.x", 1), ("", 1), ("27.1000", 1), ("27..0", 1)])
    func anUnrankableBetaIsNotRanked(_ version: String, _ seed: Int) {
        #expect(XcodeReleasesSource.rank(ofBetaSeed: seed, version: version) == nil)
    }

    // MARK: - BetaVersion.plist

    static func plist(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>\(body)</dict></plist>
        """.utf8)
    }

    @Test func theSeedIsReadAsTheBundleWritesIt() {
        // As measured in the 27.0 beta 5 bundle: a string.
        #expect(XcodeReleasesSource.betaSeed(fromBetaVersionPlist:
            Self.plist("<key>seedNumber</key><string>5</string>")) == 5)
        #expect(XcodeReleasesSource.betaSeed(fromBetaVersionPlist:
            Self.plist("<key>seedNumber</key><integer>7</integer>")) == 7)
        #expect(XcodeReleasesSource.betaSeed(fromBetaVersionPlist: Self.plist("")) == nil)
        #expect(XcodeReleasesSource.betaSeed(fromBetaVersionPlist:
            Self.plist("<key>seedNumber</key><string>0</string>")) == nil)
        #expect(XcodeReleasesSource.betaSeed(fromBetaVersionPlist:
            Self.plist("<key>seedNumber</key><string>901</string>")) == nil)
        #expect(XcodeReleasesSource.betaSeed(fromBetaVersionPlist: Data("zz".utf8)) == nil)
    }

    @Test func theFileIsReadFromTheBundle() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-xcode-beta-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundle = dir.appendingPathComponent("Xcode-beta.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        // No file: an RC or GA bundle.
        #expect(XcodeReleasesSource.installedBeta(at: bundle, shortVersion: "27.0") == nil)
        try Self.plist("<key>seedNumber</key><string>5</string>")
            .write(to: resources.appendingPathComponent("BetaVersion.plist"))
        #expect(XcodeReleasesSource.installedBeta(at: bundle, shortVersion: "27.0")
            == .init(shortVersion: "27.0", seed: 5))
        #expect(XcodeReleasesSource.installedBeta(at: bundle, shortVersion: nil) == nil)
    }

    // MARK: - The offer, and what the engine makes of it

    /// Unknown beta 7 while the RC is out: offered the RC, and the engine agrees
    /// it is an update — the lineage places the unknown build.
    @Test func anUnknownBetaIsOfferedWhatIsAboveIt() throws {
        let remote = try #require(Self.remote(
            build: "27A9001z", beta: .init(shortVersion: "27.0", seed: 7)))
        #expect(remote.version == "27A266a")
        #expect(remote.installedDisplayVersion == "27.0 beta 7 (27A9001z)")
        #expect(remote.buildLineage?.isNewer("27A266a", than: "27A9001z") == true)
        #expect(UpdateChecker.evaluate(installed: Self.app(build: "27A9001z"), remote: remote)
            == .updateAvailable(latest: "27.0 RC 1 (27A266a)"))
    }

    /// Unknown beta 7 when the index tops out at beta 6: nothing above it, so it
    /// is its own offer — never beta 6 (a downgrade) — and the engine reads
    /// up to date on purpose, because the copy is ahead of the index.
    @Test func anUnknownBetaAheadOfTheIndexIsNeverOfferedADowngrade() throws {
        let remote = try #require(Self.remote(
            build: "27A9001z", beta: .init(shortVersion: "27.0", seed: 7),
            in: Self.releases(droppingRC: true)))
        #expect(remote.version == "27A9001z")
        #expect(remote.buildLineage?.isNewer("27A5252f", than: "27A9001z") == false)
        #expect(UpdateChecker.evaluate(installed: Self.app(build: "27A9001z"), remote: remote)
            == .upToDate)
    }

    /// Equal rank is not above: an unknown respin of beta 6 while the index lists
    /// beta 6 under another build cannot be ordered against it, so no answer —
    /// neither "update" nor "up to date".
    @Test func anUnknownRespinOfAListedSeedGetsNoAnswer() {
        #expect(Self.remote(
            build: "27A9002z", beta: .init(shortVersion: "27.0", seed: 6),
            in: Self.releases(droppingRC: true)) == nil)
    }

    /// ...but something strictly above both is still offered.
    @Test func anUnknownRespinIsStillOfferedWhatIsAboveBoth() throws {
        let remote = try #require(Self.remote(
            build: "27A9002z", beta: .init(shortVersion: "27.0", seed: 6)))
        #expect(remote.version == "27A266a")
    }

    /// The host's macOS floor still bounds the candidates: on 26.4 the RC (26.6)
    /// is out of reach, beta 6 is below, so the copy is its own offer.
    @Test func theMacOSFloorStillApplies() throws {
        let remote = try #require(Self.remote(
            build: "27A9001z", beta: .init(shortVersion: "27.0", seed: 7), osVersion: "26.4.0"))
        #expect(remote.version == "27A9001z")
    }

    /// No `BetaVersion.plist` (an RC or GA, or a bundle that says nothing): an
    /// unknown build keeps today's answer, nil.
    @Test func anUnknownBuildWithoutTheFileIsStillNil() {
        #expect(Self.remote(build: "27A9001z", beta: nil) == nil)
    }
}
