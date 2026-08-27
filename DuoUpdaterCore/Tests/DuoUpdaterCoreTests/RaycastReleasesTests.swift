import Testing
import Foundation
@testable import DuoUpdaterCore

/// The v2 endpoint's real response, captured 2026-08-27 from
/// `x.raycast-releases.com/releases/latest?platform=macos&architecture=arm64`
/// and trimmed to one build per platform and a two-line changelog. Key ORDER is
/// the real one — it is what makes "first match" the top-level field for
/// `version`, `created_at` and `download_url` rather than something inside
/// `builds`.
private let raycastV2Body = #"""
{"id":2275,"version":"2.0.6.0","title":"🎉Raycast 2.0 is out of Beta!","changelog":"Raycast 2.0 is out of Beta! 🎉\n\n## ✨ New\n\n- **AI**: Added a Clear Chat action\n","commit_sha":"c3450ccdc97a0804cf0985092b3b7e5ccb70be70","created_at":"2026-08-25T07:34:17.976Z","updated_at":"2026-08-25T08:16:54.354Z","builds":[{"id":5129,"platform":"macos","architecture":"arm64","url":"https://x-r2.raycast-releases.com/Raycast_2.0.6.0_c3450ccdc9_arm64.dmg","checksum":"f09c22aa30a45e17c346c2b1051cf4c3"},{"id":5128,"platform":"windows","architecture":"arm64","url":"https://x-r2.raycast-releases.com/Raycast.Package_2.0.6.0_c3450ccdc9_arm64.msix","checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],"download_url":"https://x-r2.raycast-releases.com/Raycast_2.0.6.0_c3450ccdc9_arm64.dmg","checksum":"f09c22aa30a45e17c346c2b1051cf4c3"}
"""#

/// `www.raycast.com/changelog` as served 2026-08-27, trimmed to two `<article>`s
/// with two bullets per section. The hashed CSS-module class names are kept
/// verbatim — the recipe must match on their readable suffix, not the hash.
private let raycastChangelogFixture = #"""
<h1>Changelog</h1><div class="PlatformSwitch-module__I1eiVa__platformSwitch"><a class="PlatformSwitch-module__I1eiVa__pill" href="/changelog/macos"><span class="PlatformSwitch-module__I1eiVa__label">macOS V1</span></a></div>
<article><span id="2.0"></span><div class="ChangelogEntry-module__p4g-ca__changelogMeta"><a class="Pill-module__gZwUCW__pill" href="/changelog/macos-beta/2-0">v<!-- -->2.0</a><span class="ChangelogEntry-module__p4g-ca__changelogDate">August 25, 2026</span></div><div class="markdown ChangelogEntry-module__p4g-ca__changelogBody"><p><img src="https://misc-assets.raycast.com/releases/901e5ffd.png" alt="image"/></p>
<p>Raycast 2.0 is out of Beta! 🎉</p>
<h2>✨ New</h2> <ul> <li><strong>AI</strong>: Added a Clear Chat action, which resets a chat&#x27;s messages</li> <li><strong>MCP</strong>: Added loopback OAuth redirects</li> </ul>
<h2>🐞 Fixes</h2> <ul> <li><strong>Notes</strong>: Fixed text being turned into links incorrectly</li> </ul></div></article><article><span id="0.71"></span><div class="ChangelogEntry-module__p4g-ca__changelogMeta"><a class="Pill-module__gZwUCW__pill" href="/changelog/macos-beta/0-71">v<!-- -->0.71</a><span class="ChangelogEntry-module__p4g-ca__changelogDate">August 19, 2026</span></div><div class="markdown ChangelogEntry-module__p4g-ca__changelogBody"><p><img src="https://misc-assets.raycast.com/releases/43fe39b8.png" alt="image"/></p>
<p>Screen Awareness brings context from your focused app into AI Chat.</p>
<h2>✨ New</h2> <ul> <li><strong>AI</strong>: Send Focused Window to AI command includes richer app and window context</li> </ul></div></article>
"""#

@Suite struct RaycastReleasesTests {

    private func recipes() -> [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { $0.bundleID == "com.raycast.macos" }
    }
    private func v2() throws -> VendorProbeRecipe {
        try #require(recipes().first { $0.variant == "v2" })
    }
    private func v1() throws -> VendorProbeRecipe {
        try #require(recipes().first { $0.variant == "v1" })
    }

    // MARK: registry shape

    /// Two endpoints, one channel, split by host — not by `channel`. The variant is
    /// what keeps the v1 recipe's `recipeID` (and so its verify baseline history)
    /// unchanged while a second one joins it.
    @Test func bothTrainsAreRegisteredOnStableWithDistinctIDs() throws {
        let all = recipes()
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.channel == .stable })
        // Both carry an explicit variant: `channelProofsCoverEveryChannelRecipe`
        // requires it of every recipe in a duplicated (bundleID, channel) group,
        // so a second endpoint can never arrive as an accidental copy-paste. The
        // v1 recipe's verify baseline entry was renamed alongside this, not
        // dropped — `vendor:com.raycast.macos:stable` → `…:stable:v1`.
        #expect(Set(all.map(\.recipeID)) == [
            "vendor:com.raycast.macos:stable:v1",
            "vendor:com.raycast.macos:stable:v2",
        ])
        // Endpoints sharing a channel must agree on `versionIsBuild` — a build
        // compared against a marketing string is the phantom-update bug that flag
        // exists to prevent, and `best(of:)` ranks the two answers against each
        // other directly.
        #expect(all.allSatisfy { !$0.versionIsBuild })
    }

    /// Only the v2 train is host-restricted; v1 must stay universal, because it is
    /// the ONLY recipe left answering on a Mac that fails v2's requirement.
    @Test func onlyTheV2TrainCarriesAHostRequirement() throws {
        #expect(try v1().hostRequirement == nil)
        let req = try #require(try v2().hostRequirement)
        #expect(req.minimumSystemVersion == "26.0")
        #expect(req.architectures == [.arm64])
    }

    /// The `version` query parameter is deliberately absent: with it the endpoint
    /// answers 204 No Content once the caller is current, which would make the
    /// probe fail exactly when it should report "up to date".
    @Test func v2EndpointAsksForLatestRatherThanForAnUpgrade() throws {
        let url = try v2().url.absoluteString
        #expect(url.hasPrefix("https://x.raycast-releases.com/releases/latest?"))
        #expect(url.contains("platform=macos"))
        #expect(!url.contains("version="))
    }

    // MARK: the host gate

    /// The truth table the split exists for. Parameterized on an explicit host so
    /// it means the same thing on whatever machine CI runs.
    @Test func hostGateAdmitsOnlyAppleSiliconOnTahoeOrLater() throws {
        let recipe = try v2()
        #expect(recipe.runs(onOS: "26.0.0", arch: .arm64))
        #expect(recipe.runs(onOS: "27.1.0", arch: .arm64))
        // Apple silicon but too old an OS — v2 would install and then not launch.
        #expect(!recipe.runs(onOS: "25.6.0", arch: .arm64))
        #expect(!recipe.runs(onOS: "14.7.1", arch: .arm64))
        // Intel, any OS: the macOS half of `builds` is arm64-only and no
        // translation has ever run that direction.
        #expect(!recipe.runs(onOS: "27.1.0", arch: .x86_64))
        #expect(!recipe.runs(onOS: "26.0.0", arch: .x86_64))
        // v1 is the fallback those machines land on, so it must admit all of them.
        let legacy = try v1()
        for (os, arch) in [("14.7.1", HostArch.x86_64), ("25.6.0", .arm64), ("27.1.0", .arm64)] {
            #expect(legacy.runs(onOS: os, arch: arch))
        }
    }

    /// A recipe with no requirement is unchanged by the gate — the property that
    /// keeps this field inert for the rest of the registry.
    ///
    /// The gated recipes are named rather than counted. A bare count told you a
    /// number had moved but not which recipe moved it, and gating a recipe is
    /// exactly the kind of change that must be deliberate: a `hostRequirement`
    /// DROPS its recipe on machines that fail it, so one added by accident takes
    /// an app to "unknown" on those Macs and says nothing anywhere.
    @Test func recipesWithoutARequirementRunEverywhere() {
        let restricted = VendorProbeRegistry.recipes.filter { $0.hostRequirement != nil }
        #expect(Set(restricted.map(\.recipeID)) == [
            // Raycast v2: arm64 + macOS 26, with v1 as the fallback train.
            "vendor:com.raycast.macos:stable:v2",
            // WorkBuddy: one recipe per architecture per site, so the install URL
            // can never be the other architecture's zip.
            "vendor:com.workbuddy.workbuddy-ai:stable:arm64",
            "vendor:com.workbuddy.workbuddy-ai:stable:x64",
            "vendor:com.workbuddy.workbuddy:stable:arm64",
            "vendor:com.workbuddy.workbuddy:stable:x64",
        ])
        let unrestricted = VendorProbeRegistry.recipes.filter { $0.hostRequirement == nil }
        #expect(unrestricted.count == VendorProbeRegistry.recipes.count - restricted.count)
        #expect(unrestricted.allSatisfy { $0.runs(onOS: "14.0.0", arch: .x86_64) })
    }

    // MARK: v2 response parsing

    @Test func v2PatternsReadTheTopLevelFieldsOfTheRealBody() throws {
        let recipe = try v2()
        #expect(VendorProbeRecipe.extractVersion(
            from: raycastV2Body, pattern: recipe.versionPattern) == "2.0.6.0")

        let publishedAt = try #require(recipe.publishedAtPattern)
        #expect(VendorProbeRecipe.extractVersion(
            from: raycastV2Body, pattern: publishedAt) == "2026-08-25T07:34:17.976Z")

        guard case let .bodyPattern(installPattern) =
            try #require(recipe.install).urlSource else {
            Issue.record("expected a bodyPattern install source"); return
        }
        // The `.dmg` anchor is load-bearing: `builds` also lists Windows `.msix`
        // URLs on the same host, and a looser pattern would resolve one of those.
        #expect(VendorProbeRecipe.extractVersion(
            from: raycastV2Body, pattern: installPattern)
            == "https://x-r2.raycast-releases.com/Raycast_2.0.6.0_c3450ccdc9_arm64.dmg")
        #expect(try #require(recipe.install).kind == .dmg)
    }

    /// v2's `version` is the marketing string the bundle reports verbatim — the
    /// check `versionIsBuild` exists for. Measured against the installed 2.0.6.0
    /// on 2026-08-27.
    @Test func v2VersionIsTheMarketingStringNotABuildNumber() throws {
        let v = try #require(VendorProbeRecipe.extractVersion(
            from: raycastV2Body, pattern: try v2().versionPattern))
        #expect(v == "2.0.6.0")
        #expect(v.split(separator: ".").count == 4)
    }

    /// The two trains' install patterns must not cross: v1's body spells the key
    /// `downloadURL`, v2's spells it `download_url`, and each pattern has to miss
    /// the other's body rather than quietly resolve something.
    @Test func theTwoTrainsInstallPatternsDoNotMatchEachOthersBodies() throws {
        func installPattern(_ r: VendorProbeRecipe) throws -> String {
            guard case let .bodyPattern(p) = try #require(r.install).urlSource else {
                Issue.record("\(r.recipeID): expected bodyPattern"); return ""
            }
            return p
        }
        let v1Body = #"{"version":"1.104.25","downloadURL":"https://worker.raycast-releases.com/?url=https%3A%2F%2Fx.dmg"}"#
        #expect(VendorProbeRecipe.extractVersion(
            from: v1Body, pattern: try installPattern(try v2())) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: raycastV2Body, pattern: try installPattern(try v1())) == nil)
    }

    // MARK: changelog

    private func changelogRecipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.raycast.macos", channel: .stable, version: "2.0.6.0"))
    }
    private func v1ChangelogRecipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.raycast.macos", channel: .stable, version: "1.104.25"))
    }

    /// The two trains' notes live on two pages that share a bundle id AND a
    /// channel, so only the version can pick between them.
    @Test func theVersionPicksTheTrainsChangelogPage() throws {
        #expect(try changelogRecipe().source.absoluteString
            == "https://www.raycast.com/changelog")
        #expect(try v1ChangelogRecipe().source.absoluteString
            == "https://www.raycast.com/changelog/macos")
        // The two trains' numbers are NOT two contiguous halves of a line: v1 runs
        // 1.95–1.104, while v2 ran 0.63–0.71 in beta before jumping to 2.0 at GA.
        // So the archive claims exactly [1, 2) and the v2 page takes everything
        // else — including the sub-1.0 beta builds, whose notes are on it.
        for v in ["2.0", "2.0.0.0", "2.1", "3.0", "0.71.7.0", "0.63.0.0"] {
            #expect(ChangelogRecipeRegistry.recipe(
                forBundleID: "com.raycast.macos", version: v)?.source.absoluteString
                == "https://www.raycast.com/changelog", "\(v) should read the v2 page")
        }
        for v in ["1.104.25", "1.104.0", "1.99.0", "1.0"] {
            #expect(ChangelogRecipeRegistry.recipe(
                forBundleID: "com.raycast.macos", version: v)?.source.absoluteString
                == "https://www.raycast.com/changelog/macos", "\(v) should read the archive")
        }
    }

    /// The windowed archive must beat the catch-all v2 page for a 1.x install even
    /// though the catch-all also "covers" it — most specific wins. Without that
    /// rule the pair could only be expressed as two contiguous ranges, which is the
    /// shape Raycast's version numbers do not have.
    @Test func aWindowedRecipeOutranksTheCatchAll() throws {
        let group = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == "com.raycast.macos" }
        #expect(group.count == 2)
        let catchAll = try #require(group.first { !$0.declaresVersionWindow })
        #expect(catchAll.source.absoluteString == "https://www.raycast.com/changelog")
        #expect(catchAll.covers(appVersion: "1.104.25"))   // it does not exclude 1.x…
        #expect(ChangelogRecipeRegistry.scoped(group, toVersion: "1.104.25")
            .map(\.source.absoluteString) == ["https://www.raycast.com/changelog/macos"])
    }

    /// With no version in hand the lookup must still answer, and answer with the
    /// CURRENT train. That falls out of preferring the window-LESS recipe rather
    /// than out of declaration order: the archive is the carved-out exception.
    @Test func aVersionlessLookupFallsBackToTheCurrentTrain() {
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.raycast.macos")?.source.absoluteString
            == "https://www.raycast.com/changelog")
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.raycast.macos", version: "")?.source.absoluteString
            == "https://www.raycast.com/changelog")
    }

    /// The version window must be inert for every recipe that declares none —
    /// scoping runs in front of ~100 recipes that have never had one, and a nil
    /// version must not start excluding recipes that were always eligible.
    @Test func versionScopingIsANoOpForRecipesWithoutAWindow() {
        let windowed = ChangelogRecipeRegistry.recipes.filter(\.declaresVersionWindow)
        #expect(windowed.allSatisfy { $0.bundleID == "com.raycast.macos" })
        #expect(windowed.count == 1)

        for recipe in ChangelogRecipeRegistry.recipes where !recipe.declaresVersionWindow {
            // Every bundle id whose group has no window resolves to the same recipe
            // with a version, without one, and with a nonsense one.
            let group = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == recipe.bundleID }
            guard !group.contains(where: \.declaresVersionWindow) else { continue }
            let bare = ChangelogRecipeRegistry.recipe(forBundleID: recipe.bundleID)
            for version in ["1.0", "999.999", ""] {
                #expect(ChangelogRecipeRegistry.recipe(
                    forBundleID: recipe.bundleID, version: version)?.source == bare?.source,
                    "\(recipe.bundleID) changed answer for version \(version)")
            }
        }
    }

    /// A version outside every declared window keeps the whole group in play rather
    /// than answering nil — possibly-wrong notes beat none, since the pane can only
    /// fall back to embedding the page.
    @Test func anUncoveredVersionStillGetsARecipe() throws {
        // The archive alone, asked about a 2.x install, covers nothing — and must
        // hand the recipe back anyway rather than an empty group. Possibly-wrong
        // notes beat none; the pane can only fall back to embedding the page.
        let archiveOnly = [try v1ChangelogRecipe()]
        #expect(!archiveOnly[0].covers(appVersion: "2.0.6.0"))
        let scoped = ChangelogRecipeRegistry.scoped(archiveOnly, toVersion: "2.0.6.0")
        #expect(scoped.map(\.source) == archiveOnly.map(\.source))
    }

    @Test func changelogReadsOneEntryPerArticle() throws {
        let log = try #require(ChangelogExtractor.extract(
            from: raycastChangelogFixture, using: try changelogRecipe()))
        #expect(log.entries.map(\.version) == ["2.0", "0.71"])
        #expect(log.entries.map(\.date) == ["August 25, 2026", "August 19, 2026"])
    }

    /// Section titles are kept as items. They are the only structure 30 flat
    /// bullets have, and an itemPattern matching bullets alone would drop them
    /// silently — itemPatterns are fallbacks, not a union.
    @Test func changelogKeepsSectionHeadingsAlongsideBullets() throws {
        let log = try #require(ChangelogExtractor.extract(
            from: raycastChangelogFixture, using: try changelogRecipe()))
        let first = try #require(log.entries.first)
        #expect(first.items == [
            "✨ New",
            "AI: Added a Clear Chat action, which resets a chat's messages",
            "MCP: Added loopback OAuth redirects",
            "🐞 Fixes",
            "Notes: Fixed text being turned into links incorrectly",
        ])
    }

    /// The page's platform switcher is a `<a>`/`<span>` pair OUTSIDE any article,
    /// and the per-version pill links live inside `changelogMeta`, before the body
    /// starts — neither may leak in as a change line.
    @Test func changelogExcludesNavigationChrome() throws {
        let log = try #require(ChangelogExtractor.extract(
            from: raycastChangelogFixture, using: try changelogRecipe()))
        let items = log.entries.flatMap(\.items)
        #expect(!items.contains { $0.contains("macOS V1") })
        #expect(!items.contains { $0.contains("2.0") && $0.count < 6 })
    }

    /// One hero image per entry, taken from the body only — the `<img>` in the
    /// platform switcher above the first article must not be picked up.
    @Test func changelogKeepsTheHeroImage() throws {
        let log = try #require(ChangelogExtractor.extract(
            from: raycastChangelogFixture, using: try changelogRecipe()))
        let images = try #require(log.entries.first).content.compactMap { block -> URL? in
            if case let .image(url) = block { return url }
            return nil
        }
        #expect(images == [URL(string: "https://misc-assets.raycast.com/releases/901e5ffd.png")!])
    }
}
