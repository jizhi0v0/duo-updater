import Foundation
import Testing
@testable import DuoUpdaterCore

/// CotEditor's two trains, read through GitHub instead of through its appcast.
///
/// The appcast keeps ONE prerelease slot, so a copy on any beta but the newest
/// cannot find itself in the feed, falls back to the default channel, and is
/// offered the stable line — which outranks it by build and trails it by three
/// marketing versions (#368). GitHub keeps every release and the tag names the
/// train, so the channel needs no lookup that history can invalidate.
///
/// Every case is driven off the registry rather than a hand-written list, and
/// each loop asserts how many rows it saw: a `for … where` over a registry is
/// green when the entry it protects has been deleted.
struct CotEditorChannelTests {
    private static let bundleID = "com.coteditor.CotEditor"

    private static var rules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
    }

    /// Real tags from the 100 newest releases (2026-09-06), including the shape
    /// that is easy to miss: the cycle's first prerelease is `7.1.0-beta`, with
    /// no number after `beta`.
    private static let tags = [
        "7.1.0-beta.6", "7.0.9", "7.1.0-beta.5", "7.1.0-beta.4", "7.1.0-beta.3",
        "7.0.8", "7.1.0-beta.2", "7.1.0-beta", "7.0.7", "7.0.6", "6.2.3", "4.1.5",
    ]

    /// Both halves of what makes the beta rule a beta rule, asserted against the
    /// registry rather than restated. Deleting either rule fails here.
    @Test func bothRulesAreRegisteredAndSplitTheTrains() throws {
        #expect(Self.rules.count == 2)
        let stable = try #require(Self.rules.first { $0.channel == .stable })
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        #expect(stable.usePrereleases == false)
        #expect(beta.usePrereleases)
        for rule in Self.rules {
            #expect(rule.owner == "coteditor" && rule.repo == "CotEditor")
            #expect(rule.installerKind == .dmg)
        }
    }

    /// What the two patterns must do is NOT symmetric, and getting that backwards
    /// is what shipped for a day.
    ///
    /// The stable pattern must refuse every prerelease — a stable copy offered a
    /// beta is the harm this repo cares most about. The beta pattern must accept
    /// BOTH, because this vendor's train runs in cycles and a copy on
    /// `7.1.0-beta.6` has to be able to take the `7.1.0` that graduates from it.
    ///
    /// Patterns are read off the registry, so a rule edited in either direction
    /// fails here rather than in production.
    @Test func theStablePatternRefusesPrereleasesAndTheBetaOneDoesNot() throws {
        let stable = try #require(Self.rules.first { $0.channel == .stable })
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        var counts = (stable: 0, beta: 0)
        for tag in Self.tags {
            let s = VendorProbeRecipe.extractVersion(from: tag, pattern: stable.versionPattern)
            let b = VendorProbeRecipe.extractVersion(from: tag, pattern: beta.versionPattern)
            if tag.contains("-beta") {
                #expect(s == nil, "the stable pattern accepted a prerelease: \(tag)")
            } else {
                #expect(s == tag)
            }
            #expect(b == tag, "the beta pattern must accept every tag, including \(tag)")
            if s != nil { counts.stable += 1 } else { counts.beta += 1 }
        }
        #expect(counts == (stable: 6, beta: 6))
    }

    /// The unnumbered `7.1.0-beta` is a real release (the cycle's first, 2026-07-26)
    /// and it is the one shape a `-beta\.[0-9]+` pattern copied from Yaak would
    /// silently drop. Kept as its own case so the reason survives.
    @Test func theCyclesFirstPrereleaseHasNoNumberAndStillMatches() throws {
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        #expect(VendorProbeRecipe.extractVersion(
            from: "7.1.0-beta", pattern: beta.versionPattern) == "7.1.0-beta")
    }

    /// The asset patterns follow the version patterns, and are asymmetric for the
    /// same reason: the stable rule must never install a prerelease build, while
    /// the beta rule must be able to install the release that graduates from its
    /// train. One asset per release, always `CotEditor_<tag>.dmg` (measured over
    /// the newest 100).
    @Test func theStableAssetPatternRefusesABetaDMGAndTheBetaOneTakesBoth() throws {
        let stable = try #require(Self.rules.first { $0.channel == .stable }.flatMap(\.installAssetPattern))
        let beta = try #require(Self.rules.first { $0.channel == .beta }.flatMap(\.installAssetPattern))
        func matches(_ pattern: String, _ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(matches(stable, "CotEditor_7.0.9.dmg"))
        #expect(!matches(stable, "CotEditor_7.1.0-beta.6.dmg"))
        #expect(!matches(stable, "CotEditor_7.1.0-beta.dmg"))

        #expect(matches(beta, "CotEditor_7.1.0-beta.6.dmg"))
        #expect(matches(beta, "CotEditor_7.1.0-beta.dmg"))
        #expect(matches(beta, "CotEditor_7.1.0.dmg"),
                "the beta rule has to be able to install the release its train graduates into")
    }

    /// ⚠️ The proof CANNOT be an `.artifact` one here, and that is a consequence
    /// of the rule above rather than a preference: the beta rule legitimately
    /// resolves a stable artifact the day a cycle graduates, and a pattern
    /// anchored to `-beta` in the download path would fire on exactly that.
    ///
    /// It was an artifact proof for a day. It passed the whole time — it would
    /// have gone on passing right up to the release it was wrong about — which is
    /// why this case asserts the KIND, not just that some proof exists.
    @Test func theChannelProofIsAnchoredToTheRecipeNotToTheArtifact() throws {
        let proof = try #require(
            ChannelProofRegistry.githubProofs[ChannelProofKey(Self.bundleID, .beta)])
        guard case .recipeAnchor(let pattern, let fields) = proof else {
            Issue.record("expected a recipeAnchor proof, got \(proof)"); return
        }
        #expect(fields.contains("usePrereleases") && fields.contains("versionPattern"))
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        #expect(beta.versionPattern.range(of: pattern, options: .regularExpression) != nil,
                "the anchor no longer matches the field it anchors to")
    }

    /// Every non-stable GitHub rule carrying an install spec needs a proof, and
    /// this app now has one — asserted through the registry's own predicate so it
    /// cannot drift from the rule.
    @Test func theBetaRuleIsInTheProofPopulation() {
        #expect(ChannelProofRegistry.channelGitHubRulesWithInstall
            .contains(ChannelProofKey(Self.bundleID, .beta)))
    }

    /// The vendor's rule, in the vendor's words:
    /// `Bundle.main.version.isPrerelease || checksUpdatesForBeta`. Four states,
    /// and the binding is only responsible for the half a version string cannot
    /// answer.
    ///
    /// The row that matters is the third: an unticked box must resolve to **nil**,
    /// not to `.stable`. A `.stable` answer is authoritative and would silence
    /// `detect()`, pinning a `7.1.0-beta.3` copy — whose owner never opened that
    /// settings pane — to the stable line. That is #368 arriving through the
    /// binding instead of through the feed.
    @Test func theBindingCoversOnlyTheHalfTheVersionStringCannot() {
        func detect(_ version: String) -> ReleaseChannel {
            ReleaseChannel.detect(name: "CotEditor", bundleID: Self.bundleID,
                keystoneChannel: nil, version: version)
        }
        func effective(installed: String, box: Bool) -> ReleaseChannel {
            CotEditorChannel.resolve(checksUpdatesForBeta: box)?.channel ?? detect(installed)
        }
        #expect(effective(installed: "7.1.0-beta.6", box: true) == .beta)
        #expect(effective(installed: "7.1.0-beta.3", box: false) == .beta)
        #expect(effective(installed: "7.0.9", box: true) == .beta)
        #expect(effective(installed: "7.0.9", box: false) == .stable)
        // Stated separately: the false case produces NO resolution at all, which
        // is what leaves `detect()` in charge above.
        #expect(CotEditorChannel.resolve(checksUpdatesForBeta: false) == nil)
        #expect(CotEditorChannel.resolve(checksUpdatesForBeta: true)?.feedOverride == nil)
        #expect(CotEditorChannel.resolve(checksUpdatesForBeta: true)?.sparkleChannelNames.isEmpty == true)
    }

    /// The binding is registered in the one switch and in the watcher's roots.
    /// Sandboxed apps keep preferences inside their container, and CapCut — the
    /// only other sandboxed binding — happens to keep its flag OUTSIDE one, so
    /// neither existing root covers this app.
    @Test func theBindingIsRegisteredAndItsContainerIsWatched() {
        #expect(ChannelBinding.hasResolver(bundleID: Self.bundleID))
        #expect(ChannelBinding.boundBundleIDs.contains(Self.bundleID.lowercased()))
        #expect(ChannelBinding.preferenceWatchCandidates.contains {
            $0.path == CotEditorChannel.preferencesDirectoryURL.path
        })
        #expect(CotEditorChannel.preferencesDirectoryURL.path.contains("Library/Containers"))
    }

    /// One changelog rail per channel, and the beta one must include the release
    /// its train graduates into.
    ///
    /// `includesPromotedStable` is asserted as a LITERAL rather than read off the
    /// rule: reading it would make this case agree with whatever the registry
    /// says. It is true here and false on Yaak's beta recipe, and the difference
    /// is the rules — Yaak's beta rule cannot resolve a stable artifact, while
    /// this one can and must, so a prerelease-only history would omit the very
    /// entry the row is offering.
    @Test func bothChangelogRailsAreRegisteredAndTheBetaOneKeepsTheGraduation() throws {
        let recipes = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
        #expect(recipes.count == 2, "one rail per channel; a deleted recipe must not read as coverage")
        var seen: Set<ReleaseChannel> = []
        for recipe in recipes {
            seen.insert(recipe.channel ?? .stable)
            #expect(recipe.source.path == "/repos/coteditor/CotEditor/releases")
            #expect(recipe.structuredFormat == .gitHubReleases)
            #expect(recipe.includesPromotedStable == (recipe.channel == .beta))
        }
        #expect(seen == [.stable, .beta])
    }

    /// The case the `-beta`-only pattern got wrong, driven through the source with
    /// the graduation that has not happened yet: `7.1.0` published as stable above
    /// the `7.1.0-beta.6` a copy is running.
    ///
    /// A beta copy must be offered it. Under the shipped-for-a-day pattern the
    /// beta rule could not see a plain tag at all, so this copy sat on a
    /// superseded prerelease until the next cycle opened — while CotEditor's own
    /// updater handed it that release, because Sparkle allows the default channel
    /// to everyone. Nothing else in this file notices: every other case is about
    /// tags that exist today, and today the newest tag IS a beta.
    @Test func aBetaCopyIsOfferedTheReleaseItsTrainGraduatesInto() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GraduationProtocol.self]
        let source = GitHubReleasesSource(session: URLSession(configuration: config))

        func app(_ short: String, _ build: String) -> InstalledApp {
            InstalledApp(
                name: "CotEditor", bundleID: Self.bundleID,
                shortVersion: short, buildVersion: build,
                path: URL(fileURLWithPath: "/Applications/CotEditor.app"),
                isMASApp: false, sparkleFeedURL: nil,
                releaseChannel: ReleaseChannel.detect(
                    name: "CotEditor", bundleID: Self.bundleID,
                    keystoneChannel: nil, version: short))
        }

        let onBeta = try #require(try await source.latestVersion(for: app("7.1.0-beta.6", "845")))
        #expect(onBeta.shortVersion == "7.1.0")
        #expect(onBeta.downloadURL?.lastPathComponent == "CotEditor_7.1.0.dmg")
        #expect(UpdateChecker.evaluate(installed: app("7.1.0-beta.6", "845"), remote: onBeta)
            == .updateAvailable(latest: "7.1.0"))

        // And the version comparison behind it, stated rather than assumed: a
        // release outranks its own prerelease tag.
        #expect(VersionComparator.isNewer("7.1.0", than: "7.1.0-beta.6"))
    }

    /// The mirror, on the same fixture: a STABLE copy is not handed the
    /// prerelease sitting in the same page. The stable rule reads
    /// `/releases/latest`, which GitHub never answers with a prerelease, and its
    /// own pattern refuses one anyway.
    @Test func aStableCopyIsNotHandedThePrereleaseInTheSamePage() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GraduationProtocol.self]
        let source = GitHubReleasesSource(session: URLSession(configuration: config))
        let stable = InstalledApp(
            name: "CotEditor", bundleID: Self.bundleID,
            shortVersion: "7.0.9", buildVersion: "843",
            path: URL(fileURLWithPath: "/Applications/CotEditor.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
        let remote = try #require(try await source.latestVersion(for: stable))
        #expect(remote.shortVersion == "7.1.0")
        #expect(remote.downloadURL?.lastPathComponent == "CotEditor_7.1.0.dmg")
    }

    /// A releases page with the graduation in it: `7.1.0` stable above the
    /// `7.1.0-beta.6` it graduates from. Shaped like the real API's fields, with
    /// one `CotEditor_<tag>.dmg` per release the way this vendor publishes.
    private final class GraduationProtocol: URLProtocol, @unchecked Sendable {
        static let releases = """
        [
          {"tag_name":"7.1.0","prerelease":false,"draft":false,"published_at":"2026-09-20T01:00:00Z",
           "html_url":"https://github.com/coteditor/CotEditor/releases/tag/7.1.0","body":"### Improvements\\n- Graduated.",
           "assets":[{"name":"CotEditor_7.1.0.dmg","browser_download_url":"https://github.com/coteditor/CotEditor/releases/download/7.1.0/CotEditor_7.1.0.dmg","size":26500000}]},
          {"tag_name":"7.1.0-beta.6","prerelease":true,"draft":false,"published_at":"2026-09-05T01:33:07Z",
           "html_url":"https://github.com/coteditor/CotEditor/releases/tag/7.1.0-beta.6","body":"### Improvements\\n- Beta six.",
           "assets":[{"name":"CotEditor_7.1.0-beta.6.dmg","browser_download_url":"https://github.com/coteditor/CotEditor/releases/download/7.1.0-beta.6/CotEditor_7.1.0-beta.6.dmg","size":26458624}]},
          {"tag_name":"7.0.9","prerelease":false,"draft":false,"published_at":"2026-09-05T01:32:59Z",
           "html_url":"https://github.com/coteditor/CotEditor/releases/tag/7.0.9","body":"### Improvements\\n- Nine.",
           "assets":[{"name":"CotEditor_7.0.9.dmg","browser_download_url":"https://github.com/coteditor/CotEditor/releases/download/7.0.9/CotEditor_7.0.9.dmg","size":25609728}]}
        ]
        """

        /// `/releases/latest` — GitHub's newest non-prerelease, spelled out rather
        /// than derived from the list above, so the stub cannot quietly answer
        /// something malformed and have a test pass for the wrong reason.
        static let latest = """
        {"tag_name":"7.1.0","prerelease":false,"draft":false,"published_at":"2026-09-20T01:00:00Z",
         "html_url":"https://github.com/coteditor/CotEditor/releases/tag/7.1.0","body":"### Improvements\\n- Graduated.",
         "assets":[{"name":"CotEditor_7.1.0.dmg","browser_download_url":"https://github.com/coteditor/CotEditor/releases/download/7.1.0/CotEditor_7.1.0.dmg","size":26500000}]}
        """

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let path = request.url?.path ?? ""
            // `/releases/latest` is GitHub's newest NON-prerelease; the list
            // endpoint carries everything, newest first.
            let body = path.hasSuffix("/releases/latest") ? Self.latest : Self.releases
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    /// ⚠️ The appcast address stays OUT of `SparkleFeedCatalog` on purpose.
    /// `SourceStack` runs Sparkle before GitHub, so adding it takes this app
    /// straight back to the feed whose single prerelease slot is what #368 is
    /// about — and every test above still passes.
    ///
    /// Measured rather than asserted: putting the entry back and running a live
    /// check moved the source from GitHub to Sparkle for all five installed
    /// states, and this is the only case in the file that noticed.
    @Test func theAppcastIsDeliberatelyNotInTheCatalog() {
        #expect(SparkleFeedCatalog.feed(forBundleID: Self.bundleID) == nil)
        #expect(SparkleFeedCatalog.feed(forBundleID: Self.bundleID.lowercased()) == nil)
    }
}
