import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ITerm2Channel`: "Check for test releases" swaps to the testing feed the
/// BUNDLE declares, so a nightly build — whose every feed key is the nightly
/// feed — is left alone even when the toggle survives from an old stable install.
@Suite struct ITerm2ChannelTests {
    /// The feed keys of the real 3.7.3 stable and 3.7.20261007-nightly bundles,
    /// read off their Info.plists on 2026-10-08 (plus one non-feed key and one
    /// non-string value, which must be ignored).
    private static var stablePlist: [String: Any] { [
        "CFBundleIdentifier": "com.googlecode.iterm2",
        "SUFeedURL": "https://iterm2.com/appcasts/final_modern.xml",
        "SUFeedURLForFinal": "https://iterm2.com/appcasts/final_modern.xml",
        "SUFeedURLForTesting": "https://iterm2.com/appcasts/testing_modern.xml",
        "SUFeedURLBogus": 42,
    ] }
    private static var nightlyPlist: [String: Any] { [
        "SUFeedURL": "https://iterm2.com/appcasts/nightly_modern.xml",
        "SUFeedURLForFinal": "https://iterm2.com/appcasts/nightly_modern.xml",
        "SUFeedURLForTesting": "https://iterm2.com/appcasts/nightly_modern.xml",
    ] }
    private static let testing = URL(string: "https://iterm2.com/appcasts/testing_modern.xml")!

    private func feeds(_ plist: [String: Any]) -> [String: URL] {
        ChannelBinding.bundleFeeds(fromInfoPlist: plist)
    }

    @Test func onlyStringFeedKeysAreRead() {
        #expect(Set(feeds(Self.stablePlist).keys) == ["SUFeedURL", "SUFeedURLForFinal", "SUFeedURLForTesting"])
    }

    /// Hard-coding the testing address would still pass here; the nightly case
    /// below is what catches that.
    @Test func aStableBuildWithTheToggleOnReadsTheTestingFeed() throws {
        let resolved = try #require(ITerm2Channel.resolve(checkTestRelease: true, bundleFeeds: feeds(Self.stablePlist)))
        #expect(resolved.channel == .beta)
        #expect(resolved.feedOverride == Self.testing)
    }

    /// The reason the feed comes from the bundle. Mutation that turns this red:
    /// returning the testing address whenever the toggle is on.
    @Test func aNightlyBuildWithALeftoverToggleKeepsItsOwnFeed() {
        #expect(ITerm2Channel.resolve(checkTestRelease: true, bundleFeeds: feeds(Self.nightlyPlist)) == nil)
    }

    /// Off is what iTerm2 writes too: the bundle's final feed, which on a stable
    /// build is the address it already declares.
    @Test func toggleOffReadsTheFinalFeed() throws {
        let resolved = try #require(ITerm2Channel.resolve(checkTestRelease: false, bundleFeeds: feeds(Self.stablePlist)))
        #expect(resolved.channel == .stable)
        #expect(resolved.feedOverride == URL(string: "https://iterm2.com/appcasts/final_modern.xml"))
        #expect(ITerm2Channel.resolve(checkTestRelease: false, bundleFeeds: feeds(Self.nightlyPlist)) == nil)
        #expect(ITerm2Channel.resolve(checkTestRelease: false, bundleFeeds: [:]) == nil)
    }

    /// The fingerprint pass has no bundle; the flip must still change its answer
    /// so the rescan that decides for real is triggered.
    @Test func withoutABundleTheFlipIsStillVisible() {
        let on = ChannelSwitchDetector.fingerprint(of: ITerm2Channel.resolve(checkTestRelease: true, bundleFeeds: [:]))
        let off = ChannelSwitchDetector.fingerprint(of: ITerm2Channel.resolve(checkTestRelease: false, bundleFeeds: [:]))
        #expect(on != off)
    }

    @Test func iTerm2IsBound() {
        #expect(ChannelBinding.boundBundleIDs.contains("com.googlecode.iterm2"))
        #expect(ChannelBinding.hasResolver(bundleID: "com.googlecode.iterm2"))
    }
}
