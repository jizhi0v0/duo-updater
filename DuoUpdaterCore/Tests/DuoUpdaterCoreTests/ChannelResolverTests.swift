import Testing
import Foundation
@testable import DuoUpdaterCore

/// Per-app channel resolvers turn a private preference into a `(channel, feed)`.
/// The mappings are pure; each app encodes the choice differently, so each gets
/// its own pinned-down truth. The safety invariant across all of them: an
/// unknown/absent preference resolves to the app's shipped default, never up.

// MARK: - Surge (Application Support `IncludeBetaBuilds` Bool → feed swap)

@Test func surgeBetaTrueRetargetsToBetaFeed() {
    let r = SurgeChannel.resolve(includeBeta: true)
    #expect(r.channel == .beta)
    #expect(r.feedOverride == SurgeChannel.betaFeed)
}

@Test func surgeBetaFalseStaysOnReleaseFeed() {
    let r = SurgeChannel.resolve(includeBeta: false)
    #expect(r.channel == .stable)
    #expect(r.feedOverride == SurgeChannel.releaseFeed)
}

// MARK: - OrbStack (`updates_optinChannel` String → channel tag, no feed swap)

@Test func orbStackMapsLiteralChannelNames() {
    #expect(OrbStackChannel.resolve(channelString: "stable").channel == .stable)
    #expect(OrbStackChannel.resolve(channelString: "beta").channel == .beta)
    #expect(OrbStackChannel.resolve(channelString: "canary").channel == .canary)
    // Channel-tag app: never a feed override, the recipe picks by channel.
    #expect(OrbStackChannel.resolve(channelString: "canary").feedOverride == nil)
}

@Test func orbStackAbsentOrUnknownIsStable() {
    #expect(OrbStackChannel.resolve(channelString: nil).channel == .stable)
    #expect(OrbStackChannel.resolve(channelString: "experimental").channel == .stable)
}

// MARK: - DuoPaste (`sparkleIncludePrereleases` Bool → channel tag, no feed swap)

@Test func duoPastePrereleasesMapToBeta() {
    #expect(DuoPasteChannel.resolve(includePrereleases: true).channel == .beta)
    #expect(DuoPasteChannel.resolve(includePrereleases: false).channel == .stable)
    #expect(DuoPasteChannel.resolve(includePrereleases: true).feedOverride == nil)
}

// MARK: - Registry dispatch

@Test func channelBindingDispatchesKnownAppsAndIgnoresOthers() {
    // Unknown / nil bundles get no bespoke resolver → generic detection stays.
    #expect(ChannelBinding.resolve(bundleID: "com.google.Chrome") == nil)
    #expect(ChannelBinding.resolve(bundleID: nil) == nil)
    // Known apps resolve to *something* (live pref read; value machine-dependent).
    #expect(ChannelBinding.resolve(bundleID: ForkChannel.bundleID) != nil)
    #expect(ChannelBinding.resolve(bundleID: OrbStackChannel.bundleID) != nil)
}
