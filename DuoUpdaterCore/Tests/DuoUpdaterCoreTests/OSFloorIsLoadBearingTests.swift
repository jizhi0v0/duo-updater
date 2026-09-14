import Testing
import Foundation
@testable import DuoUpdaterCore

/// The vendor's declared macOS floor, now that something reads it (#640).
///
/// Before this, `RemoteVersion.minimumSystemVersion` was write-only:
/// `AlcoveUpdateSource` decoded `minimum_system_version` and `SparkleAppcastSource`
/// copied `sparkle:minimumSystemVersion` onto it, and no consumer existed anywhere
/// in `App/Sources`, `CLI/Sources` or the engine. A Sparkle app was bounded anyway —
/// `usableItems` drops a too-high item before a `RemoteVersion` is ever built — so
/// the unread property was the WHOLE gate for every other source.
/// `XcodeReleasesSource` did not even parse its index's `requires`, which is the
/// one that had a live victim: a Mac on macOS 26.0–26.5 was shown Xcode 27.0 RC.
///
/// One predicate throughout: `SignatureVerifier.canRun(minimumSystemVersion:on:)`,
/// which is also install-time gate 6 and (since this change) the expression inside
/// `usableItems`. Never a second implementation — see `HostOS`.
///
/// Every host here is injected. Not one of these tests may ask the Mac it runs on
/// what OS that is; a test that did would answer differently in CI (CLAUDE.md).
///
/// ## Mutation table — every row was applied to the real source and run
///
/// | # | mutation | observed red |
/// |---|---|---|
/// | 1 | delete the `if !SignatureVerifier.canRun(…)` block at the top of `UpdateChecker.evaluate` | `aReleaseAboveTheHostsMacOSIsNotOffered` |
/// | 2 | flip that gate's sense (`!canRun` → `canRun`) | `aFloorThisMacMeetsStillOffers` (both hosts), `aRemoteWithNoFloorIsUnaffected` (both remotes), `aReleaseAboveTheHostsMacOSIsNotOffered` |
/// | 3 | `minimumSystemVersion: offer.requires` → `nil` in `XcodeReleasesSource.remote` | `theXcodeRemoteCarriesTheOfferedReleasesFloor` |
/// | 4 | drop `&& SignatureVerifier.canRun(…)` from `offer`'s candidate filter | `aMacBelowTheRCsFloorIsOfferedTheNewestRUNNABLEBuild`, `aMacBelowEveryNewerBuildsFloorIsOfferedItself` (its offer half only — the checker's gate still caught the verdict, which is what a backstop is for) |
/// | 5 | `self.requires = json["requires"] as? String` → `= nil` | `theIndexsRequiresIsParsed`, `theXcodeRemoteCarriesTheOfferedReleasesFloor`, and both of #4's — including the verdict half, since with no floor parsed the backstop has nothing to read either |
/// | 6 | Alcove's coding key `"minimum_system_version"` → `"minimumSystemVersion"` | `alcoveDecodesTheVendorsFloorVerbatim`, `aReleaseAboveTheHostsMacOSIsNotOffered` |
/// | 7 | delete `usableItems`' floor guard | `SparkleMaximumSystemVersionTests` × 3 (`aFeedWithNoCapIsUnaffected`'s `min: "28.0"` case, `theWindowIsClosedAtBothEnds`, `aCappedLegacyItemIsDroppedFromTheHistoryToo`) |
///
/// #6 changes the key rather than deleting the `CodingKeys` case because deleting
/// it does not compile (a property absent from `CodingKeys` needs a default), and
/// a mutation that fails to build proves nothing about the tests.
@Suite struct OSFloorIsLoadBearingTests {

    // MARK: - Fixtures

