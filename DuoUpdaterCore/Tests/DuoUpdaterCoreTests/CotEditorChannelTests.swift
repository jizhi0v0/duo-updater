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

    /// The two version patterns must PARTITION the tag space: every real tag
    /// matched by exactly one of them. A pattern that accepted both trains would
    /// hand a beta copy the stable release and call it an update — the same
    /// outcome #368 produced through the appcast, by a different route.
    ///
    /// Patterns are read off the registry, so a rule edited to overlap fails here
    /// rather than in production.
    @Test func theTwoVersionPatternsPartitionEveryRealTag() throws {
        let stable = try #require(Self.rules.first { $0.channel == .stable })
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        var counts = (stable: 0, beta: 0)
        for tag in Self.tags {
            let s = VendorProbeRecipe.extractVersion(from: tag, pattern: stable.versionPattern)
            let b = VendorProbeRecipe.extractVersion(from: tag, pattern: beta.versionPattern)
            #expect((s == nil) != (b == nil), "\(tag) matched \(s == nil ? "neither" : "both") rules")
            if s != nil { counts.stable += 1 } else { counts.beta += 1 }
            // The capture is the version, not the tag with decoration around it.
            #expect((s ?? b) == tag)
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

    /// Each rule's asset pattern selects only its own train's DMG. One asset per
    /// release, always `CotEditor_<tag>.dmg` (measured over the newest 100).
    @Test func eachRuleSelectsOnlyItsOwnTrainsDMG() throws {
        let stable = try #require(Self.rules.first { $0.channel == .stable }.flatMap(\.installAssetPattern))
        let beta = try #require(Self.rules.first { $0.channel == .beta }.flatMap(\.installAssetPattern))
        func matches(_ pattern: String, _ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(matches(stable, "CotEditor_7.0.9.dmg"))
        #expect(!matches(stable, "CotEditor_7.1.0-beta.6.dmg"))
        #expect(matches(beta, "CotEditor_7.1.0-beta.6.dmg"))
        #expect(matches(beta, "CotEditor_7.1.0-beta.dmg"))
        #expect(!matches(beta, "CotEditor_7.0.9.dmg"))
    }

    /// The channel proof has to fail on the other train's artifact, or it proves
    /// nothing. For this vendor the filename repeats the tag, so a stable URL
    /// carries `-beta` in neither half — the tag-segment anchor is consistency
    /// with the neighbouring entries, not the thing that makes this work (see the
    /// registry comment).
    @Test func theChannelProofAcceptsOnlyABetaArtifact() throws {
        let key = ChannelProofKey(Self.bundleID, .beta)
        let proof = try #require(ChannelProofRegistry.githubProofs[key])
        let beta = "https://github.com/coteditor/CotEditor/releases/download/7.1.0-beta.6/CotEditor_7.1.0-beta.6.dmg"
        let stable = "https://github.com/coteditor/CotEditor/releases/download/7.0.9/CotEditor_7.0.9.dmg"
        guard case .artifact(let pattern) = proof else {
            Issue.record("expected an artifact proof"); return
        }
        #expect(beta.range(of: pattern, options: .regularExpression) != nil)
        #expect(stable.range(of: pattern, options: .regularExpression) == nil)
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
