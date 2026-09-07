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

    /// The stable recipe. There are three now — one per track — so this names the
    /// one it wants instead of assuming the registry holds a single entry, which
    /// is what it used to assume.
    private static func theRecipe() throws -> VendorProbeRecipe {
        try #require(recipes.first { $0.channel == .stable })
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
        // One recipe per track, and no duplicates within a track — the channel
        // gate picks exactly one, and two would make `best(of:)` arbitrate
        // between endpoints that are supposed to answer for different people.
        #expect(Set(Self.recipes.map(\.channel)) == [.stable, .beta, .guineaPig])
        #expect(Self.recipes.count == 3)
        #expect(Self.recipes.allSatisfy { $0.install == nil },
                "every track stays detection-only")
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
        let recipe = try #require(ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == Self.bundleID && $0.channel == .stable
        })
        #expect(recipe.structuredFormat == .gitHubReleases)
        #expect(recipe.source.host() == "api.github.com")
        #expect(recipe.source.path == "/repos/Windscribe/Desktop-App/releases")
        // Not promoted-stable — that field is what lets a NON-stable track show
        // the release that graduated into it, and a stable reader has no other
        // line to be shown. `everyTrackHasItsOwnChangelogRecipe` covers the two
        // that do set it.
        #expect(!recipe.includesPromotedStable)
    }

    /// One changelog recipe per track, so `recipe(forBundleID:channel:)` finds an
    /// exact match instead of falling back to the stable one.
    ///
    /// Mutation: delete the two prerelease entries — the fallback then hands a
    /// beta copy the stable-only list, which is what this replaced.
    @Test func everyTrackHasItsOwnChangelogRecipe() throws {
        let all = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
        #expect(Set(all.compactMap(\.channel)) == [.stable, .beta, .guineaPig])
        #expect(all.count == 3)
        #expect(all.allSatisfy { $0.structuredFormat == .gitHubReleases })
        // All three read the same page of the same feed: `per_page` decides how
        // far back each can see, and three different values would give three
        // readers three different histories of one app.
        #expect(Set(all.map(\.source)).count == 1)
        // The ladder, in the field that already expressed it: a non-stable track
        // must be able to show the release that graduated, because that is what
        // its own row offers whenever release leads.
        for recipe in all where recipe.channel != .stable {
            #expect(recipe.includesPromotedStable,
                    "\(recipe.channel?.rawValue ?? "?") would omit the release it is offered")
        }
        #expect(all.first { $0.channel == .stable }?.includesPromotedStable == false)
    }

    /// The behaviour the field names, run through the real decoder on real
    /// release bodies: a beta reader gets the prerelease AND the graduated
    /// release; a stable reader gets only the release.
    ///
    /// Mutation: drop `includesPromotedStable` — 2.24.12 leaves the beta list,
    /// and a beta copy offered 2.24.12 (which is what happens whenever release
    /// leads, the state on the day this was written) sees a pane without it.
    @Test func aPrereleaseReaderSeesBothLines() throws {
        let stable = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            Self.gitHubReleasesBody, channel: .stable, maxEntries: 20))
        #expect(stable.entries.map(\.version) == ["2.24.12"])

        for channel in [ReleaseChannel.beta, .guineaPig] {
            let notes = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
                Self.gitHubReleasesBody, channel: channel, maxEntries: 20,
                includesPromotedStable: true))
            let versions = notes.entries.map(\.version)
            #expect(versions.contains("2.24.12"), "\(channel.rawValue) lost the graduated release")
            #expect(versions.contains("2.24.10"), "\(channel.rawValue) lost the prerelease")
            #expect(notes.entries.allSatisfy { !$0.items.isEmpty },
                    "an entry parsed to no items is a pane row with nothing in it")
        }
    }

    /// The cost of using GitHub for this, asserted rather than left in prose:
    /// GitHub marks every prerelease the same way, so a beta reader also sees
    /// guinea pig builds and builds the vendor's own feed never listed.
    ///
    /// Pinned so that fixing it properly — the vendor feed, which states each
    /// entry's track — has a test that changes rather than a comment nobody
    /// re-reads.
    @Test func theGitHubFeedCannotTellTheTwoPrereleaseTracksApart() throws {
        let notes = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            Self.gitHubReleasesBody, channel: .beta, maxEntries: 20,
            includesPromotedStable: true))
        let versions = notes.entries.map(\.version)
        // 2.24.6 is guinea pig by the vendor's own `beta` number, and 2.24.11 is
        // on no vendor track at all — both are `prerelease: true` on GitHub.
        #expect(versions.contains("2.24.6"), "if this stops being true the split got finer")
        #expect(versions.contains("2.24.11"))
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

    // MARK: - the two prerelease tracks

    /// The tracks are a LADDER: a user on level N is served the newest build
    /// from tracks 0…N. So the beta recipe must read release entries too, and the
    /// guinea pig recipe must read all three — reading only its own track would
    /// tell someone on 2.24.10 that the beta track's 2.24.10 is the newest thing
    /// there is, and would offer a guinea pig user a version older than the one
    /// they are running.
    ///
    /// These feeds are the real entries from `/ChangeLogs?platform=osx`, replayed
    /// by release date. That replay is the whole point: TODAY all three tracks
    /// answer 2.24.12, because release leads — so a fixture built from today's
    /// feed cannot tell a correct implementation from one that ignores the track
    /// number entirely. These dates can.
    private static func recipe(_ channel: ReleaseChannel) throws -> VendorProbeRecipe {
        try #require(
            VendorProbeRegistry.recipes.first {
                $0.bundleID == bundleID && $0.channel == channel
            },
            "no \(channel.rawValue) recipe registered")
    }

    /// Resolve a body the way `VendorProbeSource` does for these recipes:
    /// `entryStartPattern` slices, `selectHighest` picks the winner.
    private static func resolve(_ recipe: VendorProbeRecipe, in body: String) -> String? {
        guard let start = recipe.entryStartPattern,
              let entry = VendorProbeRecipe.highestVersionEntry(
                in: body, entryStartPattern: start,
                versionPattern: recipe.versionPattern, selectHighest: recipe.selectHighest)
        else { return nil }
        return VendorProbeRecipe.highestVersion(from: entry, pattern: recipe.versionPattern)
    }

    /// Mutation: give the beta recipe `"beta"\s*:\s*1` (its own track only) —
    /// 2026-09-07 still passes, and every earlier date goes red.
    @Test func eachTrackReadsItsOwnAndEverythingMoreStable() throws {
        let stable = try Self.recipe(.stable)   // reads the summary, not this feed
        #expect(stable.entryStartPattern == nil)

        let beta = try Self.recipe(.beta)
        let guinea = try Self.recipe(.guineaPig)
        let cases: [(String, String, String, String)] = [
            // as of        release-track   beta        guinea pig
            ("2026-07-25", "2.23.11", "2.23.11", "2.24.3"),
            ("2026-08-01", "2.23.11", "2.23.11", "2.24.6"),
            ("2026-08-12", "2.23.11", "2.24.8",  "2.24.8"),
            ("2026-08-26", "2.23.11", "2.24.10", "2.24.10"),
            ("2026-09-07", "2.24.12", "2.24.12", "2.24.12"),
        ]
        for (asOf, expectedRelease, expectedBeta, expectedGuinea) in cases {
            let body = Self.feed(asOf: asOf)
            #expect(Self.resolve(beta, in: body) == expectedBeta, "beta as of \(asOf)")
            #expect(Self.resolve(guinea, in: body) == expectedGuinea, "guinea pig as of \(asOf)")
            // The release track, read with the same machinery, as the control the
            // other two are supposed to differ from.
            #expect(Self.resolve(Self.releaseTrackControl, in: body) == expectedRelease,
                    "release as of \(asOf)")
        }
    }

    /// The track set is a switch that refuses what it has not been taught, not a
    /// ternary with a catch-all. The catch-all shipped first and mapped every
    /// non-beta channel — `.stable` included — to the guinea-pig set, which would
    /// have offered a guinea pig build to every stable user the moment somebody
    /// put stable on this endpoint too.
    ///
    /// Mutation: `channel == .beta ? "[01]" : "[0-2]"`, which turns the `.stable`
    /// and `.rc` expectations below red while the two real tracks still pass.
    @Test func onlyTheTwoLadderTracksHaveATrackSet() {
        #expect(VendorProbeRegistry.windscribeTrackSet(.beta) == "[01]")
        #expect(VendorProbeRegistry.windscribeTrackSet(.guineaPig) == "[0-2]")
        for other: ReleaseChannel in [.stable, .rc, .canary, .nightly, .alpha, .dev] {
            #expect(VendorProbeRegistry.windscribeTrackSet(other) == nil,
                    "\(other.rawValue) must not silently inherit another track's set")
        }
    }

    /// The three answers are NOT always the same, or the test above would pass
    /// for a recipe that ignored the track number.
    @Test func theFixtureActuallyDiscriminates() throws {
        let body = Self.feed(asOf: "2026-08-12")
        let answers = Set([
            Self.resolve(Self.releaseTrackControl, in: body),
            Self.resolve(try Self.recipe(.beta), in: body),
            Self.resolve(try Self.recipe(.guineaPig), in: body),
        ])
        #expect(answers.count > 1, "all three agree — this fixture proves nothing")
    }

    /// Both prerelease recipes stay detection-only and keep the header, and both
    /// scope the date to the same entry the version came from.
    ///
    /// Mutation: drop `entryStartPattern`, which lets `publishedAtPattern`
    /// first-match a different release's date.
    @Test func thePrereleaseRecipesAreShapedLikeTheStableOne() throws {
        for channel in [ReleaseChannel.beta, .guineaPig] {
            let recipe = try Self.recipe(channel)
            #expect(recipe.install == nil, "\(channel.rawValue) must stay detection-only")
            #expect(recipe.requestHeaders["Authorization"] != nil)
            #expect(recipe.selectHighest)
            #expect(recipe.entryStartPattern != nil)
            #expect(recipe.publishedAtPattern != nil)
            #expect(recipe.url.absoluteString
                == "https://api.windscribe.com/ChangeLogs?platform=osx")
        }
    }

    /// The date comes out of the winning entry, not the first one in the body.
    @Test func theDateBelongsToTheVersionThatWon() throws {
        let recipe = try Self.recipe(.beta)
        let body = Self.feed(asOf: "2026-08-12")
        let start = try #require(recipe.entryStartPattern)
        let datePattern = try #require(recipe.publishedAtPattern)
        let entry = try #require(VendorProbeRecipe.highestVersionEntry(
            in: body, entryStartPattern: start,
            versionPattern: recipe.versionPattern, selectHighest: true))
        #expect(VendorProbeRecipe.highestVersion(
            from: entry, pattern: recipe.versionPattern) == "2.24.8")
        #expect(VendorProbeRecipe.extractVersion(from: entry, pattern: datePattern)
            == "2026-08-10")
    }

    /// A stand-in for "the release track read through the same machinery", so the
    /// ladder table above has a control column. Not registered — the shipped
    /// stable recipe reads the smaller summary endpoint instead.
    private static let releaseTrackControl = VendorProbeRecipe(
        bundleID: bundleID,
        url: URL(string: "https://api.windscribe.com/ChangeLogs?platform=osx")!,
        mode: .responseBody,
        versionPattern: #""beta"\s*:\s*0(?![0-9])[\s\S]*?Windscribe_([0-9]+(?:\.[0-9]+)+)_"#,
        selectHighest: true,
        entryStartPattern: #""id"\s*:\s*[0-9]+"#)

    /// The real feed, replayed: every entry published on or before `asOf`.
    private static func feed(asOf: String) -> String {
        let entries = Self.realEntries.filter { $0.date <= asOf }
            .map { entry in
                """
                        {
                            "id": \(entry.id),
                            "platform": "osx",
                            "version": "\(entry.version)",
                            "build": \(entry.build),
                            "beta": \(entry.track),
                            "url": "https://deploy.totallyacdn.com/desktop-apps/\(entry.full)/Windscribe_\(entry.file).dmg",
                            "release_date": "\(entry.date)"
                        }
                """
            }
        return "{\n    \"data\": [\n" + entries.joined(separator: ",\n") + "\n    ]\n}"
    }

    /// Copied from `/ChangeLogs?platform=osx`, 2026-09-07 — ids, tracks, artifact
    /// names and dates verbatim.
    private static let realEntries: [(id: Int, version: String, build: Int, track: Int,
                                      full: String, file: String, date: String)] = [
        (1468, "2.24", 12, 0, "2.24.12", "2.24.12_universal", "2026-09-02"),
        (1452, "2.24", 10, 1, "2.24.10", "2.24.10_beta_universal", "2026-08-25"),
        (1436, "2.24", 8, 1, "2.24.8", "2.24.8_beta_universal", "2026-08-10"),
        (1421, "2.24", 6, 2, "2.24.6", "2.24.6_guinea_pig_universal", "2026-07-30"),
        (1406, "2.24", 3, 2, "2.24.3", "2.24.3_guinea_pig_universal", "2026-07-21"),
        (1385, "2.23", 11, 0, "2.23.11", "2.23.11_universal", "2026-07-06"),
    ]

    /// `api.github.com/repos/Windscribe/Desktop-App/releases`, 2026-09-07 — the
    /// five newest entries, with each `body` cut to its first section. Tags,
    /// `prerelease` flags and dates are verbatim; the prose is shortened because
    /// the real bodies run 3.4–11.5 KB each and none of it changes the parse.
    private static let gitHubReleasesBody = """
        [
          { "tag_name": "v2.24.12", "prerelease": false, "draft": false,
            "published_at": "2026-09-02T17:44:06Z",
            "body": "### Added\\n* Custom SNI support for stunnel/wstunnel anti-censorship connections.\\n* A SECURITY.md document." },
          { "tag_name": "v2.24.11", "prerelease": true, "draft": false,
            "published_at": "2026-08-26T17:24:04Z",
            "body": "### Improved\\n* Belarusian translations in the GUI, installer and CLI." },
          { "tag_name": "v2.24.10", "prerelease": true, "draft": false,
            "published_at": "2026-08-19T16:43:15Z",
            "body": "### Improved\\n* Retry, backoff, and failover handling in wsnet." },
          { "tag_name": "v2.24.9", "prerelease": true, "draft": false,
            "published_at": "2026-08-14T17:32:23Z",
            "body": "### Improved\\n* API retry access to use bounded per-resource exponential back-off." },
          { "tag_name": "v2.24.6", "prerelease": true, "draft": false,
            "published_at": "2026-07-29T18:24:47Z",
            "body": "### Added\\n* A SECURITY.md document." }
        ]
        """
}
