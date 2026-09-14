import Testing
import Foundation
@testable import DuoUpdaterCore

/// Carbon Copy Cloner's probe reads the redirect target of
/// `download_ccc.php?v=ccc7`, which HEAD-follows two hops
/// (`bombich.com` → `api.bombich.com` → the CDN) to a versioned zip filename.
///
/// Captured 2026-08-30 with a plain `URLSession`/`curl` HEAD request (the same
/// request `.redirectFilename` issues) against the live endpoint:
///   `https://bombich.com/software/download_ccc.php?v=ccc7`
///   → 302 → `https://api.bombich.com/download/ccc?v=ccc7`
///   → 302 → `https://bombich.scdn1.secure.raxcdn.com/software/files/ccc-7.1.6.8368.zip`
/// `7.1.6` matched the mounted app's `CFBundleShortVersionString` exactly, and
/// `8368` matched `CFBundleVersion`.
///
/// The generation-scoped `?v=ccc7` is deliberate: `?v=latest` resolved to the
/// byte-identical file when captured (confirmed 2026-08-30) but is a permanent
/// alias for whichever generation is newest, so it would start answering with
/// CCC 8 the day that ships. See `stableRecipeUsesTheGenerationScopedEndpoint`.
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

/// What `?v=latestbeta` answers with BETWEEN cycles — the build the beta train
/// graduated into, which is a plain stable filename. Captured 2026-09-14 with
/// the same HEAD-and-follow request `.redirectFilename` issues:
///   `https://bombich.com/software/download_ccc.php?v=latestbeta`
///   → 302 → `https://api.bombich.com/download/ccc?v=latestbeta`
///   → 302 → `https://bombich.download/ccc-7.2.8399.zip`
/// `?v=ccc7` and `?v=latest` resolved to the same filename in the same run, so
/// the beta endpoint is not answering with something of its own. (The CDN host
/// has also moved off `bombich.scdn1.secure.raxcdn.com` since the 2026-08-30
/// captures above; `.redirectFilename` reads the final URL's last path
/// component, so the recipe never saw the difference.)
///
/// That the 7.1.7 betas graduated as 7.2 rather than as a 7.1.7 is the vendor's
/// own text: `ccc7_rn.html` has no 7.1.7 section at all (7.1.6 → 7.2) and 7.2's
/// "What's new" is the beta page's cycle list item for item, down to "During our
/// latest beta testing cycle". See `docs/app-audits/com-bombich-ccc.md`.
private let cccGraduatedStableFixture = "ccc-7.2.8399.zip"

/// CCC 5 and CCC 6, confirmed 2026-08-29 to be separately downloadable
/// generations sharing `com.bombich.ccc` — the full evidence chain (real
/// downloaded/expanded zips for all three generations, same Team
/// `L4F2DED5Q7`, what Bombich's download page listed then) is in
/// `docs/app-audits/com-bombich-ccc.md#历史与实测`.
private let cccSixRedirectFixture = "ccc-6.1.13.7699.zip"

