import Testing
import Foundation
@testable import DuoUpdaterCore

struct WindscribeProbeRecipeTests {
    private static let bundleID = "com.windscribe.client"

    @Test func threeTracksUseTheMacFeedAndInteractiveInstallers() throws {
        let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
        #expect(recipes.count == 3)
        #expect(Set(recipes.map(\.channel)) == [.stable, .beta, .guineaPig])
        for recipe in recipes {
            #expect(recipe.url.absoluteString == "https://api.windscribe.com/ChangeLogs?platform=osx")
            #expect(recipe.requestHeaders["Authorization"] != nil)
            #expect(!recipe.versionIsBuild)
            #expect(recipe.selectHighest && recipe.entryStartPattern != nil)
            let installer = try #require(recipe.install)
            #expect(installer.kind == .dmg)
            #expect(installer.checksumFormat == .sha256Hex)
            #expect(installer.installerApp?.bundleIdentifier == "com.windscribe.installer.macos")
        }
    }

    // From the actual macOS feed. The fields used by the resolver are unmodified.
    private static let currentFeed = #"""
    {"data":[
        {"id": 1574, "platform": "osx", "beta": 2, "url": "https:\/\/deploy.totallyacdn.com\/desktop-apps\/2.26.2\/Windscribe_2.26.2_guinea_pig_universal.dmg", "min_version": "14.4", "sha256": "cf98624730cccee7e2bc02b6aecf04981095408f61199ab1aca5407edc0baec5", "release_date": "2026-11-13"},
        {"id": 1542, "platform": "osx", "beta": 0, "url": "https:\/\/deploy.totallyacdn.com\/desktop-apps\/2.25.8\/Windscribe_2.25.8_universal.dmg", "min_version": "14.4", "sha256": "3341e5a56a4bfc9c9ea07b9285b9733dee0982e6304516ec9d30aacbaed74bc5", "release_date": "2026-11-10"},
        {"id": 1529, "platform": "osx", "beta": 1, "url": "https:\/\/deploy.totallyacdn.com\/desktop-apps\/2.25.6\/Windscribe_2.25.6_beta_universal.dmg", "min_version": "14.4", "sha256": "aab8a8a13c416cc3323139f80b43388ca3dec609795a5f159180552a13e69a0d", "release_date": "2026-11-03"}]}
    """#

    @Test func resolvedVersionURLAndDigestBelongToTheSameTrackEntry() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.currentFeed)
        defer { server.stop() }
        for channel in [ReleaseChannel.stable, .beta, .guineaPig] {
            let recipe = try Self.recipe(channel)
            let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
            let remote = try #require(outcome.remote)
            let expectedVersion = channel == .guineaPig ? "2.26.2" : "2.25.8"
            let expectedFlavor = channel == .guineaPig ? "guinea_pig_" : ""
            #expect(remote.shortVersion == expectedVersion)
            #expect(remote.downloadURL?.absoluteString ==
                "https://deploy.totallyacdn.com/desktop-apps/\(expectedVersion)/Windscribe_\(expectedVersion)_\(expectedFlavor)universal.dmg")
            #expect(remote.expectedSHA256 == (channel == .guineaPig
                ? "cf98624730cccee7e2bc02b6aecf04981095408f61199ab1aca5407edc0baec5"
                : "3341e5a56a4bfc9c9ea07b9285b9733dee0982e6304516ec9d30aacbaed74bc5"))
            #expect(remote.requiresManualInstaller)
            #expect(remote.vendorInstallerApp != nil)
            #expect(RecipeSanity.crossChannelArtifact(recipe: recipe, remote: remote) == nil)
        }
    }

    @Test func theOfferOnlyHandsOffForTheSupportedDestination() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.currentFeed)
        defer { server.stop() }
        let recipe = try Self.recipe(.stable)
        let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
        let remote = try #require(outcome.remote)
        let environment = InstallEnvironment(isHelperEnabled: true, runningAppPaths: [],
            stagedSelfUpdates: [:], packageInstallerAvailable: true)
        let settings = UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite)
        for path in ["/Applications/Windscribe.app", "/Applications/Windscribe Copy.app"] {
            let app = InstalledApp(name: "Windscribe", bundleID: Self.bundleID,
                shortVersion: "2.24.12", buildVersion: "2.24.12", path: URL(fileURLWithPath: path),
                isMASApp: false, sparkleFeedURL: nil)
            let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "2.25.8"))
            #expect(!UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment))
            #expect(UpdatePolicy.requiresInstaller(result, environment: environment)
                == (path == "/Applications/Windscribe.app"))
        }
    }

    @Test func missingDigestKeepsTheUpdateAndWithholdsTheInstaller() async throws {
        let body = Self.currentFeed.replacingOccurrences(
            of: "3341e5a56a4bfc9c9ea07b9285b9733dee0982e6304516ec9d30aacbaed74bc5", with: "")
        let server = try RecipeVerificationTests.StubServer(body: body)
        defer { server.stop() }
        let recipe = try Self.recipe(.stable)
        let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "2.25.8")
        #expect(remote.vendorInstallerApp == nil)
        #expect(remote.vendorInstallerKind == nil)
    }

    @Test func stableRejectsWrongPlatformOrPreviewURL() throws {
        let stable = try Self.recipe(.stable)
        #expect(Self.resolve(stable, in: Self.currentFeed.replacingOccurrences(
            of: #""platform": "osx""#, with: #""platform": "windows""#)) == nil)
        #expect(Self.resolve(stable, in: Self.currentFeed.replacingOccurrences(
            of: "2.25.8_universal.dmg", with: "2.25.8_beta_universal.dmg")) == nil)
    }

    // MARK: - the changelog

    /// The notes come from GitHub, not from the vendor API the version comes
    /// from, and that split is deliberate: the vendor's own
    /// `/ChangeLogs?platform=osx` is richer but 403s without an `Authorization`
    /// header, and `ChangelogRecipe` has no field for one.
    ///
    /// `.gitHubReleases` keeps stable releases only. That is load-bearing here
    /// rather than incidental — Windscribe publishes its beta and guinea-pig
    /// builds as GitHub prereleases (measured 2026-09-07 across every release
    /// since 2024: release-track versions are `prerelease: false` and
    /// prerelease-track versions are not), so the format's filter is exactly the
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
        let recipe = try Self.recipe(.stable)
        #expect(recipe.changelogURL?.absoluteString == "https://windscribe.com/changelog")
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
        let stable = try Self.recipe(.stable)

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
            #expect(Self.resolve(stable, in: body) == expectedRelease,
                    "release as of \(asOf)")
        }
    }

    @Test func onlyThePublishedTracksHaveATrackSet() {
        #expect(VendorProbeRegistry.windscribeTrackSet(.stable) == "0")
        #expect(VendorProbeRegistry.windscribeTrackSet(.beta) == "[01]")
        #expect(VendorProbeRegistry.windscribeTrackSet(.guineaPig) == "[0-2]")
        for other: ReleaseChannel in [.rc, .canary, .nightly, .alpha, .dev] {
            #expect(VendorProbeRegistry.windscribeTrackSet(other) == nil)
        }
    }

    /// The three answers are NOT always the same, or the test above would pass
    /// for a recipe that ignored the track number.
    @Test func theFixtureActuallyDiscriminates() throws {
        let body = Self.feed(asOf: "2026-08-12")
        let answers = Set([
            Self.resolve(try Self.recipe(.stable), in: body),
            Self.resolve(try Self.recipe(.beta), in: body),
            Self.resolve(try Self.recipe(.guineaPig), in: body),
        ])
        #expect(answers.count > 1, "all three agree — this fixture proves nothing")
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
