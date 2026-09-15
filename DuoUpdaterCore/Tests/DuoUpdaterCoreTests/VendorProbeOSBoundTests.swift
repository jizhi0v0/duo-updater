import Testing
import Foundation
@testable import DuoUpdaterCore

/// A vendor endpoint that states, per release, the macOS window the build is
/// for — and a `VendorProbeRecipe` that reads it instead of pinning it.
///
/// Issue #634: the ceiling was honoured on the Sparkle path only, while the feed
/// that motivated it (obdev's `littlesnitch6.plist`) is read by
/// `VendorProbeSource`, which consulted neither bound. A macOS 27 Mac was told
/// the 26.99-capped stable build was its latest. The fixture is the real
/// 2026-08-29 body, kept because the live feed has since raised both caps to
/// 27.99 and no longer shows the gap.
///
/// Mutations, each run once against the final tree (2026-09-15; every one
/// compiles):
///  - `OSWindowRefusal.evaluate`'s ceiling compare (was `VendorProbeRecipe.osWindowRefusal`) `== .orderedAscending` → `== .orderedSame`
///    → `theCeilingIsSparklesPredicate`, `theRefusalNamesTheBoundAndTheHost`,
///    `aCappedStableIsNotOfferedToAMacAboveTheCap`, `eachEntryReadsItsOwnCeiling` red;
///  - the same on the floor compare → `theFloorIsSparklesPredicate` red (run when
///    the floor was its own compare; it now calls `SignatureVerifier.canRun`, and
///    that mutation has not been re-run against it);
///  - remove `maximumSystemVersionPattern` from the stable Little Snitch recipe
///    → `aCappedStableIsNotOfferedToAMacAboveTheCap` and
///    `everyRecipeOnASharedEndpointReadsTheSameBounds` red;
///  - stop appending `.osBoundPatternNoMatch` → `aPatternThatMatchesNothingWarnsAndAdmits`
///    and `aRefusalKeepsTheWarningsCollectedBeforeIt` red;
///  - `fail(...)` at the refusal without `warnings:` → `aRefusalKeepsTheWarningsCollectedBeforeIt` red;
///  - drop the ceiling's digit guard in `OSWindowRefusal.evaluate` → `aTextBoundIsTreatedAsAbsent` red;
///  - remove `minimumSystemVersionPattern` from BOTH Little Snitch recipes →
///    `everyRecipeOnASharedEndpointReadsTheSameBounds` red (the anti-vacuity floor);
///  - read the bounds from `body.text` instead of `scope` → `eachEntryReadsItsOwnCeiling`
///    red (the nightly entry is listed first and says 27.99; a whole-body
///    first-match would hand the stable recipe the nightly's cap).
@Suite struct VendorProbeOSBoundTests {

    // MARK: - The predicate, off any machine

