import Testing
import Foundation
@testable import DuoUpdaterCore

/// Windscribe's `/ChangeLogs/summary` probe.
///
/// The recipe is looked up from the registry rather than restated here, and every
/// expectation runs against excerpts copied VERBATIM out of the 14,280-byte body
/// the endpoint returned on 2026-09-07, cut at map-key boundaries. The real
/// document holds 28 platform entries of exactly this shape; these are the ones
/// the patterns have to tell apart.
struct WindscribeProbeRecipeTests {

    private static let bundleID = "com.windscribe.client"

    /// The macOS entry with the platform on either side of it — verbatim and
    /// contiguous, so the neighbours really are the ones a straddling pattern
    /// would run into.
    ///
    /// Note what makes this excerpt the dangerous one: all three ship in
    /// lockstep at 2.24.12, so reading the WRONG platform's field produces the
    /// RIGHT number. That is the shape a bug hides in.
    private static let summaryExcerpt = #"""
        "linux_zst_x64_cli": [
                        {
                            "integration": "ws",
                            "type": "desktop",
                            "platform": "linux_zst_x64_cli",
                            "release_version": "2.24",
                            "release_build": 12,
                            "release_date": "2026-09-02",
                            "release_full_version": "2.24.12",
                            "beta_full_version": "2.24.10",
                            "guinea_pig_full_version": "2.24.6"
                        }
                    ],
                    "osx": [
                        {
                            "integration": "ws",
                            "type": "desktop",
                            "platform": "osx",
                            "release_version": "2.24",
                            "release_build": 12,
                            "release_date": "2026-09-02",
                            "release_full_version": "2.24.12",
                            "beta_full_version": "2.24.10",
                            "guinea_pig_full_version": "2.24.6"
                        }
                    ],
                    "windows": [
                        {
                            "integration": "ws",
                            "type": "desktop",
                            "platform": "windows",
                            "release_version": "2.24",
                            "release_build": 12,
                            "release_date": "2026-09-02",
                            "release_full_version": "2.24.12",
                            "beta_full_version": "2.24.10",
                            "guinea_pig_full_version": "2.24.6"
                        }
                    ],
        """#

    /// A non-desktop entry from the same document, where the version is nothing
    /// like the Mac's — proof that the `"platform": "osx"` anchor is load-bearing
    /// rather than decorative.
    private static let iosExcerpt = #"""
        "ios": [
                        {
                            "integration": "ws",
                            "type": "mobile",
                            "platform": "ios",
                            "release_version": "3.9.13",
                            "release_build": 1,
                            "release_date": "2026-02-19",
                            "release_full_version": "3.9.13.1",
                            "beta_full_version": "",
                            "guinea_pig_full_version": ""
                        }
                    ]
                },
                "tv": {
        """#

    /// `CFBundleShortVersionString` of the bundle inside
    /// `Windscribe_2.24.12_universal.dmg`, read after extracting the installer's
    /// `Contents/Resources/windscribe.tar.lzma` (2026-09-07, no install performed).
    private static let installedShortVersion = "2.24.12"

    /// `CFBundleVersion` of that same bundle. Windscribe's plist template writes
    /// one value into both keys, so these are equal by construction — which is
    /// why `versionIsBuild` must stay off: there is no build namespace to route
    /// into.
    private static let installedBuildVersion = "2.24.12"

    private static let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == bundleID }

    private static func theRecipe() throws -> VendorProbeRecipe {
        #expect(recipes.count == 1, "Windscribe should have exactly one recipe")
        return try #require(recipes.first)
    }

    // MARK: - registry shape

    /// One stable, detection-only recipe. The three tracks Windscribe publishes
    /// share a bundle id, a display name and a version shape (proven by
    /// extracting both the 2.24.12 stable and 2.24.10 beta bundles), so a channel
    /// recipe here could never bind to an install — and one-click is refused for
    /// reasons in the registry comment, not for lack of a URL.
    ///
    /// Mutation: give the recipe an `install:` spec, or a non-stable `channel:`.
    @Test func windscribeIsASingleStableDetectionOnlyRecipe() throws {
        let recipe = try Self.theRecipe()
        #expect(recipe.channel == .stable)
        #expect(recipe.variant == nil)
        #expect(recipe.install == nil, "one-click is refused; see the registry comment")
        #expect(recipe.identities.isEmpty && recipe.track == nil)
        // The vendor's per-release `min_version` moves (10.8 → 13.0 across the
        // 149 macOS entries), so it must not be frozen into a static requirement.
        #expect(recipe.hostRequirement == nil)
        // Selection is by key name, not by document position — nothing here may
        // start picking "the highest number in a 28-platform document".
        #expect(!recipe.selectHighest)
        #expect(recipe.entryStartPattern == nil)
        if case .responseBody = recipe.mode {} else {
            Issue.record("\(recipe.recipeID) is not a body-parsing recipe")
        }
    }

    /// The endpoint — and the header that makes it answer at all. Without the
    /// `Authorization` header the API returns 403 "Missing client authentication
    /// values"; the value is not validated (measured 2026-09-07: `Bearer 9999`
    /// returns the same body), so this pins presence, not a secret.
    ///
    /// Mutation: drop `requestHeaders`; point `url` back at `/CheckUpdate`.
    @Test func theProbeCarriesTheHeaderTheEndpointDemands() throws {
        let recipe = try Self.theRecipe()
        #expect(recipe.url.absoluteString
            == "https://api.windscribe.com/ChangeLogs/summary")
        #expect(recipe.requestHeaders["Authorization"] != nil,
                "the endpoint 403s without an Authorization header")
    }

    // MARK: - the version

    /// The release track's own field, whole.
    ///
    /// Mutation: any change to `versionPattern` that stops it matching.
    @Test func theVersionIsTheReleaseTracksOwnField() throws {
        let recipe = try Self.theRecipe()
        let version = try #require(
            VendorProbeRecipe.extractVersion(
                from: Self.summaryExcerpt, pattern: recipe.versionPattern))
        #expect(version == Self.installedShortVersion)
        #expect(VersionComparator.compare(version, Self.installedShortVersion)
            == .orderedSame,
            "an up-to-date Windscribe would be shown a phantom update")
    }

    /// The two prerelease tracks are the next two lines of the same object.
    ///
    /// What actually keeps them out TODAY is document order — the lazy run stops
    /// at the first `…_full_version` it reaches, and `release_full_version` is
    /// listed first — so a pattern relaxed to `[a-z_]*full_version` reads the same
    /// 2.24.12 and looks fine. The exact key is insurance against the vendor
    /// reordering the object, which is the only way this could go wrong and the
    /// only shape in which the two patterns disagree. So the reorder is what this
    /// test performs, on the real excerpt.
    ///
    /// Mutation: `"[a-z_]*full_version"` in place of `"release_full_version"`.
    @Test func theAdjacentPrereleaseFieldsAreNotWhatIsRead() throws {
        let recipe = try Self.theRecipe()
        #expect(Self.summaryExcerpt.contains(#""beta_full_version": "2.24.10""#))
        #expect(Self.summaryExcerpt.contains(#""guinea_pig_full_version": "2.24.6""#))

        let relaxed = #""platform"\s*:\s*"osx""#
            + #"(?:(?!"platform")[\s\S])*?"#
            + #""[a-z_]*full_version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#

        // As shipped, both read the release track — order alone is enough.
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.summaryExcerpt, pattern: recipe.versionPattern) == "2.24.12")
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.summaryExcerpt, pattern: relaxed) == "2.24.12")

        // Reordered so beta comes first: now they disagree, and the exact key is
        // the one that still names the release track.
        let reordered = Self.summaryExcerpt.replacingOccurrences(
            of: "\"release_full_version\": \"2.24.12\",\n                    \"beta_full_version\": \"2.24.10\",",
            with: "\"beta_full_version\": \"2.24.10\",\n                    \"release_full_version\": \"2.24.12\",")
        #expect(reordered != Self.summaryExcerpt, "the reorder must have landed")
        #expect(VendorProbeRecipe.extractVersion(
            from: reordered, pattern: recipe.versionPattern) == "2.24.12")
        #expect(VendorProbeRecipe.extractVersion(
            from: reordered, pattern: relaxed) == "2.24.10",
            "if the relaxed pattern no longer reads the beta, this proves nothing")
    }

    /// `release_version` is a DIFFERENT key holding two of the three segments
    /// (`2.24`); the third is in `release_build`. Reading it would compare `2.24`
    /// against the installed `2.24.12` as a permanent downgrade and hide every
    /// future update.
    ///
    /// Mutation: drop `_full` from the key in `versionPattern`.
    @Test func theTwoSegmentFieldWouldReadAsADowngrade() throws {
        let short = #""platform"\s*:\s*"osx""#
            + #"(?:(?!"platform")[\s\S])*?"#
            + #""release_version"\s*:\s*"([0-9.]+)""#
        let truncated = try #require(
            VendorProbeRecipe.extractVersion(from: Self.summaryExcerpt, pattern: short))
        #expect(truncated == "2.24")
        #expect(VersionComparator.compare(truncated, Self.installedShortVersion)
            == .orderedAscending)
        let recipe = try Self.theRecipe()
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.summaryExcerpt, pattern: recipe.versionPattern) != truncated)
    }

    /// Marketing, not build — and here the two are the same string, so nothing
    /// downstream may assume they differ.
    ///
    /// Mutation: set `versionIsBuild: true`.
    @Test func theVersionIsMarketingNotBuild() throws {
        let recipe = try Self.theRecipe()
        #expect(!recipe.versionIsBuild)
        #expect(recipe.displayVersionPattern == nil)
        #expect(Self.installedShortVersion == Self.installedBuildVersion)
    }

    // MARK: - the platform anchor and its boundary

    /// The anchor is load-bearing: pointed at a document region that has no macOS
    /// entry, the pattern must find nothing rather than the nearest number.
    ///
    /// Mutation: drop `"platform"\s*:\s*"osx"` from the front of `versionPattern`
    /// — it then reads iOS's 3.9.13.1.
    @Test func aNonMacEntryYieldsNothing() throws {
        let recipe = try Self.theRecipe()
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.iosExcerpt, pattern: recipe.versionPattern) == nil)
        #expect(Self.iosExcerpt.contains(#""release_full_version": "3.9.13.1""#),
                "the excerpt must carry a readable version, or this proves nothing")
    }

    /// The `(?:(?!"platform")…)` boundary stops the lazy run from crossing into
    /// the next platform's copy of the key. Measured on this excerpt with the
    /// macOS entry's `release_full_version` deleted: bounded finds nothing,
    /// unbounded returns Windows' `2.24.12` — the right answer, from the wrong
    /// platform, which is why this could ship unnoticed.
    ///
    /// Mutation: replace the boundary with a plain `[\s\S]*?`.
    @Test func thePatternCannotStraddleIntoTheNextPlatform() throws {
        let recipe = try Self.theRecipe()
        let osxStart = try #require(Self.summaryExcerpt.range(of: #""platform": "osx""#))
        let windowsStart = try #require(Self.summaryExcerpt.range(of: #""platform": "windows""#))
        let mutated = Self.summaryExcerpt.replacingOccurrences(
            of: #"                    "release_full_version": "2.24.12",\#n"#,
            with: "",
            range: osxStart.lowerBound..<windowsStart.lowerBound)
        #expect(mutated != Self.summaryExcerpt, "the deletion must have landed")

        #expect(VendorProbeRecipe.extractVersion(
            from: mutated, pattern: recipe.versionPattern) == nil,
            "the bounded pattern must refuse to answer for a platform that said nothing")

        let unbounded = #""platform"\s*:\s*"osx"[\s\S]*?"#
            + #""release_full_version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#
        #expect(VendorProbeRecipe.extractVersion(from: mutated, pattern: unbounded)
            == "2.24.12",
            "if this stops straddling, the boundary is no longer being tested")
    }

    // MARK: - the changelog

    /// The notes come from GitHub, not from the vendor API the version comes
    /// from, and that split is deliberate: the vendor's own
    /// `/ChangeLogs?platform=osx` is richer but 403s without an `Authorization`
    /// header, and `ChangelogRecipe` has no field for one.
    ///
    /// `.gitHubReleases` keeps stable releases only. That is load-bearing here
    /// rather than incidental — Windscribe publishes its beta and guinea-pig
    /// builds as GitHub prereleases (measured across every release since 2024:
    /// all 19 release-track versions are `prerelease: false`, and none of the 51
    /// prerelease-track versions are), so the format's filter is exactly the
    /// track split, and a copy would otherwise be shown notes for a track it
    /// never opted into.
    ///
    /// Mutation: `channel: .beta`; or drop `structuredFormat`, which leaves the
    /// recipe trying to regex a JSON array with no entry pattern.
    @Test func theChangelogIsGitHubsStableReleasesOnly() throws {
        let recipes = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
        #expect(recipes.count == 1, "Windscribe should have exactly one changelog recipe")
        let recipe = try #require(recipes.first)
        #expect(recipe.structuredFormat == .gitHubReleases)
        #expect(recipe.channel == .stable)
        #expect(recipe.source.host() == "api.github.com")
        #expect(recipe.source.path == "/repos/Windscribe/Desktop-App/releases")
        // Not promoted-stable: that field is for a beta train whose builds
        // graduate, which is not the shape of a stable-only recipe.
        #expect(!recipe.includesPromotedStable)
    }

    /// The probe keeps its own `changelogURL` as the web fallback, pointing at the
    /// vendor's page rather than at GitHub — the two are different surfaces and
    /// the fallback should show the vendor's own.
    ///
    /// Mutation: point `changelogURL` at the GitHub releases page.
    @Test func theWebFallbackIsStillTheVendorsOwnPage() throws {
        let recipe = try Self.theRecipe()
        #expect(recipe.changelogURL?.absoluteString == "https://windscribe.com/changelog")
    }

    // MARK: - the date

    /// The publish date, from the macOS entry and carrying the same anchor and
    /// boundary as the version — otherwise a first-match would stamp the Mac's
    /// version with whichever platform sits first in the document.
    ///
    /// Mutation: drop `publishedAtPattern`; or drop its `"osx"` anchor, which
    /// makes it read the first platform in the body instead.
    @Test func theDateComesFromTheMacEntryAndIsReadable() throws {
        let recipe = try Self.theRecipe()
        let pattern = try #require(recipe.publishedAtPattern)
        let raw = try #require(
            VendorProbeRecipe.extractVersion(from: Self.summaryExcerpt, pattern: pattern))
        #expect(raw == "2026-09-02")
        // A bare calendar day, which `ReleaseDate` must resolve to a vendor day —
        // a pattern that matched but produced nothing readable warns as
        // `.publishedAtUnreadable` and silently disables verify's age gate.
        let fields = ReleaseDate.publishedFields(from: raw)
        #expect(fields.publishedAt != nil || fields.vendorDay != nil)
        #expect(VendorProbeRecipe.extractVersion(from: Self.iosExcerpt, pattern: pattern) == nil)
    }
}
