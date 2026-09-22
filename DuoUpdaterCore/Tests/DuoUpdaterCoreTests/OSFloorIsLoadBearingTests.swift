import Testing
import Foundation
@testable import DuoUpdaterCore

/// The vendor's declared macOS floor, now that every source that states one acts
/// on it (#640).
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
/// **Where the refusal lives, and why not in the engine.** Each source refuses
/// while CHOOSING its candidate — `usableItems` for Sparkle, `offer` for Xcode,
/// `AlcoveUpdateSource.remote(from:token:osVersion:)` for Alcove — so a release
/// this Mac cannot run never becomes a `RemoteVersion` at all.
/// `UpdateChecker.evaluate` asks nothing about the host: a host-dependent branch
/// there would make each of its ~60 comparison tests measure the machine it runs
/// on, and the only verdict it could return (`.upToDate`) draws a plain
/// checkmark — a second answer for a condition `AppStoreGate.needsNewerMacOS`
/// already renders properly. One row, one answer; the row state is #634 part 3.
///
/// One predicate throughout: `SignatureVerifier.canRun(minimumSystemVersion:on:)`,
/// which is also install-time gate 6. `HostOS`'s doc comment lists the sites.
///
/// Every host here is injected. Not one of these tests may ask the Mac it runs on
/// what OS that is; a test that did would answer differently in CI (CLAUDE.md).
///
/// ## Mutation table — every row was applied to the real source and run
///
/// | # | mutation | observed red |
/// |---|---|---|
/// | 1 | delete the `guard SignatureVerifier.canRun(…)` in `AlcoveUpdateSource.remote` | `aReleaseAboveTheHostsMacOSIsNotOffered` |
/// | 2 | flip that guard's sense (`canRun` → `!canRun`) | `aReleaseAboveTheHostsMacOSIsNotOffered`, `aFloorThisMacMeetsStillOffers`, `aRemoteWithNoFloorIsUnaffected` |
/// | 3 | `minimumSystemVersion: offer.requires` → `nil` in `XcodeReleasesSource.remote` | `theXcodeRemoteCarriesTheOfferedReleasesFloor` |
/// | 4 | drop `&& SignatureVerifier.canRun(…)` from `offer`'s candidate filter | `aMacBelowTheRCsFloorIsOfferedTheNewestRUNNABLEBuild`, `aMacBelowEveryNewerBuildsFloorIsOfferedItself` |
/// | 5 | `self.requires = json["requires"] as? String` → `= nil` | `theIndexsRequiresIsParsed`, `theXcodeRemoteCarriesTheOfferedReleasesFloor`, and both of #4's |
/// | 6 | Alcove's coding key `"minimum_system_version"` → `"minimumSystemVersion"` | `alcoveDecodesTheVendorsFloorVerbatim`, `aReleaseAboveTheHostsMacOSIsNotOffered`, `aFloorThisMacMeetsStillOffers`, `aRemoteWithNoFloorIsUnaffected` |
/// | 7 | delete `usableItems`' floor guard | `SparkleMaximumSystemVersionTests` × 3 (`aFeedWithNoCapIsUnaffected`'s `min: "28.0"` case, `theWindowIsClosedAtBothEnds`, `aCappedLegacyItemIsDroppedFromTheHistoryToo`) |
/// | 8 | `VendorHostRequirement.isSatisfied` returns `true` instead of checking its floor | `aProbeRecipesFloorStillGates` |
/// | 9 | `XcodeReleasesSource.offer` degenerates to `(installed, installed)` for every host | `aMacBelowTheRCsFloorIsOfferedTheNewestRUNNABLEBuild`, `theXcodeRemoteCarriesTheOfferedReleasesFloor`, and three pre-existing `XcodeReleasesTests` |
///
/// ⚠️ #9 is the one this suite does NOT catch where you would expect it to.
/// `aMacBelowEveryNewerBuildsFloorIsOfferedItself` stays GREEN under it, and pinning
/// the literal `"27A5237l"` (instead of the `offer.build == installed.build` this
/// used to assert, which is two outputs of one call compared against each other)
/// does not change that: on THIS host the degenerate answer and the correct answer
/// are the same build, so no assertion about this call can separate them. The
/// literal is still the right form — it states what the answer is rather than that
/// two unknowns agree — but what actually kills #9 is the other five tests, and
/// saying otherwise would be inventing coverage.
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
    private static func alcoveBody(floor: String?) -> Data {
        let line = floor.map { "\"minimum_system_version\":\"\($0)\"," } ?? ""
        return Data("""
        {"tag_name":"1.7.9","build_number":203,
         "published_at":"2026-06-30T20:57:57.000Z",
         \(line)
         "assets":[{"name":"Alcove.dmg","url":"https://api.tryalcove.com/updates/Alcove.dmg"}]}
        """.utf8)
    }

    private static func decodedAlcove(floor: String? = "15 Sequoia") throws -> UpdatesLatest {
        try JSONDecoder().decode(UpdatesLatest.self, from: alcoveBody(floor: floor))
    }

    /// What the source would offer on a given Mac, from the decoded body — never a
    /// literal floor, so a decode that silently stopped reading the field cannot
    /// leave the gate tests green.
    private static func alcoveRemote(floor: String? = "15 Sequoia", on osVersion: String)
        throws -> RemoteVersion? {
        AlcoveUpdateSource.remote(
            from: try decodedAlcove(floor: floor), token: "zz-fixture-token",
            osVersion: osVersion)
    }

    // MARK: - Alcove: the floor is parsed…

    @Test func alcoveDecodesTheVendorsFloorVerbatim() throws {
        #expect(try Self.decodedAlcove().minimumSystemVersion == "15 Sequoia")
    }

    // MARK: - …and now read

    /// The gate. A Mac below the vendor's floor is not offered the release at all —
    /// the source declines to build a `RemoteVersion`, exactly as `usableItems`
    /// declines to keep a feed item.
    ///
    /// "15 Sequoia" parses as 15 followed by a text token, and a text token ranks
    /// below a numeric one in `VersionComparator` — so 14.7.2 is below it and
    /// 15.0.0 is not, which is what the vendor means by the string.
    @Test func aReleaseAboveTheHostsMacOSIsNotOffered() throws {
        #expect(try Self.alcoveRemote(on: "14.7.2") == nil)
    }

    /// …and the gate is not wider than that: a Mac that MEETS the floor still gets
    /// the release, with the floor riding along on it. Without this, "refuse
    /// everything" passes the test above.
    @Test func aFloorThisMacMeetsStillOffers() throws {
        for host in ["15.0.0", "26.6.0"] {
            let remote = try #require(try Self.alcoveRemote(on: host), "refused on \(host)")
            #expect(remote.shortVersion == "1.7.9")
            #expect(remote.minimumSystemVersion == "15 Sequoia")
        }
    }

    /// The population this must not disturb: a body that declares no floor at all,
    /// and one whose floor cannot be read as a version. A gate that failed CLOSED
    /// on either would strand every app whose vendor says nothing — which is most
    /// of them.
    @Test func aRemoteWithNoFloorIsUnaffected() throws {
        let absent = try #require(try Self.alcoveRemote(floor: nil, on: "10.15.7"))
        #expect(absent.minimumSystemVersion == nil)
        // And an unreadable one fails open too — the same rule gate 6 states for a
        // floor it cannot parse.
        let unreadable = try #require(try Self.alcoveRemote(floor: "whenever", on: "10.15.7"))
        #expect(unreadable.minimumSystemVersion == "whenever")
    }

    // MARK: - Vendor probe recipes

    /// `VendorHostRequirement.isSatisfied` used to hand-write the floor comparison;
    /// it now calls `canRun` like everything else. Its architecture half is covered
    /// by `WorkBuddyProbeRecipeTests`; nothing covered the floor half, which is how
    /// a fourth copy of the comparison survived unnoticed.
    @Test func aProbeRecipesFloorStillGates() {
        let requirement = VendorHostRequirement(minimumSystemVersion: "15.0")
        #expect(!requirement.isSatisfied(byOS: "14.7.2", arch: .arm64))
        #expect(requirement.isSatisfied(byOS: "15.0.0", arch: .arm64))
        // Fails open on a value with no digit in it — the one behaviour change of
        // the switch to `canRun`, stated rather than left to be rediscovered.
        #expect(VendorHostRequirement(minimumSystemVersion: "Sequoia")
            .isSatisfied(byOS: "14.7.2", arch: .arm64))
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
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.4.0", followsBetaLine: false))
        #expect(onOld.build == "27A5252f")
        // Same index, a Mac that meets the RC's floor: the RC, as before.
        let (_, onNew) = try #require(XcodeReleasesSource.offer(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.6.0", followsBetaLine: false))
        #expect(onNew.build == "27A266a")
    }

    /// And when nothing newer is runnable, the offer is the installed release
    /// itself — the engine then compares equal builds and says "up to date". The
    /// source still asserts no verdict of its own.
    ///
    /// The build is pinned as a LITERAL, not as `offer.build == installed.build`:
    /// that comparison is two outputs of one call, so an `offer` degenerating to
    /// `(installed, installed)` for every host satisfies it (mutation 9).
    @Test func aMacBelowEveryNewerBuildsFloorIsOfferedItself() throws {
        let (installed, offer) = try #require(XcodeReleasesSource.offer(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.0.0", followsBetaLine: false))
        #expect(installed.build == "27A5237l")
        #expect(offer.build == "27A5237l")
        let app = Self.app(
            name: "Xcode-beta", bundleID: XcodeReleasesSource.bundleID,
            short: "27.0", build: "27A5237l")
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.0.0", host: .arm64, followsBetaLine: false))
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .upToDate)
    }

    /// The floor rides along on the remote — a fact about the release. Nothing
    /// reads it yet: the row's "requires macOS N" line (#634 part 3) would be its
    /// first consumer, and install-time gate 6 reads the downloaded bundle's own
    /// `LSMinimumSystemVersion`, not this.
    @Test func theXcodeRemoteCarriesTheOfferedReleasesFloor() throws {
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "27A5237l", in: Self.xcodeReleases(), osVersion: "26.6.0", host: .arm64, followsBetaLine: false))
        #expect(remote.version == "27A266a")
        #expect(remote.minimumSystemVersion == "26.6")
    }
}
