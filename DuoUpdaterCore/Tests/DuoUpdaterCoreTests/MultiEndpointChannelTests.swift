import Foundation
import Testing

@testable import DuoUpdaterCore

/// One channel, several endpoints, highest wins — `VendorProbeSource.best`.
///
/// This exists for vendors that publish two equally legitimate views of "latest"
/// (Claude: a public GA redirect and a device-keyed staged-rollout endpoint) where
/// which one leads flips during a release ramp. Ranking is offline and pure, so it
/// is pinned here rather than against the network.
@Suite struct MultiEndpointChannelTests {

    private func outcome(
        _ version: String?, failure: ProbeFailure? = nil,
        publishedAt: Date? = nil, downloadURL: URL? = nil, tag: String = ""
    ) -> ProbeOutcome {
        ProbeOutcome(
            recipeID: "vendor:test:stable:\(tag.isEmpty ? (version ?? "none") : tag)",
            bundleID: "test", channel: .stable,
            remote: version.map {
                RemoteVersion(
                    shortVersion: $0, version: nil, downloadURL: downloadURL,
                    sourceName: VendorProbeSource.sourceName, publishedAt: publishedAt)
            },
            failure: failure)
    }

    @Test func theHighestVersionWins() throws {
        let best = try #require(VendorProbeSource.best(of: [
            outcome("1.30096.1"), outcome("1.30096.5"),
        ]))
        #expect(best.remote?.shortVersion == "1.30096.5")
    }

    /// Order must not decide it — the GA endpoint is listed first in the registry
    /// and today the rollout endpoint is the one that's ahead.
    @Test func orderDoesNotDecideIt() throws {
        let ascending = try #require(VendorProbeSource.best(of: [
            outcome("1.30096.1"), outcome("1.30096.5"),
        ]))
        let descending = try #require(VendorProbeSource.best(of: [
            outcome("1.30096.5"), outcome("1.30096.1"),
        ]))
        #expect(ascending.remote?.shortVersion == descending.remote?.shortVersion)
    }

    /// A broken endpoint must not drag down a working one, or adding the second
    /// endpoint would make detection *less* reliable than one alone.
    @Test func aFailingEndpointDoesNotSuppressAWorkingOne() throws {
        let best = try #require(VendorProbeSource.best(of: [
            outcome(nil, failure: .httpStatus(500)), outcome("1.30096.5"),
        ]))
        #expect(best.remote?.shortVersion == "1.30096.5")
    }

    /// When everything failed we still report a concrete failure, so the health
    /// record and the log name a reason instead of a bare "no version".
    @Test func allFailedStillReportsAFailure() throws {
        let best = try #require(VendorProbeSource.best(of: [
            outcome(nil, failure: .httpStatus(500)),
            outcome(nil, failure: .versionPatternNoMatch(sampleBytes: 10)),
        ]))
        #expect(best.remote == nil)
        #expect(best.failure != nil)
    }

    @Test func noOutcomesIsNil() {
        #expect(VendorProbeSource.best(of: []) == nil)
    }

    /// The tie is the interesting case, and it is NOT a coin flip. Only one of
    /// Claude's endpoints states a publish time, and the ramp is the only window
    /// in which that time is obtainable: `ReleaseTimelineStore.record` logs each
    /// version once at first sighting, so a version whose exact date we didn't
    /// capture before the endpoints converged is stuck as an estimated window
    /// forever. Letting registry order win a tie threw that away.
    @Test func aTieGoesToTheOutcomeCarryingAPublishDate() throws {
        let dated = Date(timeIntervalSince1970: 1_786_747_824)
        // Both orderings: the bare answer must not win by being listed first.
        for pair in [
            [outcome("1.30096.5", tag: "ga"),
             outcome("1.30096.5", publishedAt: dated, tag: "rollout")],
            [outcome("1.30096.5", publishedAt: dated, tag: "rollout"),
             outcome("1.30096.5", tag: "ga")],
        ] {
            let best = try #require(VendorProbeSource.best(of: pair))
            #expect(best.recipeID.hasSuffix("rollout"))
            #expect(best.remote?.publishedAt == dated)
        }
    }

    /// A *newer* version still wins even if the older answer is the richer one —
    /// the publish date is a tie-break, never a reason to report a stale version.
    @Test func aRicherOutcomeNeverBeatsANewerVersion() throws {
        let best = try #require(VendorProbeSource.best(of: [
            outcome("1.30096.1", publishedAt: Date(), downloadURL: URL(string: "https://x/a.zip")),
            outcome("1.30096.5"),
        ]))
        #expect(best.remote?.shortVersion == "1.30096.5")
    }

    /// With neither side dated, an installable answer beats a detection-only one,
    /// so adding a detection-only endpoint can't silently kill one-click.
    @Test func aTieWithoutDatesGoesToTheInstallableAnswer() throws {
        let best = try #require(VendorProbeSource.best(of: [
            outcome("1.30096.5", tag: "detect"),
            outcome("1.30096.5", downloadURL: URL(string: "https://x/a.zip"), tag: "install"),
        ]))
        #expect(best.recipeID.hasSuffix("install"))
    }
}