/// The artifact that does not exist yet. Shaped exactly like every real CCC
/// filename above — same `ccc-<marketing>.<build>.zip` scheme, same segment
/// counts — differing ONLY in the major version, so nothing but the anchor can
/// reject it. This is the fixture the endpoint/pattern fix is written against:
/// before it, both strings parsed cleanly through the CCC 7 recipes and a CCC 7
/// install would have been offered a paid major-version upgrade as if it were
/// the next point release.
private let cccEightRedirectFixture = "ccc-8.0.1.9000.zip"
private let cccEightBetaRedirectFixture = "ccc-8.0.2-b1.9012.zip"
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

    /// NOT symmetric to the above, on purpose — and this is the assertion the
    /// `-b<N>`-required pattern got backwards. This train runs in cycles, and
    /// between cycles `?v=latestbeta` answers with the build the train graduated
    /// into, so a beta pattern that rejects a plain filename rejects the vendor's
    /// ordinary resting state: the probe throws, the row shows a failed check,
    /// and `duo verify` — which walks recipes, not installs — files a red finding
    /// on every machine. Same call CotEditor's beta rule makes, for the same
    /// reasons; see the registry comment.
    ///
    /// Mutation: drop the `?` from `(?:-b[0-9]+)?` in the beta `versionPattern`
    /// (i.e. restore the shipped pattern) — this reads nil and fails.
    @Test func betaPatternReadsTheGraduatedStableFilenameOnPurpose() throws {
        let recipe = try #require(self.betaRecipe())
        #expect(VendorProbeRecipe.extractVersion(
            from: cccGraduatedStableFixture, pattern: recipe.versionPattern) == "7.2")
        // An open cycle still reads its own build — the suffix became optional,
        // not ignored. Both halves are needed, and the second one catches its own
        // mutation: dropping `-b[0-9]+` from the pattern entirely leaves the line
        // above passing (`7.2` still reads) while this one goes nil — measured,
        // not assumed, because the `\.[0-9]{3,}` that follows no longer lines up
        // with `-b7.8389` and the whole match fails rather than truncating.
        #expect(VendorProbeRecipe.extractVersion(
            from: cccBetaRedirectFixture, pattern: recipe.versionPattern) == "7.1.7-b7")
        // The historical two-segment marketing form is reachable through the
        // relaxed arm too, and must read the same version the stable recipe reads
        // from it rather than swallowing the build segment.
        #expect(VendorProbeRecipe.extractVersion(
            from: cccTwoSegmentMarketingFixture, pattern: recipe.versionPattern) == "7.1")
    }

    /// The ordering the fix depends on, asserted rather than assumed: a copy on
    /// the last prerelease of a closed cycle must read the graduation as NEWER,
    /// or the relaxed pattern resolves a version that is never offered.
    ///
    /// Cheaper here than CotEditor's equivalent and worth saying why: `7.2` beats
    /// `7.1.7-b7` at the SECOND component, so this never reaches the
    /// `.text`-versus-padded-`.number(0)` rule `7.1.0` / `7.1.0-beta.6` needs. The
    /// reverse direction is asserted too — it is what stops a stale between-cycles
    /// answer from being offered to a copy that is already ahead of it.
    @Test func theGraduationOutranksTheLastPrereleaseOfItsCycle() {
        #expect(VersionComparator.isNewer("7.2", than: "7.1.7-b7"))
        #expect(!VersionComparator.isNewer("7.1.7-b7", than: "7.2"))
        // And the shape a future cycle will graduate through, where the padding
        // rule IS what decides: a bare `7.3` against its own `7.3-b1`.
        #expect(VersionComparator.isNewer("7.3", than: "7.3-b1"))
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
        // The graduation reads `.stable` too, and that is deliberately left
        // alone: a copy that takes the build its beta cycle graduated into stops
        // being a beta copy, so the stable recipe serves it from then on. Pinned
        // here because it is the one-way cost of the beta recipe accepting a
        // stable filename — the decision is in the registry comment, and this is
        // what makes it a checked decision rather than a remark. Nothing in this
        // repo reads CCC's own "Inform me of beta releases" preference, so there
        // is no `ChannelBinding` to override this the way `CotEditorChannel`
        // overrides the equivalent for CotEditor.
        #expect(ReleaseChannel.detect(
            name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
            keystoneChannel: nil, version: "7.2") == .stable)
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

    // MARK: - The day CCC 8 ships

    /// The CCC 7 recipes must probe a GENERATION-SCOPED endpoint, never the
    /// `?v=latest` alias. Both resolve to the same file while CCC 7 is the newest
    /// generation (on 2026-08-30 both gave `ccc-7.1.6.8368.zip`), which is exactly
    /// why this needs a test rather than a live check: nothing observable before
    /// CCC 8 ships distinguishes the right URL from the wrong one. `?v=latest` is a
    /// permanent alias for whichever generation is NEWEST, so on CCC 8's release
    /// day it would hand this CCC-7-scoped recipe a CCC 8 artifact — the phantom
    /// cross-generation upgrade the three-recipe split exists to prevent,
    /// arriving through the URL instead of through the version comparison.
    ///
    /// The beta recipe is asserted separately and differently on purpose: there
    /// is no per-generation beta endpoint to switch to (probed 2026-08-30,
    /// `?v=ccc7beta`/`?v=ccc7-beta` answer with the STABLE ccc7 zip and
    /// `?v=beta7` falls back to the download page), so `?v=latestbeta` stays and
    /// the anchored pattern below is its only guard.
    @Test func stableRecipeUsesTheGenerationScopedEndpoint() throws {
        let recipe = try #require(self.stableRecipe())
        #expect(recipe.url.absoluteString == "https://bombich.com/software/download_ccc.php?v=ccc7")
        #expect(!recipe.url.absoluteString.contains("v=latest"))
        // Where the user is SENT must be pinned to the same generation as where
        // the version is READ — a `?v=latest` download link would eventually
        // hand a CCC 7 user a CCC 8 zip even with detection scoped correctly.
        #expect(recipe.downloadURL?.absoluteString
            == "https://bombich.com/software/download_ccc.php?v=ccc7")
        #expect(try #require(self.betaRecipe()).url.absoluteString
            == "https://bombich.com/software/download_ccc.php?v=latestbeta")
    }

    /// Every CCC recipe's `versionPattern` is anchored to its OWN major version,
    /// so a filename from another generation fails to match rather than parsing
    /// into a cross-generation version. Derived from the registry (the four
    /// recipes are looked up, not hand-listed) and run as a full matrix: each
    /// pattern against every generation's real filename plus the CCC 8 shapes
    /// that do not exist yet.
    ///
    /// This is the second, independent guard behind
    /// `stableRecipeUsesTheGenerationScopedEndpoint`: the endpoint fix depends
    /// on Bombich keeping `?v=ccc7` pointed at CCC 7 (as they have for
    /// `?v=ccc5`/`?v=ccc6` for years), and this one holds even if they do not.
    @Test func eachRecipesPatternReadsOnlyItsOwnGenerationsFilename() throws {
        let ccc7 = try #require(self.stableRecipe())
        let ccc6 = try #require(self.ccc6Recipe())
        let ccc5 = try #require(self.ccc5Recipe())
        let beta = try #require(self.betaRecipe())

        let everyFilename = [
            cccFiveRedirectFixture, cccSixRedirectFixture, cccRedirectFixture,
            cccTwoSegmentMarketingFixture, cccBetaRedirectFixture,
            cccGraduatedStableFixture,
            cccEightRedirectFixture, cccEightBetaRedirectFixture,
        ]
        /// What each recipe is allowed to read, keyed by filename. Anything not
        /// listed for a recipe must come back nil.
        ///
        /// The beta row is the widest on purpose and that is the change this
        /// matrix now pins: its `-b<N>` is optional, so every CCC 7 filename is
        /// legitimately readable through it (see the registry comment on why
        /// between-cycles resolution has to work). What it must STILL refuse is
        /// another generation — which is now carried by the major-7 anchor alone,
        /// since requiring `-b` used to reject `cccEightRedirectFixture` as a side
        /// effect and no longer does.
        let expected: [(VendorProbeRecipe, [String: String])] = [
            (ccc7, [cccRedirectFixture: "7.1.6", cccTwoSegmentMarketingFixture: "7.1",
                    cccGraduatedStableFixture: "7.2"]),
            (ccc6, [cccSixRedirectFixture: "6.1.13"]),
            (ccc5, [cccFiveRedirectFixture: "5.1.28"]),
            (beta, [cccBetaRedirectFixture: "7.1.7-b7", cccRedirectFixture: "7.1.6",
                    cccTwoSegmentMarketingFixture: "7.1",
                    cccGraduatedStableFixture: "7.2"]),
        ]
        for (recipe, allowed) in expected {
            for filename in everyFilename {
                let read = VendorProbeRecipe.extractVersion(
                    from: filename, pattern: recipe.versionPattern)
                #expect(
                    read == allowed[filename],
                    """
                    recipe \(recipe.variant ?? recipe.channel.rawValue) read \(read ?? "nil")                     from \(filename), expected \(allowed[filename] ?? "nil")
                    """)
            }
        }
    }

    /// The same guard end-to-end through `VendorProbeSource.probeDiagnostic` —
    /// the production `.redirectFilename` path, not just the extractor. A stub
    /// HTTP server standing in for the CDN serves the CCC 8 filename the vendor
    /// will one day redirect to; the CCC 7 recipes must report NOTHING rather
    /// than a "8.0.1" that would out-rank every installed CCC 7 build.
    ///
    /// Each half carries its own positive control served from the same stub, so
    /// a version that silently stopped being read at all (which would also make
    /// the CCC 8 half pass) fails the test instead of hiding in it.
    @Test func aFutureCCC8ArtifactResolvesToNothingThroughTheCCC7Recipes() async throws {
        let server = try RecipeVerificationTests.StubServer(body: "", contentType: "application/zip")
        defer { server.stop() }
        /// `.redirectFilename` + `followRedirects` reads the FINAL URL's last
        /// path component; the stub answers any path, so the path IS the
        /// fixture. No redirect is needed to exercise the filename read.
        func url(_ filename: String) -> URL {
            URL(string: "http://127.0.0.1:\(server.port)/software/files/\(filename)")!
        }

        let ccc7 = try #require(self.stableRecipe())
        let beta = try #require(self.betaRecipe())

        let stableControl = await VendorProbeSource()
            .probeDiagnostic(ccc7.with(url: url(cccRedirectFixture)))
        #expect(stableControl.remote?.shortVersion == "7.1.6")

        let stableFuture = await VendorProbeSource()
            .probeDiagnostic(ccc7.with(url: url(cccEightRedirectFixture)))
        #expect(stableFuture.remote == nil, "a CCC 8 zip must not resolve through the CCC 7 recipe")
        // Silent is not good enough: the miss has to reach `duo verify`, which
        // is what turns "this recipe went quiet" into a triaged recipe change
        // instead of an app that stops updating unnoticed.
        #expect(stableFuture.failure != nil)

        let betaControl = await VendorProbeSource()
            .probeDiagnostic(beta.with(url: url(cccBetaRedirectFixture)))
        #expect(betaControl.remote?.shortVersion == "7.1.7-b7")

        let betaFuture = await VendorProbeSource()
            .probeDiagnostic(beta.with(url: url(cccEightBetaRedirectFixture)))
        #expect(betaFuture.remote == nil, "a CCC 8 beta zip must not resolve through the CCC 7 beta recipe")
        #expect(betaFuture.failure != nil)

        // The beta recipe against a CCC 8 STABLE filename — newly reachable, and
        // the reason this half exists. `?v=latestbeta` is a "latest" alias with
        // no per-generation twin, so on CCC 8's release day it will answer this
        // recipe with a CCC 8 build; between cycles that build is a plain
        // `ccc-8.…zip`, which the `-b`-required pattern used to reject as a side
        // effect of requiring the suffix. Only the major-7 anchor stops it now.
        let betaFutureStable = await VendorProbeSource()
            .probeDiagnostic(beta.with(url: url(cccEightRedirectFixture)))
        #expect(betaFutureStable.remote == nil,
                "a CCC 8 stable zip must not resolve through the CCC 7 beta recipe")
        #expect(betaFutureStable.failure != nil)

        // Positive control for that half from the same stub: the between-cycles
        // answer the recipe is now supposed to read.
        let betaGraduated = await VendorProbeSource()
            .probeDiagnostic(beta.with(url: url(cccGraduatedStableFixture)))
        #expect(betaGraduated.remote?.shortVersion == "7.2")
    }

    /// The user-visible bug, end to end through `VendorProbeSource` rather than
    /// through the extractor: a copy on the last prerelease of a closed cycle
    /// detects as `.beta` (step 0.8), passes the channel gate onto the beta
    /// recipe and `installedVersionPattern`'s `^7\.`, and is offered the build
    /// its own train graduated into. Before the fix this whole path ended in
    /// `ProbeFailed` and the row showed a failed check.
    ///
    /// Served from the stub rather than the live endpoint so it keeps asserting
    /// the between-cycles behaviour after the vendor opens the next cycle —
    /// `betaEndpointStillResolvesAVersionLive` below is the live half.
    ///
    /// Mutation: restore the `-b[0-9]+`-required pattern — `latestVersion` goes
    /// nil and both expectations fail.
    @Test func aBetaCopyIsOfferedTheBuildItsCycleGraduatedInto() async throws {
        let server = try RecipeVerificationTests.StubServer(body: "", contentType: "application/zip")
        defer { server.stop() }
        let beta = try #require(self.betaRecipe())
        let endpoint = URL(
            string: "http://127.0.0.1:\(server.port)/\(cccGraduatedStableFixture)")!

        let source = VendorProbeSource(recipes: [beta.with(url: endpoint)])
        let installed = InstalledApp(
            name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
            shortVersion: "7.1.7-b7", buildVersion: "8389",
            path: URL(fileURLWithPath: "/Applications/Carbon Copy Cloner.app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: ReleaseChannel.detect(
                name: "Carbon Copy Cloner", bundleID: "com.bombich.ccc",
                keystoneChannel: nil, version: "7.1.7-b7"))
        #expect(installed.releaseChannel == .beta)

        let remote = try await source.latestVersion(for: installed)
        // Marketing-only recipe (`versionIsBuild: false`), so the comparable
        // value rides in `shortVersion` — same as the CCC 6 live test above.
        let offered = try #require(remote?.shortVersion)
        #expect(offered == "7.2")
        // Resolving it is only half the fix; it has to out-rank the installed
        // prerelease or nothing is ever offered.
        #expect(VersionComparator.isNewer(offered, than: "7.1.7-b7"))
    }

    /// The live half, and the one written to survive the vendor changing state.
    /// `?v=latestbeta` answers with a beta filename while a cycle is open and
    /// with the graduated stable between cycles, so asserting a VERSION here
    /// would go red on the vendor's schedule. What must hold in both states is
    /// that the recipe resolves a CCC 7 version at all — which is exactly the
    /// property that broke, and exactly what the nightly sweep files on.
    ///
    /// Mutation: restore the `-b[0-9]+`-required pattern — red today (the
    /// endpoint is between cycles), green while a cycle is open. That asymmetry
    /// is the point: this test is the live tripwire, and the stub-served tests
    /// above are what hold the behaviour down when it is not armed.
    ///
    /// ⚠️ WHAT IT CANNOT SEE, said out loud so it is not read as more than it is:
    /// `hasPrefix("7.")` is satisfied by the stable fallback, so this passes
    /// unchanged if the beta rail is RETIRED rather than resting — and it would
    /// also pass if the recipe's `url` were repointed at `?v=ccc7` or `?v=latest`,
    /// which resolve the same filename between cycles (the audit's table shows
    /// all three). Neither gap is fixable by a stronger assertion here: nothing
    /// in the response distinguishes those states — that is the cost the registry
    /// comment names — and the URL itself is pinned by
    /// `betaRecipeExistsAndUsesTheLatestbetaEndpoint`, not by this test.
    @Test func betaEndpointStillResolvesAVersionLive() async throws {
        let beta = try #require(self.betaRecipe())
        let outcome = await VendorProbeSource().probeDiagnostic(beta)
        let version = try #require(
            outcome.remote?.shortVersion,
            "?v=latestbeta resolved nothing — failure: \(String(describing: outcome.failure))")
        #expect(version.hasPrefix("7."), "resolved \(version), which is not a CCC 7 version")
    }
}
