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

@Suite struct CarbonCopyClonerProbeRecipeTests {
    private func recipe() -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.bombich.ccc" }
    }

    @Test func recipeExistsAndUsesRedirectFilenameMode() throws {
        let recipe = try #require(self.recipe())
        guard case .redirectFilename = recipe.mode else {
            Issue.record("expected the redirect-filename mode"); return
        }
        // Two redirect hops stand between the probed URL and the versioned
        // filename (bombich.com → api.bombich.com → the CDN) — only the
        // default HEAD-and-follow behavior reaches the CDN's filename at all.
        #expect(recipe.followRedirects)
    }

    @Test func readsTheThreeSegmentMarketingVersionFromTheRedirectTarget() throws {
        let recipe = try #require(self.recipe())
        #expect(VendorProbeRecipe.extractVersion(
            from: cccRedirectFixture, pattern: recipe.versionPattern) == "7.1.6")
    }

    @Test func readsTheTwoSegmentHistoricalMarketingForm() throws {
        let recipe = try #require(self.recipe())
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
    /// separate decision this recipe deliberately does not make.
    @Test func detectionOnlyNoInstallSpec() throws {
        let recipe = try #require(self.recipe())
        #expect(recipe.install == nil)
    }

    @Test func stableChannelOnly() throws {
        let recipe = try #require(self.recipe())
        #expect(recipe.channel == .stable)
    }

    @Test func changelogPointsAtTheVendorsOwnReleaseNotesPage() throws {
        let recipe = try #require(self.recipe())
        #expect(recipe.changelogURL?.absoluteString == "https://bombich.com/software/updates/ccc7_rn.html")
    }
}
