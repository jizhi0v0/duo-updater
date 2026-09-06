import Testing
import Foundation
@testable import DuoUpdaterCore

/// Fork hides its channel in `applicationUpdateChannel`. Getting the mapping
/// backwards is not a cosmetic mislabel — it retargets the feed, and because the
/// stable feed's head (2.66.7) is *older* than a Develop user's installed copy,
/// "wrong feed" surfaces as "no update available" rather than as an error. That
/// is what shipped: the constant said 2 == Stable when Fork writes 2 for Develop.
///
/// The values below are read out of Fork 2.69.0's binary, not out of our own
/// resolver — see `ForkChannel`'s doc comment for the disassembly. Pinning them
/// against `resolve` alone would repeat the mistake that produced the bug.

@Test func forkStableIsPrefOneAndRetargetsToStableFeed() {
    let r = ForkChannel.resolve(channelPref: 1)
    #expect(ForkChannel.stablePrefValue == 1)
    #expect(r.channel == .stable)
    #expect(r.feedOverride == ForkChannel.stableFeed)
}

/// The regression itself. 2 is what Fork's "Develop" menu item writes, so this
/// is the value a real Develop user has on disk; we answered `.stable` for it.
@Test func forkDeveloperPrefIsTwoAndKeepsTheDeveloperFeed() {
    let r = ForkChannel.resolve(channelPref: ForkChannel.developerPrefValue)
    #expect(ForkChannel.developerPrefValue == 2)
    #expect(r.channel == .beta)
    #expect(r.feedOverride == ForkChannel.developerFeed)
}

/// Absent is Develop because Fork's picker is a bare `cmp #1` against
/// `integerForKey:`, which yields 0 for an unset key.
@Test func forkAbsentPrefIsDeveloperDefault() {
    let r = ForkChannel.resolve(channelPref: nil)
    #expect(r.channel == .beta)
    #expect(r.feedOverride == ForkChannel.developerFeed)
}

@Test func forkUnexpectedPrefFallsBackToDeveloper() {
    for v in [0, 2, 3, -1, 99] {
        let r = ForkChannel.resolve(channelPref: v)
        #expect(r.channel == .beta, "pref \(v) should resolve to Develop/beta")
        #expect(r.feedOverride == ForkChannel.developerFeed)
    }
}

/// The two feeds must not collapse into one, or every assertion above passes
/// while the retargeting does nothing.
@Test func forkFeedsAreDistinct() {
    #expect(ForkChannel.stableFeed != ForkChannel.developerFeed)
    #expect(ForkChannel.stablePrefValue != ForkChannel.developerPrefValue)
}

/// `readChannelPref`'s typed half. Fork reads the key with `integerForKey:`,
/// which parses a string, so a string-typed pref must not read as "unset" —
/// unset falls through to Develop, which would push a Develop build at a copy
/// its owner put on Stable.
@Test func forkChannelPrefAcceptsWhatIntegerForKeyAccepts() {
    #expect(ForkChannel.channelPref(from: NSNumber(value: 1)) == 1)
    #expect(ForkChannel.channelPref(from: "1") == 1)
    #expect(ForkChannel.resolve(channelPref: ForkChannel.channelPref(from: "1")).channel
            == .stable)

    // Not numeric and not present both mean "not 1", which is Develop — the same
    // answer `integerForKey:` produces by returning 0.
    #expect(ForkChannel.channelPref(from: "develop") == nil)
    #expect(ForkChannel.channelPref(from: nil) == nil)
    #expect(ForkChannel.channelPref(from: Date()) == nil)
    #expect(ForkChannel.resolve(channelPref: ForkChannel.channelPref(from: "develop")).channel
            == .beta)
}