    /// Sparkle's `-isMaximumOperatingSystemVersionOK:` is `!= NSOrderedAscending`
    /// on max-vs-host: the cap is inclusive, a Mac exactly at it still gets the
    /// build, and the first OS past it does not.
    @Test func theCeilingIsSparklesPredicate() {
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: "26.99", osVersion: "27.0.0", version: "7212") != nil)
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: "26.99", osVersion: "26.99.0", version: "7212") == nil)
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: "26.99", osVersion: "26.6.0", version: "7212") == nil)
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: "27.99", osVersion: "27.0.0", version: "7212") == nil)
        // Empty and absent bounds never refuse — an endpoint that leaves the key
        // blank has said nothing.
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: "", osVersion: "99.0.0", version: "7212") == nil)
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: nil, osVersion: "99.0.0", version: "7212") == nil)
    }

    @Test func theFloorIsSparklesPredicate() {
        #expect(OSWindowRefusal.evaluate(minimum: "14.0", maximum: nil, osVersion: "13.7.1", version: "7212") != nil)
        #expect(OSWindowRefusal.evaluate(minimum: "14.0", maximum: nil, osVersion: "14.0.0", version: "7212") == nil)
        #expect(OSWindowRefusal.evaluate(minimum: "", maximum: nil, osVersion: "10.0.0", version: "7212") == nil)
    }

    /// The refusal names both the bound and the host — as data for the row
    /// (`UpdateStatus.outsideOSWindow`) and in the log line behind it.
    @Test func theRefusalNamesTheBoundAndTheHost() throws {
        let reason = try #require(
            OSWindowRefusal.evaluate(minimum: nil, maximum: "26.99", osVersion: "27.0.0", version: "7212"))
        #expect(reason.logDescription.contains("26.99"))
        #expect(reason.logDescription.contains("27.0.0"))
        #expect(reason.bound == .ceiling(maximum: "26.99"))
        #expect(reason.hostOS == "27.0.0")
    }

    // MARK: - The real feed, through the real recipes

    private static func littleSnitchRecipes() throws -> (stable: VendorProbeRecipe, nightly: VendorProbeRecipe) {
        let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == "at.obdev.littlesnitch" }
        return (
            try #require(recipes.first { $0.channel == .stable }),
            try #require(recipes.first { $0.channel == .nightly }))
    }

    /// The gap itself: `final` is capped at 26.99, so a macOS 27 Mac gets no
    /// version from the stable recipe — and gets it as `.notApplicable`, not as
    /// a red row, because there is nothing to retry until obdev moves the cap.
    /// The nightly entry (27.99) still answers the same Mac.
    @Test func aCappedStableIsNotOfferedToAMacAboveTheCap() async throws {
        let (stable, nightly) = try Self.littleSnitchRecipes()
        let server = try RecipeVerificationTests.StubServer(
            body: LittleSnitchFeedFixture.body20260829, contentType: "application/xml")
        defer { server.stop() }
        let source = VendorProbeSource(hostOSVersion: "27.0.0")

        let stableOutcome = await source.probeDiagnostic(stable.with(url: server.url))
        #expect(stableOutcome.remote == nil)
        #expect(stableOutcome.failure?.classification == .notApplicable)
        #expect(stableOutcome.failure?.kind == "outsideVendorOSWindow")

        let nightlyOutcome = await source.probeDiagnostic(nightly.with(url: server.url))
        #expect(nightlyOutcome.remote?.version == "7301")
        #expect(nightlyOutcome.warnings.isEmpty)
    }

    /// The refusal reaches the row (#634 part 3): `latestVersion(for:)` throws it
    /// rather than answering nil, because nil is "this source does not cover the
    /// app" and landed Little Snitch on the "no source" dash on a macOS 27 Mac.
    /// The refusal names the release it refused in the row's spelling, the bound
    /// and the host the verdict was made on.
    ///
    /// Mutation: `return nil` in place of `throw OSWindowRefused(refusal)` in
    /// `latestVersion(for:)` → red.
    @Test func latestVersionThrowsTheRefusalRatherThanNil() async throws {
        let (stable, _) = try Self.littleSnitchRecipes()
        let server = try RecipeVerificationTests.StubServer(
            body: LittleSnitchFeedFixture.body20260829, contentType: "application/xml")
        defer { server.stop() }
        let source = VendorProbeSource(recipes: [stable.with(url: server.url)], hostOSVersion: "27.0.0")
        let app = InstalledApp(
            name: "ZZFixture Snitch", bundleID: stable.bundleID,
            shortVersion: "6.4", buildVersion: "7100",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Snitch.app"),
            isMASApp: false, sparkleFeedURL: nil)
        #expect(!FileManager.default.fileExists(atPath: app.path.path))

        do {
            let remote = try await source.latestVersion(for: app)
            Issue.record("expected OSWindowRefused, got \(String(describing: remote))")
        } catch let refused as OSWindowRefused {
            #expect(refused.refusal.bound == .ceiling(maximum: "26.99"))
            #expect(refused.refusal.hostOS == "27.0.0")
            #expect(refused.refusal.version == "6.4.1")
        }
    }

    /// The adversarial review's case, on the real fixture and the real recipe:
    /// a Mac moved to macOS 27 with the capped `final` build (6.4.1 / 7212)
    /// already installed. The vendor's refusal is about the build this copy HAS,
    /// so the row must not say DuoUpdater "won't offer it" — it stays the dash it
    /// was. One build older (7100), the same refusal is news and the row says so.
    ///
    /// Mutation: drop the `evaluate` guard in `UpdateChecker`'s `OSWindowRefused`
    /// catch → the 7212 copy comes back `.outsideOSWindow` → red.
    @Test func aCopyAlreadyOnTheCappedBuildIsNotToldItIsMissingIt() async throws {
        let (stable, _) = try Self.littleSnitchRecipes()
        let server = try RecipeVerificationTests.StubServer(
            body: LittleSnitchFeedFixture.body20260829, contentType: "application/xml")
        defer { server.stop() }
        let checker = UpdateChecker(sources: [
            VendorProbeSource(recipes: [stable.with(url: server.url)], hostOSVersion: "27.0.0"),
        ])
        func copy(_ short: String, _ build: String) -> InstalledApp {
            let app = InstalledApp(
                name: "ZZFixture Snitch", bundleID: stable.bundleID,
                shortVersion: short, buildVersion: build,
                path: URL(fileURLWithPath: "/Applications/ZZFixture-Snitch-\(build).app"),
                isMASApp: false, sparkleFeedURL: nil)
            #expect(!FileManager.default.fileExists(atPath: app.path.path))
            return app
        }

        #expect(await checker.check(copy("6.4.1", "7212")).status == .unknown)

        guard case .outsideOSWindow(let refusal) = await checker.check(copy("6.4", "7100")).status else {
            Issue.record("an older copy should be told the vendor refused 6.4.1 for this macOS")
            return
        }
        #expect(refusal.bound == .ceiling(maximum: "26.99"))
    }

    /// A Mac inside the window is answered exactly as before the bounds were
    /// read — same version, no warning. This is the "every existing recipe's
    /// behaviour is identical" half of the change.
    @Test func aMacInsideTheWindowIsAnsweredAsBefore() async throws {
        let (stable, _) = try Self.littleSnitchRecipes()
        let server = try RecipeVerificationTests.StubServer(
            body: LittleSnitchFeedFixture.body20260829, contentType: "application/xml")
        defer { server.stop() }

        let outcome = await VendorProbeSource(hostOSVersion: "26.6.0")
            .probeDiagnostic(stable.with(url: server.url))
        #expect(outcome.remote?.version == "7212")
        #expect(outcome.warnings.isEmpty)
    }

    /// The bounds are read from the winning ENTRY, never from the whole body.
    /// The fixture lists `nightly` (27.99) first: a whole-body first-match would
    /// hand the stable recipe the nightly's cap and admit the 26.99 build on
    /// macOS 27. The stable recipe's own pattern is anchored on `final`, so
    /// this is measured with a deliberately un-anchored pattern on the same
    /// entry slicing — the shape a future recipe would most naturally write.
    @Test func eachEntryReadsItsOwnCeiling() async throws {
        let (stable, _) = try Self.littleSnitchRecipes()
        let unanchored = VendorProbeRecipe(
            bundleID: stable.bundleID, url: stable.url, mode: .responseBody,
            versionPattern: stable.versionPattern,
            versionIsBuild: true,
            maximumSystemVersionPattern: #"<key>MaximumSystemVersion</key>\s*<string>([^<]+)</string>"#,
            entryStartPattern: stable.entryStartPattern)
        let server = try RecipeVerificationTests.StubServer(
            body: LittleSnitchFeedFixture.body20260829, contentType: "application/xml")
        defer { server.stop() }

        let outcome = await VendorProbeSource(hostOSVersion: "27.0.0")
            .probeDiagnostic(unanchored.with(url: server.url))
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.classification == .notApplicable)
    }

    /// A declared pattern that finds nothing fails OPEN — the version still
    /// resolves — but says so, because the sweep is the only thing that will
    /// ever notice the ceiling stopped being read.
    @Test func aPatternThatMatchesNothingWarnsAndAdmits() async throws {
        let (stable, _) = try Self.littleSnitchRecipes()
        let renamedKey = VendorProbeRecipe(
            bundleID: stable.bundleID, url: stable.url, mode: .responseBody,
            versionPattern: stable.versionPattern,
            versionIsBuild: true,
            maximumSystemVersionPattern: #"<key>MaxOSVersion</key>\s*<string>([^<]+)</string>"#,
            entryStartPattern: stable.entryStartPattern)
        let server = try RecipeVerificationTests.StubServer(
            body: LittleSnitchFeedFixture.body20260829, contentType: "application/xml")
        defer { server.stop() }

        let outcome = await VendorProbeSource(hostOSVersion: "27.0.0")
            .probeDiagnostic(renamedKey.with(url: server.url))
        #expect(outcome.remote?.version == "7212")
        #expect(outcome.warnings.contains(.osBoundPatternNoMatch))
    }

    /// A refusal keeps the warnings collected on the way to it. The floor key is
    /// renamed (pattern misses, warns) while the ceiling still reads 26.99 and
    /// refuses a 27.0.0 host: the outcome must carry BOTH the refusal and the
    /// warning, or the sweep sees `skipped` with nothing to say why the read
    /// might be wrong.
    @Test func aRefusalKeepsTheWarningsCollectedBeforeIt() async throws {
        let (stable, _) = try Self.littleSnitchRecipes()
        let renamedFloor = VendorProbeRecipe(
            bundleID: stable.bundleID, url: stable.url, mode: .responseBody,
            versionPattern: stable.versionPattern,
            versionIsBuild: true,
            minimumSystemVersionPattern: #"<key>MinOSVersion</key>\s*<string>([^<]+)</string>"#,
            maximumSystemVersionPattern: stable.maximumSystemVersionPattern,
            entryStartPattern: stable.entryStartPattern)
        let server = try RecipeVerificationTests.StubServer(
            body: LittleSnitchFeedFixture.body20260829, contentType: "application/xml")
        defer { server.stop() }

        let outcome = await VendorProbeSource(hostOSVersion: "27.0.0")
            .probeDiagnostic(renamedFloor.with(url: server.url))
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.kind == "outsideVendorOSWindow")
        #expect(outcome.warnings.contains(.osBoundPatternNoMatch))
    }

    /// A bound with no digit in it is a bound the vendor did not state, not a
    /// ceiling below every Mac. `VersionComparator` ranks text below numbers, so
    /// without the guard `any` refuses everyone.
    @Test func aTextBoundIsTreatedAsAbsent() {
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: "any", osVersion: "27.0.0", version: "7212") == nil)
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: "-", osVersion: "27.0.0", version: "7212") == nil)
        #expect(OSWindowRefusal.evaluate(minimum: "latest", maximum: nil, osVersion: "10.0.0", version: "7212") == nil)
        // A digit somewhere still counts as a version, however odd the spelling.
        #expect(OSWindowRefusal.evaluate(minimum: nil, maximum: "26.99", osVersion: "27.0.0", version: "7212") != nil)
    }

    // MARK: - Derived from the registry

    /// Every OS-bound pattern in the registry compiles. Same guard every other
    /// pattern field has; a pattern that does not compile is a silent nil.
    @Test func everyOSBoundPatternInTheRegistryIsAValidRegex() {
        for recipe in VendorProbeRegistry.recipes {
            for (label, pattern) in [
                ("minimumSystemVersionPattern", recipe.minimumSystemVersionPattern),
                ("maximumSystemVersionPattern", recipe.maximumSystemVersionPattern),
            ] {
                guard let pattern else { continue }
                #expect(
                    (try? NSRegularExpression(pattern: pattern)) != nil,
                    "\(recipe.recipeID): \(label) does not compile")
            }
        }
    }

    /// Two recipes reading the SAME document read the same bounds, or neither
    /// does. The document either states an OS window per entry or it does not;
    /// a recipe that declares a ceiling pattern proves the endpoint has one, and
    /// a sibling on that endpoint without the pattern is the nightly-recipe
    /// omission this guard exists for. Derived from the registry, so the next
    /// vendor whose feed has this shape is covered the day its second recipe is
    /// written — not when someone remembers this suite.
    @Test func everyRecipeOnASharedEndpointReadsTheSameBounds() {
        let byURL = Dictionary(grouping: VendorProbeRegistry.recipes, by: \.url)
        let shared = byURL.filter { $0.value.count > 1 }
        for (url, recipes) in shared {
            // One (floor, ceiling) flag pair per recipe; a shared document has one.
            let declared = Set(recipes.map {
                [$0.minimumSystemVersionPattern != nil, $0.maximumSystemVersionPattern != nil]
            })
            #expect(declared.count == 1, """
                recipes on \(url.absoluteString) disagree on whether the document states \
                an OS window: \(recipes.map { "\($0.recipeID) min=\($0.minimumSystemVersionPattern != nil) max=\($0.maximumSystemVersionPattern != nil)" })
                """)
        }
        // Anti-vacuity: Little Snitch's two recipes share one URL and declare
        // BOTH bounds. If that stops being true the guard above is checking
        // nothing, and this line says so instead of staying green.
        let declaringBoth = shared.values.contains { recipes in
            recipes.allSatisfy {
                $0.minimumSystemVersionPattern != nil && $0.maximumSystemVersionPattern != nil
            }
        }
        #expect(declaringBoth, "no shared endpoint declares both OS bounds; the guard above is vacuous")
    }
}
