import Testing
import Foundation
@testable import DuoUpdaterCore

/// `td.telegram.org` answers the HEAD that resolves Telegram's download with a
/// 502 in bursts — confirmed by interleaving URLSession and curl against the same
/// URL in the same seconds, both 502, so it is the vendor rather than our client.
/// The probe reported that as `installURLUnresolved`, which means "the one-click
/// is dead, go fix the recipe", and two of those in a row file an issue. These
/// pin the rule that keeps a vendor's bad minute from being blamed on a recipe.
struct InstallURLTransientTests {

    @Test func fiveHundredsAndTooManyRequestsAreTheVendorsProblem() {
        for code in [500, 502, 503, 504, 429] {
            #expect(VendorProbeSource.isTransientStatus(code), "\(code) should be transient")
        }
    }

    @Test func clientErrorsAreOurProblemAndMustNotBeRetried() {
        // A 404 means the URL in the recipe is wrong. Retrying cannot fix that,
        // and reporting it as transient would hide a genuinely dead install spec.
        for code in [400, 401, 403, 404, 410] {
            #expect(!VendorProbeSource.isTransientStatus(code), "\(code) should not be transient")
        }
    }

    @Test func theTwoWarningsAreDistinct() {
        // They accuse different people, so they must not collapse into one kind:
        // one is actionable, the other is deliberately not.
        #expect(ProbeWarning.installURLTransient(status: 502).kind == "installURLTransient")
        #expect(ProbeWarning.installURLUnresolved.kind == "installURLUnresolved")
        #expect(ProbeWarning.installURLTransient(status: 502)
            != ProbeWarning.installURLUnresolved)
    }

    @Test func theStatusIsCarriedSoAReportCanSayWhichOne() {
        #expect(ProbeWarning.installURLTransient(status: 502)
            != ProbeWarning.installURLTransient(status: 503))
        #expect(ProbeWarning.installURLTransient(status: nil)
            .kind == ProbeWarning.installURLTransient(status: 502).kind,
            "the kind is the wire format and must not vary with the status")
    }

    // MARK: - what a detection-only fallback is, and is not

    /// Discord PTB and Canary during `make release`, 2026-09-15: the download
    /// redirect answered `HTTP/2 429` (`retry-after: 3000`) and the live install
    /// sweep reported, for both channels, that the install "may be crossing
    /// channels" because it "resolved" the update MANIFEST URL.
    ///
    /// Nothing resolved the manifest as an installer. `resolveInstall` threw
    /// `TransientInstallURL` as designed, the probe fell back to detection-only,
    /// and `makeRemoteVersion` filled the detection-only `downloadURL` with
    /// `recipe.downloadURL ?? <probe endpoint>` — PTB and Canary carry no page, so
    /// that is the manifest. `crossChannelArtifact` then judged that URL as if it
    /// were the artifact, which turned a vendor's rate limit into an accusation
    /// that `duo verify` does not exempt the way it exempts the transient warning.
    ///
    /// Driven through the registered PTB proof (`^https://ptb\.`), against a stub
    /// that answers the feed and 429s the redirect HEAD — the stub URL can never
    /// satisfy that proof, so a complaint here is the false accusation itself.
    @Test func aRateLimitedRedirectIsTransientAndAccusesNoChannel() async throws {
        let ptb = try #require(
            VendorProbeRegistry.recipes.first {
                $0.bundleID == "com.hnc.DiscordPTB" && $0.channel == .ptb
            })
        let server = try InstallURLReachabilityTests.MethodAwareServer(
            headStatus: 429, rangedGetStatus: 429)
        defer { server.stop() }
        let recipe = VendorProbeRecipe(
            bundleID: ptb.bundleID,
            url: server.feedURL,
            mode: .responseBody,
            versionPattern: #""version":"([0-9.]+)""#,
            install: VendorInstallSpec(urlSource: .redirect(server.installURL), kind: .dmg),
            channel: ptb.channel)

        let outcome = await VendorProbeSource().probeDiagnostic(recipe)
        let remote = try #require(outcome.remote, "the version still reads: \(String(describing: outcome.failure))")
        #expect(outcome.warnings == [.installURLTransient(status: 429)],
                "the rate limit must be named as the vendor's, saw \(outcome.warnings)")
        #expect(remote.vendorInstallerKind == nil, "nothing was resolved to install")
        let complaint = RecipeSanity.crossChannelArtifact(recipe: recipe, remote: remote)
        #expect(complaint == nil,
                "a detection-only fallback is not an artifact to judge: \(complaint ?? "")")
    }

    /// The same property for every recipe and rule that CAN fall back, derived
    /// from the registries rather than listed: whatever a detection-only
    /// `downloadURL` holds — a vendor page, a probe endpoint, a releases page —
    /// the channel check must not read it as the install artifact. A 404 or a
    /// pattern that stopped matching lands on the same fallback as a 429, so this
    /// is not about rate limits.
    @Test func noDetectionOnlyFallbackIsJudgedAsAChannelArtifact() {
        // Counted, because a registry-derived loop that matches nothing asserts
        // nothing: rename `install` or `installAssetPattern` and this test would
        // go on passing while covering neither guard. Measured before the fix:
        // 30 recipes and 6 rules raise the false complaint, so both floors are
        // far below today's populations.
        var recipesChecked = 0
        var rulesChecked = 0
        for recipe in VendorProbeRegistry.recipes where recipe.install != nil {
            recipesChecked += 1
            let fallback = VendorProbeSource.makeRemoteVersion(
                recipe: recipe, version: "1.0.0", install: nil, plan: nil,
                resolvedDownload: recipe.url)
            let complaint = RecipeSanity.crossChannelArtifact(recipe: recipe, remote: fallback)
            #expect(complaint == nil, "\(recipe.recipeID): \(complaint ?? "")")
        }
        // `GitHubReleasesSource` falls back to the repository's releases page
        // when a rule names an install asset the release does not carry.
        for rule in GitHubReleaseRegistry.rules where rule.installAssetPattern != nil {
            rulesChecked += 1
            let fallback = RemoteVersion(
                shortVersion: "1.0.0", version: nil,
                downloadURL: URL(string: "https://github.com/\(rule.slug)/releases"),
                sourceName: "GitHub", requiresManualInstaller: true, vendorInstallerKind: nil)
            let complaint = RecipeSanity.crossChannelArtifact(rule: rule, remote: fallback)
            #expect(complaint == nil, "\(rule.recipeID): \(complaint ?? "")")
        }
        #expect(recipesChecked >= 20, "only \(recipesChecked) recipes carry an install spec — this loop has stopped covering the vendor guard")
        #expect(rulesChecked >= 5, "only \(rulesChecked) rules name an install asset — this loop has stopped covering the GitHub guard")
    }
}
