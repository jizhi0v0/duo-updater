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

/// CCC 5 and CCC 6, confirmed 2026-08-29 to be independently, currently
/// maintained generations sharing `com.bombich.ccc` — see the registry
/// comment above the three stable recipes for the full evidence chain
/// (real downloaded/expanded zips for all three generations, same Team
/// `L4F2DED5Q7`, Bombich's own download page listing `?v=ccc5`/`?v=ccc6`/
/// `?v=ccc7` as live links alongside `?v=latest`).
private let cccSixRedirectFixture = "ccc-6.1.13.7699.zip"
private let cccFiveRedirectFixture = "ccc-5.1.28.6213.zip"

@Suite struct CarbonCopyClonerProbeRecipeTests {
    /// The three STABLE recipes are distinguished only by
    /// `installedVersionPattern` (all share bundle id and channel), so look
    /// each one up by that rather than by registration order, which would
    /// silently pick up whichever the registry happens to list first.
    private func stableRecipe(installedVersionPattern: String) -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first {
            $0.bundleID == "com.bombich.ccc" && $0.channel == .stable
                && $0.installedVersionPattern == installedVersionPattern
        }
    }

    private func stableRecipe() -> VendorProbeRecipe? { stableRecipe(installedVersionPattern: #"^7\."#) }
    private func ccc6Recipe() -> VendorProbeRecipe? { stableRecipe(installedVersionPattern: #"^6\."#) }
    private func ccc5Recipe() -> VendorProbeRecipe? { stableRecipe(installedVersionPattern: #"^5\."#) }

    private func betaRecipe() -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.bombich.ccc" && $0.channel == .beta }
    }

    /// Exactly four recipes for this bundle id: three stable generations (5/6/7)
    /// plus one beta (7 only — no evidence CCC 5/6 currently ship one). Catches
    /// a future recipe added for this bundle id without updating THIS test to
    /// account for it, the same shape of tripwire
    /// `littleSnitchStableAndNightlyRecipesResolveFromTheRealFeedWithoutCrossingChannels`
    /// uses for Little Snitch.
    @Test func exactlyFourRecipesRegisteredForThisBundleID() {
        let all = VendorProbeRegistry.recipes.filter { $0.bundleID == "com.bombich.ccc" }
        #expect(all.count == 4)
        #expect(all.filter { $0.channel == .stable }.count == 3)
        #expect(all.filter { $0.channel == .beta }.count == 1)
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

    /// Each generation's `hostRequirement.minimumSystemVersion` is pinned as a
    /// STATIC floor, which is only safe because Bombich treats it as a fixed
    /// per-generation commitment rather than something that drifts release to
    /// release — the reasoning (and the Wayback Machine evidence for CCC 6, and
    /// the independent KB-page witness for CCC 5) lives on the CCC 6/CCC 5
    /// recipe comments in the registry. Values read from the real mounted
    /// binaries' `LSMinimumSystemVersion`: 5→10.10, 6→10.15, 7→13.1 (both
    /// channels).
    @Test func hostRequirementMatchesEachGenerationsRealMinimumSystemVersion() throws {
        #expect(try #require(self.stableRecipe()).hostRequirement?.minimumSystemVersion == "13.1")
        #expect(try #require(self.betaRecipe()).hostRequirement?.minimumSystemVersion == "13.1")
        #expect(try #require(self.ccc6Recipe()).hostRequirement?.minimumSystemVersion == "10.15")
        #expect(try #require(self.ccc5Recipe()).hostRequirement?.minimumSystemVersion == "10.10")
    }

    /// The host gate itself, exercised directly (no network): a Mac running an
    /// OS below a generation's floor must not be offered that generation's
    /// build, and a Mac at-or-above the floor must be. Pure function, so this
    /// doesn't need a live install — `runs(onOS:arch:)` is the same check
    /// `VendorProbeSource.probeDiagnostic` applies before ever fetching.
    @Test func hostGateDeclinesAnOSBelowTheFloorAndAcceptsAtOrAboveIt() throws {
        let ccc7 = try #require(self.stableRecipe())
        #expect(!ccc7.runs(onOS: "12.6", arch: .arm64))  // Monterey: below CCC 7's Ventura floor
        #expect(ccc7.runs(onOS: "13.1", arch: .arm64))
        #expect(ccc7.runs(onOS: "15.0", arch: .arm64))

        let ccc6 = try #require(self.ccc6Recipe())
        #expect(!ccc6.runs(onOS: "10.14", arch: .arm64))  // Mojave: below CCC 6's Catalina floor
        #expect(ccc6.runs(onOS: "10.15", arch: .arm64))

        let ccc5 = try #require(self.ccc5Recipe())
        #expect(!ccc5.runs(onOS: "10.9", arch: .arm64))  // Mavericks: below CCC 5's Yosemite floor
        #expect(ccc5.runs(onOS: "10.10", arch: .arm64))
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

    // MARK: - CCC 6 / CCC 5 generations

    @Test func ccc6RecipeUsesItsOwnEndpointAndReadsItsFixture() throws {
        let recipe = try #require(self.ccc6Recipe())
        #expect(recipe.url.absoluteString == "https://bombich.com/software/download_ccc.php?v=ccc6")
        #expect(VendorProbeRecipe.extractVersion(
            from: cccSixRedirectFixture, pattern: recipe.versionPattern) == "6.1.13")
        #expect(recipe.changelogURL?.absoluteString == "https://bombich.com/en/kb/ccc/6/release-notes")
        #expect(recipe.install == nil)
    }

    @Test func ccc5RecipeUsesItsOwnEndpointAndReadsItsFixture() throws {
        let recipe = try #require(self.ccc5Recipe())
        #expect(recipe.url.absoluteString == "https://bombich.com/software/download_ccc.php?v=ccc5")
        #expect(VendorProbeRecipe.extractVersion(
            from: cccFiveRedirectFixture, pattern: recipe.versionPattern) == "5.1.28")
        #expect(recipe.changelogURL?.absoluteString == "https://bombich.com/en/kb/ccc/5/release-notes")
        #expect(recipe.install == nil)
    }

    /// The bug the whole three-recipe split exists to fix, pinned as a
    /// deterministic matrix: each generation's `installedVersionPattern` must
    /// match ONLY its own installed marketing string, never another
    /// generation's — a CCC 5 or CCC 6 install must never become a candidate
    /// for CCC 7's endpoint (or vice versa) just because "7.1.6" sorts higher
    /// than "5.1.28"/"6.1.13" numerically. Real installed-version strings from
    /// the mounted 2026-08-29 bundles, not synthetic ones.
    @Test func eachGenerationsPatternMatchesOnlyItsOwnInstalledVersion() throws {
        let ccc7 = try #require(self.stableRecipe())
        let ccc6 = try #require(self.ccc6Recipe())
        let ccc5 = try #require(self.ccc5Recipe())

        #expect(ccc7.matchesInstalled(version: "7.1.6"))
        #expect(!ccc7.matchesInstalled(version: "6.1.13"))
        #expect(!ccc7.matchesInstalled(version: "5.1.28"))

        #expect(!ccc6.matchesInstalled(version: "7.1.6"))
        #expect(ccc6.matchesInstalled(version: "6.1.13"))
        #expect(!ccc6.matchesInstalled(version: "5.1.28"))

        #expect(!ccc5.matchesInstalled(version: "7.1.6"))
        #expect(!ccc5.matchesInstalled(version: "6.1.13"))
        #expect(ccc5.matchesInstalled(version: "5.1.28"))
    }

    /// End-to-end through `VendorProbeSource` (not just the pure pattern above):
    /// a hypothetical future CCC generation this registry has no recipe for yet
    /// (e.g. "8.0.0") must resolve to nil — never silently fall back to ANY of
    /// the three existing generation recipes just because one happens to be
    /// registered. Skipped before any fetch, the same zero-candidates shape
    /// `dbBrowserStableRecipeDoesNotReachTheNightly` relies on, so this needs no
    /// network and stays fast.
    @Test func anUnrecognizedFutureGenerationResolvesToNilRatherThanFallingBackToAny() async throws {
        let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == "com.bombich.ccc" }
        let source = VendorProbeSource(recipes: recipes)
        let futureApp = InstalledApp(
            name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
            shortVersion: "8.0.0", buildVersion: "9000",
            path: URL(fileURLWithPath: "/Applications/Carbon Copy Cloner.app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: ReleaseChannel.detect(
                name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
                keystoneChannel: nil, version: "8.0.0"))
        #expect(try await source.latestVersion(for: futureApp) == nil)
    }

    /// The live counterpart to the matrix above, against the real vendor
    /// endpoints (2026-08-29) rather than a fixture — the repo's own rule that
    /// a recipe/pattern change needs a real-endpoint check, not just a unit
    /// test. Registers all three stable generations together (as the real
    /// registry does) and confirms a CCC 6 install resolves through the CCC 6
    /// endpoint specifically: the reported build is `7699` (CCC 6's), never
    /// `8368` (CCC 7's) — the exact cross-generation phantom this fix exists
    /// to prevent, caught here even if the pure-pattern matrix above were
    /// somehow satisfied by a registry that still wired the wrong URL to the
    /// wrong `installedVersionPattern`.
    @Test func ccc6InstallResolvesThroughTheCcc6EndpointLiveNotCcc7() async throws {
        let recipes = VendorProbeRegistry.recipes.filter {
            $0.bundleID == "com.bombich.ccc" && $0.channel == .stable
        }
        let source = VendorProbeSource(recipes: recipes)
        let installed = InstalledApp(
            name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
            shortVersion: "6.1.13", buildVersion: "7699",
            path: URL(fileURLWithPath: "/Applications/Carbon Copy Cloner.app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: ReleaseChannel.detect(
                name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
                keystoneChannel: nil, version: "6.1.13"))
        let remote = try await source.latestVersion(for: installed)
        // CCC is a marketing-only recipe (`versionIsBuild: false`), so the
        // comparable value rides in `shortVersion`, not `version` (which is
        // reserved for a build-number comparison basis and stays nil here —
        // see `VendorProbeSource.makeRemoteVersion`).
        #expect(remote?.shortVersion == "6.1.13")
        #expect(remote?.shortVersion != "7.1.6")
    }
}
