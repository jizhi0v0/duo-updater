import Testing
import Foundation
@testable import DuoUpdaterCore

/// Carbon Copy Cloner's probe reads the redirect target of
/// `download_ccc.php?v=latest`, which HEAD-follows two hops
/// (`bombich.com` → `api.bombich.com` → the CDN) to a versioned zip filename.
///
/// Captured 2026-08-29 with a plain `URLSession` HEAD request (the same request
/// `.redirectFilename` issues) against the live endpoint:
///   `https://bombich.com/software/download_ccc.php?v=latest`
///   → 302 → `https://api.bombich.com/download/ccc?v=latest`
///   → 302 → `https://bombich.scdn1.secure.raxcdn.com/software/files/ccc-7.1.6.8368.zip`
/// `7.1.6` matched the mounted app's `CFBundleShortVersionString` exactly, and
/// `8368` matched `CFBundleVersion`.
private let cccRedirectFixture = "ccc-7.1.6.8368.zip"

/// Older releases carry a two-segment marketing version before the build
/// (`7.1`, not `7.1.6`) — the exact "variable number of parts" the Homebrew
/// cask's own `livecheck` block calls out in its regex comment. The pattern
/// must handle both without a scheme change.
private let cccTwoSegmentMarketingFixture = "ccc-7.1.1234.zip"

/// The app's Info.plist DOES carry a Sparkle `SUFeedURL`
/// (`https://api.bombich.com/updates/ccc`, read from the real bundle inside the
/// vendor's own zip) — but every request variant tried against it (plain GET,
/// several User-Agents including a Sparkle-shaped one, an `appVersion` query
/// param) came back HTTP 200 with a ZERO-BYTE body, verified 2026-08-29 with
/// both Python's `urllib` and Swift's `URLSession` (the exact stack
/// `SparkleAppcastSource` uses). `SparkleAppcastSource.usableItems` would parse
/// that into an empty item array and report "no update" forever — this fixture
/// pins the empty response so a future change can't quietly start trusting it.
private let cccBrokenSparkleFeedFixture = ""

/// Beta channel, unblocked 2026-08-29 by trying `?v=latestbeta` (no hyphen) —
/// the query param the 2026-08-29 stable investigation never tried (it tried
/// `?v=beta` and `?v=latest-beta`, both dead ends). Captured with a plain
/// `URLSession` HEAD request against the live endpoint:
///   `https://bombich.com/software/download_ccc.php?v=latestbeta`
///   → 302 → `https://api.bombich.com/download/ccc?v=latestbeta`
///   → 302 → `https://bombich.scdn1.secure.raxcdn.com/software/files/ccc-7.1.7-b7.8389.zip`
/// Downloaded and expanded the real zip: `CFBundleShortVersionString="7.1.7-b7"
/// CFBundleVersion="8389" CFBundleIdentifier="com.bombich.ccc"`, Team
/// `L4F2DED5Q7`, notarized — the marketing field matches the probed capture
/// group exactly.
private let cccBetaRedirectFixture = "ccc-7.1.7-b7.8389.zip"

