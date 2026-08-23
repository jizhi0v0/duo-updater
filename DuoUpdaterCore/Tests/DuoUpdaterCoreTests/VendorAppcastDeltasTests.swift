import Testing
import Foundation
@testable import DuoUpdaterCore

/// Pulling patches out of a vendor probe's response body.
///
/// This exists because ChatGPT — 31 GB of the traffic ledger's 97 GB, and the
/// entire reason the delta route was built — never reaches `SparkleAppcastSource`.
/// Its feed lives inside the app's asar, so only `VendorProbeRecipe` answers for
/// it and every install is served by `Vendor`. The body below is verbatim from
/// `chatgpt.com/backend-api/wham/app/appcast`, fetched 2026-08-23.
struct VendorAppcastDeltasTests {

    private let body = """
    <?xml version='1.0' encoding='utf-8'?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel>
            <title>Codex</title>
            <item>
                <title>26.818.41509</title>
                <sparkle:version>6962</sparkle:version>
                <sparkle:shortVersionString>26.818.41509</sparkle:shortVersionString>
                <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.818.41509.zip" length="604981045" type="application/octet-stream" sparkle:edSignature="archive-sig" />
                <sparkle:deltas>
                    <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT6962-6933-arm64.delta" sparkle:deltaFrom="6933" length="1943806" type="application/octet-stream" sparkle:edSignature="sig-6933" />
                    <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT6962-6892-arm64.delta" sparkle:deltaFrom="6892" length="17246734" type="application/octet-stream" sparkle:edSignature="sig-6892" />
                </sparkle:deltas>
            </item>
            <item>
                <title>26.818.32112</title>
                <sparkle:version>6933</sparkle:version>
                <sparkle:shortVersionString>26.818.32112</sparkle:shortVersionString>
                <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.818.32112.zip" length="604975173" type="application/octet-stream" sparkle:edSignature="older-archive-sig" />
                <sparkle:deltas>
                    <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT6933-6892-arm64.delta" sparkle:deltaFrom="6892" length="16379398" type="application/octet-stream" sparkle:edSignature="sig-older" />
                </sparkle:deltas>
            </item>
        </channel>
    </rss>
    """

    /// The recipe's regex resolves the marketing string, so that is what has to
    /// select the item — the build number is not what the caller has in hand.
    @Test func findsThePatchesForTheResolvedVersion() throws {
        let patches = VendorAppcastDeltas.patches(inBody: body, forVersion: "26.818.41509")
        #expect(patches.count == 2)
        let from6933 = try #require(patches.first { $0.fromBuild == "6933" })
        #expect(from6933.size == 1_943_806)
        #expect(from6933.edSignature == "sig-6933")
    }

    /// Matching on the build works too: a `versionIsBuild` recipe resolves that
    /// instead, and both must land on the same item.
    @Test func alsoMatchesOnTheBuildNumber() {
        #expect(VendorAppcastDeltas.patches(inBody: body, forVersion: "6962").count == 2)
    }

    /// The safety property. A probe's regex is free to select a different item
    /// than a feed reader would, so patches must never be taken from "the newest
    /// item" — only from the one naming the version being installed. Here the
    /// older item's single patch must not leak into the newer item's set.
    @Test func neverReturnsAnotherReleasesPatches() throws {
        let older = VendorAppcastDeltas.patches(inBody: body, forVersion: "26.818.32112")
        #expect(older.count == 1)
        #expect(older.first?.size == 16_379_398)

        let newer = VendorAppcastDeltas.patches(inBody: body, forVersion: "26.818.41509")
        #expect(!newer.contains { $0.size == 16_379_398 })
    }

    /// A version the feed does not carry yields nothing rather than a best guess:
    /// installing a patch cut for a different release would be authentic, correctly
    /// signed, and wrong.
    @Test func anUnknownVersionYieldsNothing() {
        #expect(VendorAppcastDeltas.patches(inBody: body, forVersion: "99.0.0").isEmpty)
    }

    /// Most probes answer with JSON, HTML, or a bare version string. Those must
    /// cost nothing and produce nothing.
    @Test func aBodyThatIsNotAnAppcastYieldsNothing() {
        #expect(VendorAppcastDeltas.patches(
            inBody: #"{"version":"1.2.3","url":"https://x/a.zip"}"#, forVersion: "1.2.3").isEmpty)
        #expect(VendorAppcastDeltas.patches(inBody: "4.87.0", forVersion: "4.87.0").isEmpty)
    }

    /// An appcast with no patches at all — the common case even among Sparkle
    /// feeds — is not an error.
    @Test func anAppcastWithoutPatchesYieldsNothing() {
        let plain = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel><item>
            <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
            <enclosure url="https://x/a.zip" length="10" sparkle:edSignature="s"/>
        </item></channel></rss>
        """
        #expect(VendorAppcastDeltas.patches(inBody: plain, forVersion: "1.0").isEmpty)
    }

    /// Two items claiming the same version is ambiguous, and the full archive is
    /// always correct — so refuse rather than pick one. TablePro really does
    /// publish one release twice (once per architecture), so this shape exists.
    @Test func ambiguousVersionsAreRefused() {
        let twice = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel>
        <item>
            <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
            <enclosure url="https://x/arm64.zip" length="10" sparkle:edSignature="a"/>
            <sparkle:deltas><enclosure url="https://x/a.delta" sparkle:deltaFrom="1" length="5"/></sparkle:deltas>
        </item>
        <item>
            <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
            <enclosure url="https://x/x86.zip" length="10" sparkle:edSignature="b"/>
            <sparkle:deltas><enclosure url="https://x/b.delta" sparkle:deltaFrom="1" length="5"/></sparkle:deltas>
        </item>
        </channel></rss>
        """
        #expect(VendorAppcastDeltas.patches(inBody: twice, forVersion: "2.0").isEmpty)
    }
}
