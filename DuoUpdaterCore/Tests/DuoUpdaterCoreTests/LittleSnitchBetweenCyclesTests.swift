import Foundation
import Testing
@testable import DuoUpdaterCore

/// obdev's `littlesnitch6.plist` between nightly cycles: the array holds the
/// `final` entry alone (`LittleSnitchFeedFixture.body20261003`). Neither recipe
/// is broken by that, and the sweep must not say they are — #861 filed the
/// nightly recipe as `versionPatternNoMatch`, #862 the stable one as
/// `entryPatternNoMatch`, both against a feed doing exactly what it does.
@Suite
struct LittleSnitchBetweenCyclesTests {

    private static func recipe(_ channel: ReleaseChannel) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "at.obdev.littlesnitch" && $0.channel == channel
        })
    }

    private static func probe(_ channel: ReleaseChannel, body: String) async throws -> ProbeOutcome {
        let server = try RecipeVerificationTests.StubServer(body: body, contentType: "application/xml")
        defer { server.stop() }
        return await VendorProbeSource(hostOSVersion: "26.0.0")
            .probeDiagnostic(try recipe(channel).with(url: server.url))
    }

    /// #862. Mutation: put back `guard starts.count > 1` in
    /// `VendorProbeRecipe.highestVersionEntry` → the warning returns.
    @Test func stableReadsAOneEntryFeedWithoutWarning() async throws {
        let outcome = try await Self.probe(.stable, body: LittleSnitchFeedFixture.body20261003)
        #expect(outcome.remote?.version == "7303")
        #expect(outcome.remote?.shortVersion == "6.5")
        #expect(outcome.warnings.isEmpty, "a one-entry array is one entry, not a fallback")
    }

    /// #861. Mutation: drop the nightly recipe's `trackClosedPattern` → a
    /// `.recipe`-class `versionPatternNoMatch` failure, i.e. a red row.
    @Test func nightlyIsClosedWhenTheFeedListsOnlyFinal() async throws {
        let outcome = try await Self.probe(.nightly, body: LittleSnitchFeedFixture.body20261003)
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.classification == .notApplicable)
        #expect(outcome.failure?.kind == "notApplicable")
    }

    /// While a nightly is on offer the same recipe still reads it — the closed
    /// signal is consulted only after the version pattern missed, and it does
    /// not match a feed that lists a nightly anyway.
    @Test func anOpenNightlyIsStillRead() async throws {
        let nightly = try Self.recipe(.nightly)
        #expect(!nightly.matchesTrackClosed(LittleSnitchFeedFixture.body20260829))
        let outcome = try await Self.probe(.nightly, body: LittleSnitchFeedFixture.body20260829)
        #expect(outcome.remote?.version == "7301")
    }

    /// The closed signal is "every lifecycle is `final`", not "no `nightly`".
    /// A renamed track, or a feed this recipe no longer understands, must stay a
    /// loud failure rather than read as a nightly train at rest forever.
    @Test func onlyAnAllFinalFeedReadsAsClosed() throws {
        let nightly = try Self.recipe(.nightly)
        #expect(nightly.matchesTrackClosed(LittleSnitchFeedFixture.body20261003))

        let renamedTrack = LittleSnitchFeedFixture.body20260829
            .replacingOccurrences(of: "<string>nightly</string>", with: "<string>beta</string>")
        #expect(!nightly.matchesTrackClosed(renamedTrack))

        let noFinal = LittleSnitchFeedFixture.body20261003
            .replacingOccurrences(of: "<string>final</string>", with: "<string>release</string>")
        #expect(!nightly.matchesTrackClosed(noFinal))

        #expect(!nightly.matchesTrackClosed("Malformed Request"))
        #expect(!nightly.matchesTrackClosed(#"<plist version="1.0"><array></array></plist>"#))
    }

    /// Stable has no closed state: a feed without its `final` entry is broken.
    @Test func stableDeclaresNoClosedState() throws {
        #expect(try Self.recipe(.stable).trackClosedPattern == nil)
    }
}