@Suite struct CarbonCopyClonerProbeRecipeTests {
    private func stableRecipe() -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.bombich.ccc" && $0.channel == .stable }
    }

    private func betaRecipe() -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.bombich.ccc" && $0.channel == .beta }
    }

    @Test func recipeExistsAndUsesRedirectFilenameMode() throws {
        let recipe = try #require(self.stableRecipe())
        guard case .redirectFilename = recipe.mode else {
            Issue.record("expected the redirect-filename mode"); return
        }
        // Two redirect hops stand between the probed URL and the versioned
        // filename (bombich.com → api.bombich.com → the CDN) — only the
        // default HEAD-and-follow behavior reaches the CDN's filename at all.
        #expect(recipe.followRedirects)
    }

    @Test func readsTheThreeSegmentMarketingVersionFromTheRedirectTarget() throws {
        let recipe = try #require(self.stableRecipe())
        #expect(VendorProbeRecipe.extractVersion(
            from: cccRedirectFixture, pattern: recipe.versionPattern) == "7.1.6")
    }

    @Test func readsTheTwoSegmentHistoricalMarketingForm() throws {
        let recipe = try #require(self.stableRecipe())
        #expect(VendorProbeRecipe.extractVersion(
            from: cccTwoSegmentMarketingFixture, pattern: recipe.versionPattern) == "7.1")
    }

    /// The broken Sparkle feed is not this recipe's endpoint, but the fixture
    /// documents why `SparkleAppcastSource` (which reads `SUFeedURL` from
    /// Info.plist directly, with no per-app registry entry) can never be the
    /// answer for this app: an empty body yields no appcast items at all.
    @Test func theBrokenSparkleFeedProducesNoAppcastItems() {
        #expect(SparkleAppcastParser.parse(Data(cccBrokenSparkleFeedFixture.utf8)).isEmpty)
    }

    /// Detection-only: CCC installs a privileged helper, a LaunchDaemon and an
    /// XPC service alongside the `.app`, so a one-click in-place swap is a
    /// separate decision this recipe deliberately does not make. Applies to
    /// both channels.
    @Test func detectionOnlyNoInstallSpec() throws {
        #expect(try #require(self.stableRecipe()).install == nil)
        #expect(try #require(self.betaRecipe()).install == nil)
    }

    @Test func stableRecipeIsStableChannel() throws {
        let recipe = try #require(self.stableRecipe())
        #expect(recipe.channel == .stable)
    }

    @Test func changelogPointsAtTheVendorsOwnReleaseNotesPage() throws {
        let recipe = try #require(self.stableRecipe())
        #expect(recipe.changelogURL?.absoluteString == "https://bombich.com/software/updates/ccc7_rn.html")
    }

    // MARK: - Beta channel

    @Test func betaRecipeExistsAndUsesTheLatestbetaEndpoint() throws {
        let recipe = try #require(self.betaRecipe())
        #expect(recipe.url.absoluteString == "https://bombich.com/software/download_ccc.php?v=latestbeta")
        guard case .redirectFilename = recipe.mode else {
            Issue.record("expected the redirect-filename mode"); return
        }
    }

    @Test func betaRecipeReadsTheMarketingVersionWithItsBetaSuffix() throws {
        let recipe = try #require(self.betaRecipe())
        #expect(VendorProbeRecipe.extractVersion(
            from: cccBetaRedirectFixture, pattern: recipe.versionPattern) == "7.1.7-b7")
    }

    /// The stable pattern must NOT accidentally match a beta filename — if it
    /// did, a beta artifact could be misread through the stable recipe's
    /// version comparison instead of being isolated to its own channel.
    @Test func stablePatternDoesNotMatchABetaFilename() throws {
        let recipe = try #require(self.stableRecipe())
        #expect(VendorProbeRecipe.extractVersion(
            from: cccBetaRedirectFixture, pattern: recipe.versionPattern) == nil)
    }

    /// Symmetric to the above: the beta pattern (which requires the `-b<N>`
    /// suffix) must not match an ordinary stable filename either.
    @Test func betaPatternDoesNotMatchAStableFilename() throws {
        let recipe = try #require(self.betaRecipe())
        #expect(VendorProbeRecipe.extractVersion(
            from: cccRedirectFixture, pattern: recipe.versionPattern) == nil)
    }

    @Test func betaRecipeChangelogPointsAtTheVendorsPrereleaseNotesPage() throws {
        let recipe = try #require(self.betaRecipe())
        #expect(recipe.changelogURL?.absoluteString == "https://bombich.com/software/updates/ccc7_rn_beta.html")
    }

    /// `ReleaseChannel.detect()` needed a new bundle-id-scoped rule (step 0.8)
    /// for the short `-b<N>` suffix CCC's beta uses — it matches neither the
    /// Mozilla `<maj>.<min>b<n>` shape (exactly one dot, no dash) nor the
    /// full-word `-beta<N>` shape (GitHub Desktop's). Verified against the
    /// real downloaded beta build's `CFBundleShortVersionString` and the
    /// installed stable string, plus one negative control confirming the rule
    /// is scoped to this bundle id and not a global pattern change.
    @Test func detectRecognizesTheShortBetaSuffix() {
        #expect(ReleaseChannel.detect(
            name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
            keystoneChannel: nil, version: "7.1.7-b7") == .beta)
        #expect(ReleaseChannel.detect(
            name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
            keystoneChannel: nil, version: "7.1.6") == .stable)
        // Scoped to this bundle id: an unrelated app with a superficially
        // similar-looking tail is not swept up by this rule.
        #expect(ReleaseChannel.detect(
            name: "Some App", bundleID: "com.example.other",
            keystoneChannel: nil, version: "7.1.7-b7") == .stable)
    }
}
