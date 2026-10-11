import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ChannelBinding.feedVerificationCases` — the feed addresses the bindings hand
/// out as `feedOverride`, as `duo verify --feed` sweeps them.
///
/// The list is derived from `allResolutions`, so most of what can go wrong is
/// the derivation dropping, doubling or misnaming a feed, or the runtime
/// handing out an address the list does not have. Every case names the
/// mutation it catches.
@Suite struct ChannelFeedRegistryTests {

    private var cases: [SparkleFeedCatalog.VerificationCase] {
        ChannelBinding.feedVerificationCases
    }

    /// The case registered for this app and channel, if any.
    private func registered(_ bundleID: String, _ channel: ReleaseChannel) -> [URL] {
        cases.filter {
            $0.bundleID.lowercased() == bundleID.lowercased()
                && $0.resolution?.channel == channel
        }.map(\.feed)
    }

    /// Pinned as ids, not addresses: the address is written once, in its
    /// channel file, and a copy here would be a second place to update. What
    /// this pins is that no app or channel silently drops out of the sweep.
    ///
    /// Mutation: drop the `feedOverride` guard's binding (sweep every
    /// resolution) and OrbStack, TablePlus and the rest arrive with nothing to
    /// read; drop iTerm2 from `allResolutions` and its two ids go missing.
    @Test func theSweptChannelFeedsArePinned() {
        let ids = Set(cases.map(\.recipeID))
        #expect(ids == [
            "feed:com.DanPristupov.Fork:beta",
            "feed:com.DanPristupov.Fork:stable",
            "feed:com.colliderli.iina:beta",
            "feed:com.colliderli.iina:stable",
            "feed:com.googlecode.iterm2:beta",
            "feed:com.googlecode.iterm2:stable",
            "feed:com.mitchellh.ghostty:stable",
            "feed:com.nssurge.surge-mac:beta",
            "feed:com.nssurge.surge-mac:stable",
            "feed:com.nuebling.mac-mouse-fix:beta",
            "feed:com.nuebling.mac-mouse-fix:stable",
        ], "swept: \(ids.sorted())")
        #expect(cases.allSatisfy { $0.kind == .channel && $0.declared == nil })
    }

    /// One id per app and channel, and never one the catalog uses — `Baseline`
    /// keys a streak and an issue number on the id alone.
    ///
    /// Mutation: do not fold duplicates. Fork's Develop feed is enumerated for
    /// both `2` and an absent preference, so it arrives twice.
    /// Mutation: drop the channel from `recipeID`. Surge's two feeds then share
    /// one id.
    @Test func idsAreUniqueAndCarryTheirChannel() {
        let ids = cases.map(\.recipeID)
        #expect(ids.count == Set(ids).count, "duplicate ids: \(ids)")
        for entry in cases {
            #expect(entry.recipeID
                == "feed:\(entry.bundleID):\(entry.resolution?.channel.rawValue ?? "?")")
        }
        let catalog = Set(SparkleFeedCatalog.verificationCases.map(\.recipeID))
        #expect(catalog.isDisjoint(with: ids))
        // And the catalog's own ids did not move.
        #expect(SparkleFeedCatalog.verificationCases.allSatisfy {
            $0.recipeID == "feed:\($0.bundleID)"
        })
    }

    /// Every `feedOverride` a binding can produce is either swept or named as
    /// not swept — and the exclusion is not inert.
    ///
    /// Mutation: exclude by something wider than the bundle id. A feed then
    /// drops out of the sweep. (Folding by id alone instead of id and address
    /// is NOT caught today: no app hands out two addresses for one channel, so
    /// the two folds agree on every current input.)
    @Test func everyFeedOverrideIsSweptOrExcused() {
        for binding in ChannelBinding.allResolutions {
            guard let feed = binding.resolved.feedOverride else { continue }
            if ChannelBinding.feedsNotSwept.contains(binding.bundleID.lowercased()) { continue }
            #expect(registered(binding.bundleID, binding.resolved.channel).contains(feed),
                    "\(binding.bundleID) \(binding.resolved.channel) \(feed) is not swept")
        }
        let withFeeds = Set(ChannelBinding.allResolutions
            .filter { $0.resolved.feedOverride != nil }.map { $0.bundleID.lowercased() })
        #expect(ChannelBinding.feedsNotSwept.isSubset(of: withFeeds))
    }

    /// CleanShot's feed carries a licence key, and the enumerated one carries a
    /// placeholder that type promises never to send.
    ///
    /// Mutation: drop the `feedsNotSwept` check. The placeholder-keyed address
    /// joins the sweep and a nightly request goes out with it.
    @Test func theLicenceKeyedFeedIsNeverSwept() {
        #expect(!cases.contains { $0.bundleID.lowercased() == CleanShotChannel.bundleID.lowercased() })
        #expect(!cases.contains { $0.feed.query?.contains("key=") == true })
    }

    /// The pure resolvers, over every value their preference can hold, only
    /// ever hand out a registered address for the channel they resolve to.
    ///
    /// Inputs beyond the ones `allResolutions` enumerates are included on
    /// purpose — Fork's `0` and `7` are Develop to Fork — so this is not the
    /// derivation checked against itself.
    @Test func eachResolvedFeedOverrideComesFromTheRegisteredList() {
        var resolutions: [(String, ResolvedChannel?)] = [
            (GhosttyChannel.bundleID, GhosttyChannel.resolveCurrent()),
        ]
        for flag in [true, false] {
            resolutions.append((SurgeChannel.bundleID, SurgeChannel.resolve(includeBeta: flag)))
            resolutions.append((IINAChannel.bundleID, IINAChannel.resolve(receiveBeta: flag)))
            resolutions.append((MacMouseFixChannel.bundleID,
                                MacMouseFixChannel.resolve(checkForPrereleases: flag)))
            resolutions.append((ITerm2Channel.bundleID, ITerm2Channel.resolve(
                checkTestRelease: flag, bundleFeeds: ITerm2Channel.stableBundleFeeds)))
        }
        for pref in [nil, 0, 1, 2, 7] {
            resolutions.append((ForkChannel.bundleID, ForkChannel.resolve(channelPref: pref)))
        }
        #expect(resolutions.count == 14)
        for (bundleID, resolved) in resolutions {
            guard let resolved, let feed = resolved.feedOverride else {
                Issue.record("\(bundleID) resolved to no feed")
                continue
            }
            #expect(registered(bundleID, resolved.channel) == [feed],
                    "\(bundleID) \(resolved.channel) resolves to \(feed)")
        }
    }

    /// The same question asked of the runtime's own entry point, on this Mac's
    /// real preferences: whatever they say, the address `AppScanner` would be
    /// handed is one the sweep reads, for the channel it is handed under.
    ///
    /// Only for the apps in the list, so nothing here opens another app's
    /// container. iTerm2 is given a stable build's feeds, the one input that
    /// resolver takes from the bundle.
    @Test func theRuntimeEntryPointOnlyHandsOutRegisteredFeeds() {
        let bounded = BoundedBlockingWork(label: "test")
        for bundleID in Set(cases.map(\.bundleID)) {
            let feeds = bundleID == ITerm2Channel.bundleID ? ITerm2Channel.stableBundleFeeds : [:]
            guard let resolved = ChannelBinding.resolve(
                bundleID: bundleID, bundleFeeds: feeds, bounded: bounded),
                  let feed = resolved.feedOverride else { continue }
            // The address is not printed: on this path it is the real one, and
            // CleanShot's carries a licence key in its query.
            #expect(registered(bundleID, resolved.channel).contains(feed),
                    "\(bundleID) resolved \(resolved.channel) to \(feed.host ?? "?")\(feed.path) on this Mac")
        }
    }

    /// The sweep reads a channel feed as the bound install would: on its
    /// channel, authoritatively, which is what `AppScanner` does with a
    /// binding. Without a resolution the stand-in is unchanged.
    ///
    /// Mutation: ignore `resolution` in `probeApp`. A beta feed whose items
    /// started carrying `<sparkle:channel>beta` would then read as every item
    /// filtered out.
    @Test func aChannelFeedIsReadOnItsOwnChannel() throws {
        let beta = try #require(cases.first { $0.resolution?.channel == .beta })
        let app = SparkleAppcastSource.probeApp(
            bundleID: beta.bundleID, feedURL: beta.feed, resolution: beta.resolution)
        #expect(app.releaseChannel == .beta)
        #expect(app.channelIsAuthoritative)

        let fresh = SparkleAppcastSource.probeApp(bundleID: beta.bundleID, feedURL: beta.feed)
        #expect(fresh.releaseChannel == .stable)
        #expect(!fresh.channelIsAuthoritative)
    }

    /// The enclosure read cap is the one byte the range asks for. A literal,
    /// not the constant against itself.
    @Test func theEnclosureReadCapIsOneByte() {
        #expect(SparkleAppcastSource.enclosureReadCap == 1)
    }
}
