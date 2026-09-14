import Testing
import Foundation
@testable import DuoUpdaterCore

/// Xcode is the awkward case the rest of the engine's assumptions don't cover: two
/// installs share a bundle id, a display name AND a marketing version, the build
/// number that identifies them is in none of the usual places, and the only index
/// of releases mixes betas, RCs and shipping versions in one list.
///
/// These lock down the three ways that can go wrong: reading the wrong build (every
/// Xcode reads as out of date forever), crossing tracks (a beta user offered a
/// downgrade, or a release user offered a beta), and guessing at a build we don't
/// recognise.
@Suite struct XcodeReleasesTests {

    /// A trimmed slice of `xcodereleases.com/data.json`, keeping the shapes that
    /// matter: an arch-split duplicate, an RC sharing its build with the release,
    /// a different product to filter out, and the beta ladder.
    static let feed = Data("""
    [
      {"name":"Xcode","_versionOrder":27000000005,
       "version":{"number":"27.0","build":"27A5237l","release":{"beta":5}},
       "links":{"notes":{"url":"https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes"}}},
      {"name":"Xcode","_versionOrder":27000000001,
       "version":{"number":"27.0","build":"27A5194q","release":{"beta":1}}},
      {"name":"Xcode","_versionOrder":26006000999,
       "version":{"number":"26.6","build":"17F113","release":{"release":true}}},
      {"name":"Xcode (Apple Silicon)","_versionOrder":26006000902,
       "version":{"number":"26.6","build":"17F113","release":{"rc":2}}},
      {"name":"Xcode (Universal)","_versionOrder":26006000901,
       "version":{"number":"26.6","build":"17F109","release":{"rc":1}}},
      {"name":"Xcode","_versionOrder":26005000999,
       "version":{"number":"26.5","build":"17F42","release":{"release":true}}},
      {"name":"Xcode Tools","_versionOrder":99000000000,
       "version":{"number":"99.0","build":"99Z999","release":{"release":true}}}
    ]
    """.utf8)

    static func releases() -> [XcodeReleasesSource.Release] {
        XcodeReleasesSource.parse(feed)
    }

    @Test func keepsXcodeVariantsAndDropsOtherProducts() {
        let builds = Set(Self.releases().map(\.build))
        // "Xcode (Apple Silicon)" / "(Universal)" are the same releases packaged for
        // one arch — they must survive, or an arch-split release goes missing.
        #expect(builds.contains("17F109"))
        // "Xcode Tools" is a different product; letting it in would make its version
        // the newest thing in the index.
        #expect(!builds.contains("99Z999"))
    }

    @Test func labelsTheTrackInTheDisplayedVersion() throws {
        let byBuild = Dictionary(grouping: Self.releases(), by: \.build)
        // The build rides along: it is Xcode's only exact identity, and betas get
        // respun under the same number (27A5194o and 27A5194q are both "beta 1").
        #expect(byBuild["27A5237l"]?.first?.displayVersion == "27.0 beta 5 (27A5237l)")
        #expect(byBuild["17F109"]?.first?.displayVersion == "26.6 RC 1 (17F109)")
        // A shipping release carries no track word — just the version and its build.
        #expect(byBuild["17F42"]?.first?.displayVersion == "26.5 (17F42)")
    }

