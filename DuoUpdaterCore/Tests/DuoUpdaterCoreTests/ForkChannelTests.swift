import Testing
import Foundation
@testable import DuoUpdaterCore

/// Fork hides its channel in `applicationUpdateChannel` (2 == Stable). The pure
/// mapping is the one piece worth pinning down — getting it backwards would
/// offer a beta build to a Stable user.

@Test func forkStablePrefRetargetsToStableFeed() {
    let r = ForkChannel.resolve(channelPref: 2)
    #expect(r.channel == .stable)
    #expect(r.feedOverride == ForkChannel.stableFeed)
}

@Test func forkAbsentPrefIsDeveloperDefault() {
    let r = ForkChannel.resolve(channelPref: nil)
    #expect(r.channel == .beta)
    #expect(r.feedOverride == ForkChannel.developerFeed)
}

@Test func forkUnexpectedPrefFallsBackToDeveloper() {
    for v in [0, 1, 3, -1, 99] {
        let r = ForkChannel.resolve(channelPref: v)
        #expect(r.channel == .beta, "pref \(v) should resolve to Developer/beta")
        #expect(r.feedOverride == ForkChannel.developerFeed)
    }
}