    /// Fabricated path, never a real one: `UpdatePolicy.runtimeBundlePath` resolves
    /// symlinks, so a fixture naming an app that happens to exist measures the
    /// machine instead of the code (CLAUDE.md).
    private static func app(name: String, bundleID: String, short: String, build: String?)
        -> InstalledApp {
        let path = "/Applications/ZZFixture-\(name).app"
        #expect(!FileManager.default.fileExists(atPath: path))
        return InstalledApp(
            name: name, bundleID: bundleID, shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    /// Alcove's `/updates/latest` payload.
    ///
    /// The floor — the field this is here for — is verbatim from a real body:
    /// `GET https://download.tryalcove.com/latest`, read 2026-09-15, served
    /// `{"version":"1.7.9","build":203,"published_at":"2026-06-30T20:57:57.000Z",
    /// "assets":[{"name":"Alcove.zip","size_bytes":15269999},
    /// {"name":"Alcove.dmg","size_bytes":16086914}],
    /// "minimum_system_version":"15 Sequoia"}`. Note the spelling: it is not a
    /// bare number, which is exactly the shape a floor check has to survive.
    ///
    /// ⚠️ The surrounding `tag_name`/`assets[].url` fields are the LICENSED
    /// endpoint's shape as `AlcoveUpdateSource` documents it, not a captured body:
    /// `api.tryalcove.com/updates/latest` needs a license key this checkout does
    /// not have, so it was not fetched. Stated rather than implied — only the
    /// floor and its spelling are measured here.
    static let alcoveLatest = Data("""
    {"tag_name":"1.7.9","build_number":203,
     "published_at":"2026-06-30T20:57:57.000Z",
     "minimum_system_version":"15 Sequoia",
     "assets":[{"name":"Alcove.dmg","url":"https://api.tryalcove.com/updates/Alcove.dmg"}]}
    """.utf8)

    private static func decodedAlcove() throws -> UpdatesLatest {
        try JSONDecoder().decode(UpdatesLatest.self, from: alcoveLatest)
    }

    /// The remote Alcove's source builds, with the floor it decoded — not a
    /// literal, so a decode that silently stopped reading the field cannot leave
    /// the gate tests green.
    private static func alcoveRemote() throws -> RemoteVersion {
        let latest = try decodedAlcove()
        return RemoteVersion(
            shortVersion: latest.tagName, version: nil,
            downloadURL: latest.assets.first?.url,
            minimumSystemVersion: latest.minimumSystemVersion,
            sourceName: "Vendor", requiresManualInstaller: false)
    }

    // MARK: - Alcove: the floor is parsed…

    @Test func alcoveDecodesTheVendorsFloorVerbatim() throws {
        #expect(try Self.decodedAlcove().minimumSystemVersion == "15 Sequoia")
    }

    // MARK: - …and now read

    /// The gate. A Mac below the vendor's floor is not offered the release.
    ///
    /// "15 Sequoia" parses as 15 followed by a text token, and a text token ranks
    /// below a numeric one in `VersionComparator` — so 14.7.2 is below it and
    /// 15.0.0 is not, which is what the vendor means by the string.
    @Test func aReleaseAboveTheHostsMacOSIsNotOffered() throws {
        let remote = try Self.alcoveRemote()
        let installed = Self.app(
            name: "Alcove", bundleID: AlcoveUpdateSource.bundleID, short: "1.7.7", build: nil)
        #expect(UpdateChecker.evaluate(installed: installed, remote: remote, osVersion: "14.7.2")
                == .upToDate)
    }

    /// …and the gate is not wider than that: a Mac that MEETS the floor still gets
    /// the update. Without this, "refuse everything" passes the test above.
    @Test func aFloorThisMacMeetsStillOffers() throws {
        let remote = try Self.alcoveRemote()
        let installed = Self.app(
            name: "Alcove", bundleID: AlcoveUpdateSource.bundleID, short: "1.7.7", build: nil)
        #expect(UpdateChecker.evaluate(installed: installed, remote: remote, osVersion: "15.0.0")
                == .updateAvailable(latest: "1.7.9"))
        #expect(UpdateChecker.evaluate(installed: installed, remote: remote, osVersion: "26.6.0")
                == .updateAvailable(latest: "1.7.9"))
    }

    /// The population this must not disturb: every source that declares no floor at
    /// all, which is most of them. A gate that fails CLOSED on a missing value
    /// would stop every one of those apps updating.
    @Test func aRemoteWithNoFloorIsUnaffected() {
        let installed = Self.app(
            name: "Subject", bundleID: "com.example.zzfixture", short: "1.0", build: nil)
        let remote = RemoteVersion(
            shortVersion: "2.0", version: nil, downloadURL: nil,
            minimumSystemVersion: nil, sourceName: "Vendor", requiresManualInstaller: false)
        #expect(UpdateChecker.evaluate(installed: installed, remote: remote, osVersion: "10.15.7")
                == .updateAvailable(latest: "2.0"))
        // And an unreadable one fails open too — same rule gate 6 states for a
        // floor it cannot parse.
        let unreadable = RemoteVersion(
            shortVersion: "2.0", version: nil, downloadURL: nil,
            minimumSystemVersion: "whenever", sourceName: "Vendor", requiresManualInstaller: false)
        #expect(UpdateChecker.evaluate(installed: installed, remote: unreadable, osVersion: "10.15.7")
                == .updateAvailable(latest: "2.0"))
    }

    // MARK: - Xcode

    private static func xcodeReleases() -> [XcodeReleasesSource.Release] {
        XcodeReleasesSource.parse(XcodeReleasesTests.rcFeed)
    }

    /// Measured on the live `xcodereleases.com/data.json`, 2026-09-15: all 451
    /// entries carry a `requires`, and the 27.0 ladder is not flat — RC 1 needs
    /// macOS 26.6, every 27.0 beta needs 26.4.
    @Test func theIndexsRequiresIsParsed() throws {
        let byBuild = Dictionary(grouping: Self.xcodeReleases(), by: \.build)
        #expect(byBuild["27A266a"]?.first?.requires == "26.6")
        #expect(byBuild["27A5252f"]?.first?.requires == "26.4")
    }

    /// The reported bug: a Mac on 26.4 was shown 27.0 RC, which needs 26.6. It is
    /// offered the newest build it can actually run instead — beta 6 — rather than
    /// nothing, because the floor bounds the CANDIDATES the way `usableItems` does.
    @Test func aMacBelowTheRCsFloorIsOfferedTheNewestRUNNABLEBuild() throws {
        let (_, onOld) = try #require(XcodeReleasesSource.offer(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.4.0"))
        #expect(onOld.build == "27A5252f")
        // Same index, a Mac that meets the RC's floor: the RC, as before.
        let (_, onNew) = try #require(XcodeReleasesSource.offer(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.6.0"))
        #expect(onNew.build == "27A266a")
    }

    /// And when nothing newer is runnable, the offer is the installed release
    /// itself — the engine then compares equal builds and says "up to date". The
    /// source still asserts no verdict of its own.
    @Test func aMacBelowEveryNewerBuildsFloorIsOfferedItself() throws {
        let (installed, offer) = try #require(XcodeReleasesSource.offer(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.0.0"))
        #expect(offer.build == installed.build)
        let app = Self.app(
            name: "Xcode-beta", bundleID: XcodeReleasesSource.bundleID,
            short: "27.0", build: "27A5237l")
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.0.0"))
        #expect(UpdateChecker.evaluate(installed: app, remote: remote, osVersion: "26.0.0")
                == .upToDate)
    }

    /// The floor also rides along on the remote, so anything downstream — the
    /// checker's own gate included — can see it rather than re-deriving it.
    @Test func theXcodeRemoteCarriesTheOfferedReleasesFloor() throws {
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.6.0"))
        #expect(remote.version == "27A266a")
        #expect(remote.minimumSystemVersion == "26.6")
    }
}