/// The registry shape the Claude pair depends on. Offline: these are the
/// assumptions that, if quietly broken by a later edit, would put detection back
/// where it was on 2026-08-15 — blind for the length of a rollout ramp.
@Suite struct ClaudeRolloutRecipeTests {

    private static let bundleID = "com.anthropic.claudefordesktop"

    private var recipes: [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
    }

    @Test func bothEndpointsAreRegisteredOnTheSameChannel() throws {
        #expect(recipes.count == 2)
        #expect(Set(recipes.map(\.channel)) == [.stable])
        #expect(Set(recipes.compactMap(\.variant)) == ["ga", "rollout"])
    }

    /// The GA endpoint must stay id-free — it is the answer for a machine whose
    /// `ant-did` we can't read, and the reason the pair degrades gracefully.
    @Test func theGAEndpointNeedsNoIdentity() throws {
        let ga = try #require(recipes.first { $0.variant == "ga" })
        #expect(ga.identities.isEmpty)
        #expect(!ga.url.absoluteString.contains("device_id"))
    }

    @Test func theRolloutEndpointReadsClaudesOwnDeviceID() throws {
        let rollout = try #require(recipes.first { $0.variant == "rollout" })
        let identity = try #require(rollout.identities.first)
        #expect(identity.displayPath == "~/Library/Application Support/Claude/ant-did")
        #expect(rollout.url.absoluteString.contains("device_id=\(identity.placeholder)"))
    }

    /// The rollout endpoint's real 2026-08-15 body. Pinning the patterns against a
    /// captured response is the repo's rule for fragile recipes: a regex that only
    /// ever ran against a live endpoint proves nothing once the endpoint moves.
    private static let capturedBody = """
        {"currentRelease":"1.30096.5","releases":[{"version":"1.30096.5","updateTo":\
        {"name":"Claude 1.30096.5","version":"1.30096.5",\
        "pub_date":"2026-08-14T22:50:24.042387",\
        "url":"https://downloads.claude.ai/releases/darwin/universal/1.30096.5/\
        Claude-6e13464cbd9c3dc0501fe5ecb0568e3d3e9ea77a.zip",\
        "notes":"Production Release - No Notes"}}]}
        """

    @Test func thePatternsMatchTheCapturedResponse() throws {
        let rollout = try #require(recipes.first { $0.variant == "rollout" })

        #expect(
            VendorProbeRecipe.extractVersion(
                from: Self.capturedBody, pattern: rollout.versionPattern) == "1.30096.5")

        // `currentRelease`, not the first `version` — the two agree here, so pin
        // that the pattern actually keys on the authoritative field.
        #expect(rollout.versionPattern.contains("currentRelease"))

        let published = try #require(rollout.publishedAtPattern)
        #expect(
            VendorProbeRecipe.extractVersion(from: Self.capturedBody, pattern: published)
                == "2026-08-14T22:50:24.042387")

        let install = try #require(rollout.install)
        guard case .bodyPattern(let pattern) = install.urlSource else {
            Issue.record("rollout install must read the URL out of the same body")
            return
        }
        #expect(
            VendorProbeRecipe.extractVersion(from: Self.capturedBody, pattern: pattern)?
                .hasSuffix("Claude-6e13464cbd9c3dc0501fe5ecb0568e3d3e9ea77a.zip") == true)
    }

    /// The endpoint's `pub_date` carries no timezone, which `ISO8601DateFormatter`
    /// rejects outright — before this it read as "no release time" and Claude
    /// stayed out of the Release Log. Read as UTC: the stamp is 39s after the
    /// artifact's `Last-Modified: Fri, 14 Aug 2026 22:49:45 GMT`.
    @Test func theZonelessPubDateParsesAsUTC() throws {
        let parsed = try #require(ReleaseDate.parse("2026-08-14T22:50:24.042387"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)
        #expect(parts.year == 2026 && parts.month == 8 && parts.day == 14)
        #expect(parts.hour == 22 && parts.minute == 50 && parts.second == 24)

        // Whole seconds too, and a zoned stamp must still win its own formatter.
        #expect(ReleaseDate.parse("2026-08-14T22:50:24") != nil)
        #expect(ReleaseDate.parse("2026-08-14T22:50:24Z") == ReleaseDate.parse("2026-08-14T22:50:24"))
    }
}