    /// The machine this was built on: beta 1 installed while beta 5 is out.
    @Test func aBetaIsOfferedTheNewerBeta() throws {
        let (installed, offer) = try #require(
            XcodeReleasesSource.offer(forBuild: "27A5194q", in: Self.releases()))
        #expect(offer.build == "27A5237l")
        // Both sides are named the same way, from the same formatter, so the row
        // reads "27.0 beta 1 → 27.0 beta 5" rather than putting an opaque build
        // number opposite a friendly label.
        #expect(installed.displayVersion == "27.0 beta 1 (27A5194q)")
        #expect(offer.displayVersion == "27.0 beta 5 (27A5237l)")
    }

    /// The other copy on that machine: already the newest beta, so the offer is
    /// itself — the engine then compares equal builds and says "up to date". The
    /// source never asserts a verdict of its own.
    @Test func theNewestBetaIsOfferedItself() throws {
        let (installed, offer) = try #require(
            XcodeReleasesSource.offer(forBuild: "27A5237l", in: Self.releases()))
        #expect(offer.build == "27A5237l")
        #expect(installed.build == offer.build)
    }

    /// The floor rule, in the direction that matters: a shipping Xcode must never be
    /// pointed at a beta, however much newer the beta is. 27.0 beta 5 outranks 26.6
    /// by every ordering — stability is what has to stop it.
    @Test func aReleaseIsNeverOfferedAPrerelease() throws {
        let (_, offer) = try #require(
            XcodeReleasesSource.offer(forBuild: "17F42", in: Self.releases()))
        #expect(offer.build == "17F113")
        #expect(offer.stability == .release)
    }

    /// Same build, two entries (26.6 RC 2 and 26.6 release are the same binary).
    /// Reading it as the RC would then offer "the 26.6 release" as an update to
    /// itself; reading it as the release is both true and stable.
    @Test func aBuildSharedByAnRCAndItsReleaseReadsAsTheRelease() throws {
        let (installed, _) = try #require(
            XcodeReleasesSource.offer(forBuild: "17F113", in: Self.releases()))
        #expect(installed.build == "17F113")
        #expect(installed.stability == .release)
    }

    /// The top of the real index on 2026-09-14: Xcode 27 RC 1 above the beta ladder.
    /// Kept apart from `feed`, whose newest beta is meant to have nothing above it.
    static let rcFeed = Data("""
    [
      {"name":"Xcode","_versionOrder":27000000901,
       "version":{"number":"27.0","build":"27A266a","release":{"rc":1}}},
      {"name":"Xcode","_versionOrder":27000000006,
       "version":{"number":"27.0","build":"27A5252f","release":{"beta":6}}},
      {"name":"Xcode","_versionOrder":27000000005,
       "version":{"number":"27.0","build":"27A5237l","release":{"beta":5}}},
      {"name":"Xcode","_versionOrder":26006000999,
       "version":{"number":"26.6","build":"17F113","release":{"release":true}}}
    ]
    """.utf8)

    private static func installedXcode(build: String) -> InstalledApp {
        let path = "/Applications/ZZFixture-Xcode-beta.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        return InstalledApp(
            name: "Xcode",
            bundleID: XcodeReleasesSource.bundleID,
            shortVersion: "27.0",
            buildVersion: build,
            path: URL(fileURLWithPath: path),
            isMASApp: false,
            sparkleFeedURL: nil)
    }

    /// The reported row: beta 5 installed, RC 1 out. The source offered the RC, and
    /// the engine then compared the two builds as strings — `27A5237l` beats
    /// `27A266a` because 5237 > 266 — so the row read "up to date" with the RC drawn
    /// as a downgrade. The verdict has to come from the index's order, as the offer
    /// did.
    @Test func aBetaIsOfferedItsRCAndTheEngineAgrees() throws {
        #expect(VersionComparator.isNewer("27A5237l", than: "27A266a"),
                "precondition: this ordering is why the build string cannot decide it")
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "27A5237l", in: XcodeReleasesSource.parse(Self.rcFeed)))
        #expect(remote.version == "27A266a")

        let app = Self.installedXcode(build: "27A5237l")
        let status = UpdateChecker.evaluate(installed: app, remote: remote)
        #expect(status == .updateAvailable(latest: "27.0 RC 1 (27A266a)"))
        #expect(UpdatePolicy.laggingRemoteVersion(
            UpdateResult(app: app, remote: remote, status: status)) == nil)
    }

    /// And once the RC is installed: offered itself, current, and not a downgrade.
    @Test func theInstalledRCIsUpToDate() throws {
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "27A266a", in: XcodeReleasesSource.parse(Self.rcFeed)))
        let app = Self.installedXcode(build: "27A266a")
        let status = UpdateChecker.evaluate(installed: app, remote: remote)
        #expect(status == .upToDate)
        #expect(UpdatePolicy.laggingRemoteVersion(
            UpdateResult(app: app, remote: remote, status: status)) == nil)
    }

    /// An unrecognised seed. Guessing a track here is how a beta user gets offered a
    /// downgrade, so the source declines to answer and the row reads "unknown".
    @Test func anUnknownBuildIsNotGuessedAt() {
        #expect(XcodeReleasesSource.offer(forBuild: "27A9999z", in: Self.releases()) == nil)
    }

    /// The version trap, on a bundle laid out like a real Xcode: `CFBundleVersion`
    /// and `DTXcodeBuild` are both present and both wrong. Only
    /// `Contents/version.plist` carries the build Apple publishes.
    @Test func readsThePublishedBuildNotCFBundleVersion() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XcodeReleasesTests-\(UUID().uuidString)")
        let contents = dir.appendingPathComponent("Xcode-beta.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>ProductBuildVersion</key><string>27A5237l</string>
        </dict></plist>
        """.utf8).write(to: contents.appendingPathComponent("version.plist"))

        let bundle = dir.appendingPathComponent("Xcode-beta.app")
        #expect(AppScanner.productBuildVersion(in: bundle) == "27A5237l")
        // No version.plist → nil, so every other app keeps its CFBundleVersion.
        #expect(AppScanner.productBuildVersion(in: dir) == nil)
    }
}
