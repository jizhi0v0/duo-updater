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
        // nothing. What is counted is the row where THIS GUARD decides the
        // answer, not the row the filter admits — the first version counted the
        // filter (135 recipes / 84 rules) against floors calibrated on the 30/6
        // that actually complain, so a drift that dropped every non-stable row
        // would have left ~97/74 iterations, both floors green, and zero
        // coverage: the same vacuity the counter was added to prevent.
        //
        // The population is measured rather than declared: judge the SAME url as
        // a resolved artifact, and if that complains, this row is one the guard
        // is holding quiet. No hand-kept list of channels to drift, and it stays
        // honest if a proof is added or retired.
        var proving = 0
        for recipe in VendorProbeRegistry.recipes where recipe.install != nil {
            let fallback = VendorProbeSource.makeRemoteVersion(
                recipe: recipe, version: "1.0.0", install: nil, plan: nil,
                resolvedDownload: recipe.url)
            let complaint = RecipeSanity.crossChannelArtifact(recipe: recipe, remote: fallback)
            #expect(complaint == nil, "\(recipe.recipeID): \(complaint ?? "")")
            // `fallback.downloadURL`, not `recipe.url`: the fallback carries
            // `recipe.downloadURL ?? recipe.url`, so judging the endpoint would
            // ask about a different string than the one under test for the two
            // recipes that have a page (28 rows instead of 30).
            let asArtifact = VendorProbeSource.makeRemoteVersion(
                recipe: recipe, version: "1.0.0", install: recipe.install,
                plan: (fallback.downloadURL ?? recipe.url, nil), resolvedDownload: nil)
            if RecipeSanity.crossChannelArtifact(recipe: recipe, remote: asArtifact) != nil {
                proving += 1
            }
        }
        #expect(proving >= 20,
                "only \(proving) recipes have a fallback the channel check would otherwise complain about — this loop has stopped covering the vendor guard")

        // `GitHubReleasesSource` falls back to the repository's releases page
        // when a rule names an install asset the release does not carry.
        var provingRules = 0
        for rule in GitHubReleaseRegistry.rules where rule.installAssetPattern != nil {
            let page = URL(string: "https://github.com/\(rule.slug)/releases")
            let fallback = RemoteVersion(
                shortVersion: "1.0.0", version: nil, downloadURL: page,
                sourceName: "GitHub", requiresManualInstaller: true, vendorInstallerKind: nil)
            let complaint = RecipeSanity.crossChannelArtifact(rule: rule, remote: fallback)
            #expect(complaint == nil, "\(rule.recipeID): \(complaint ?? "")")
            let asArtifact = RemoteVersion(
                shortVersion: "1.0.0", version: nil, downloadURL: page,
                sourceName: "GitHub", vendorInstallerKind: .zip)
            if RecipeSanity.crossChannelArtifact(rule: rule, remote: asArtifact) != nil {
                provingRules += 1
            }
        }
        #expect(provingRules >= 5,
                "only \(provingRules) rules have a fallback the channel check would otherwise complain about — this loop has stopped covering the GitHub guard")
        // Printed so the floors can be re-calibrated from a run rather than from
        // a grep: measured 30 recipes / 6 rules on 2026-09-16.
        FileHandle.standardError.write(
            Data("proving rows: \(proving) recipes, \(provingRules) rules\n".utf8))
    }

    // MARK: - #670: a rate limit that names its own wait

    // These four assert a request COUNT, because "did not retry" is the entire
    // property — a verdict-only assertion passes whether the loop stopped or
    // burned every attempt and then reported the same thing.
    //
    // Each was run against the mutation it claims to catch (2026-09-16); all four
    // mutations compile, and each killed exactly one of these and nothing else:
    //
    //   delete the `Retry-After` guard entirely (the bug as shipped)
    //     → aRateLimitLongerThanTheBackoffStopsAtTheFirstAttempt
    //   drop `http.statusCode == 429` so any transient status obeys the header
    //     → aServerErrorKeepsItsRetriesEvenWhenItNamesALongWait
    //   keep presence, drop the comparison (`retryAfterDelaySeconds(http) != nil`)
    //     → aRateLimitInsideTheBackoffBudgetKeepsItsRetries
    //   read an absent header as an infinite wait (`?? .infinity`)
    //     → aRateLimitThatNamesNoWaitKeepsItsRetries

    /// One `.redirect` recipe against a stub whose `/install` answers `status`
    /// with `headers`, reporting how many HEADs the stub actually saw.
    ///
    /// Goes through `probeDiagnostic` rather than `resolveInstall` (which is
    /// private) with `checkingInstallURL` left off, so every `HEAD /install` in
    /// the tally comes from the resolve loop and nothing else.
    private static func redirectAttempts(
        status: Int, headers: [String: String] = [:]
    ) async throws -> (heads: Int, warnings: [String]) {
        let server = try InstallURLReachabilityTests.MethodAwareServer(
            headStatus: status, rangedGetStatus: status, headHeaders: headers)
        defer { server.stop() }
        let recipe = VendorProbeRecipe(
            bundleID: "com.example.ratelimited",
            url: server.feedURL,
            mode: .responseBody,
            versionPattern: #""version":"([0-9.]+)""#,
            install: VendorInstallSpec(urlSource: .redirect(server.installURL), kind: .zip))
        let outcome = await VendorProbeSource().probeDiagnostic(recipe)
        return (server.requests().filter { $0 == "HEAD /install" }.count,
                outcome.warnings.map(\.display))
    }

    /// The bug: three attempts inside two seconds at a vendor that just said to
    /// come back in fifty minutes.
    ///
    /// Measured 2026-09-15 (`make release`, ledger
    /// `${TMPDIR}duo-events-tests/…/events.sqlite`): Discord's download redirect
    /// answered `HTTP/2 429`, `retry-after: 3000`, `x-ratelimit-scope: shared`,
    /// and the ledger holds six requests inside three seconds — two channels
    /// times three attempts. Attempts two and three could not possibly have
    /// succeeded; all they did was add to a bucket the header says is shared.
    ///
    /// The header is sent lower case here because that is how Cloudflare sent it.
    /// If `HTTPURLResponse` header lookup were case-sensitive this test would see
    /// three heads, which is the point of spelling it this way rather than
    /// canonically.
    @Test func aRateLimitLongerThanTheBackoffStopsAtTheFirstAttempt() async throws {
        let run = try await Self.redirectAttempts(
            status: 429, headers: ["retry-after": "3000"])
        #expect(run.heads == 1,
                Comment(rawValue: "a 3000s Retry-After must end the loop, saw \(run.heads) HEADs"))
        #expect(run.warnings == ["installURLTransient: HTTP 429"],
                Comment(rawValue: "stopping early must still report the rate limit: \(run.warnings)"))
    }

    /// The discriminator is the header, not the status. A 429 that does not say
    /// how long keeps the retries it has always had — the probe has no evidence
    /// the wait is long, and a rate limit with a one-second window is exactly
    /// what the backoff is for.
    @Test func aRateLimitThatNamesNoWaitKeepsItsRetries() async throws {
        let run = try await Self.redirectAttempts(status: 429)
        #expect(run.heads == 3,
                Comment(rawValue: "a bare 429 must still retry, saw \(run.heads) HEADs"))
    }

    /// And the other half of the discriminator: how big. A wait this probe is
    /// willing to sit through is not a reason to give up.
    @Test func aRateLimitInsideTheBackoffBudgetKeepsItsRetries() async throws {
        let run = try await Self.redirectAttempts(
            status: 429, headers: ["Retry-After": "1"])
        #expect(run.heads == 3,
                Comment(rawValue: "1s is inside the 2.1s this loop already waits, saw \(run.heads)"))
    }

    /// The case the retry exists for, pinned unchanged. `td.telegram.org` answers
    /// this HEAD with 502 in bursts that the next attempt clears, so a 5xx must
    /// keep all three attempts — including one carrying a `Retry-After`, which no
    /// measurement here has ever seen a 5xx do and which is therefore not a
    /// behaviour to change on speculation.
    @Test func aServerErrorKeepsItsRetriesEvenWhenItNamesALongWait() async throws {
        let run = try await Self.redirectAttempts(
            status: 502, headers: ["Retry-After": "3000"])
        #expect(run.heads == 3,
                Comment(rawValue: "Telegram's 502 bursts need the retry, saw \(run.heads) HEADs"))
    }
}
