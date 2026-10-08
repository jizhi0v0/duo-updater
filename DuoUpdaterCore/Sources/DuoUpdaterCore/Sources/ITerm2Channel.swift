import Foundation

/// iTerm2 (`com.googlecode.iterm2`) — a feed-swap Sparkle app whose swap reads
/// addresses out of its OWN Info.plist, so this binding does the same.
///
/// What iTerm2 does (read from `gnachman/iTerm2`,
/// `iTermController.refreshSoftwareUpdateUserDefaults`): with "Check for test
/// releases" on (`CheckTestRelease` in its `UserDefaults`, default off) it writes
/// the bundle's `SUFeedURLForTesting` into its own `SUFeedURL` default, otherwise
/// the bundle's `SUFeedURLForFinal`, each with a `?shard=N` that today changes
/// nothing in the response. A stable build declares `final_modern.xml` and
/// `testing_modern.xml`; a nightly build declares `nightly_modern.xml` under all
/// three keys, and greys the toggle out — but a value set on an earlier stable
/// install stays in the domain.
///
/// So the testing feed is taken from the bundle (`ChannelBinding.bundleFeeds`),
/// never hard-coded: on a nightly copy it IS the nightly feed, the swap changes
/// nothing, and this answers nil so the copy stays on the feed it declares.
/// Hard-coded, that leftover toggle would move the nightly copy onto the testing
/// feed, whose version is never above a nightly's, and the copy would never be
/// offered a nightly again.
///
/// Toggle off (or unreadable) → `.stable` on the bundle's `SUFeedURLForFinal`,
/// which is what iTerm2 itself writes — and the same address a stable build
/// already declares as `SUFeedURL`, so on a stable build it changes nothing. On a
/// nightly build, where testing and final are one address, the toggle cannot
/// mean anything and this answers nil either way: the copy keeps the feed it
/// declares and its build-inferred channel.
///
/// Known divergence, inherited rather than introduced: iTerm2's release scripts
/// write the testing feed only when a beta ships, so it can sit BEHIND the final
/// feed after a stable release. iTerm2's own updater reads it all the same, and
/// so does this.
///
/// Not watched by `ChannelBinding.preferenceWatchCandidates` beyond the shared
/// `~/Library/Preferences` root, which already covers this domain.
enum ITerm2Channel {
    static let bundleID = "com.googlecode.iterm2"

    static let testingKey = "SUFeedURLForTesting"
    static let finalKey = "SUFeedURLForFinal"

    /// The two addresses a stable build declares (3.7.3, 2026-10-08), for
    /// `ChannelBinding.allResolutions`, which enumerates without a bundle.
    static let stableBundleFeeds: [String: URL] = [
        "SUFeedURL": URL(string: "https://iterm2.com/appcasts/final_modern.xml")!,
        finalKey: URL(string: "https://iterm2.com/appcasts/final_modern.xml")!,
        testingKey: URL(string: "https://iterm2.com/appcasts/testing_modern.xml")!,
    ]

    /// Map the toggle and the bundle's own feeds to a resolution, or nil to leave
    /// the bundle's declared feed and inferred channel alone. Pure and tested.
    static func resolve(checkTestRelease: Bool, bundleFeeds: [String: URL]) -> ResolvedChannel? {
        // No bundle in hand: the channel-switch fingerprint pass. Answer
        // something that differs between on and off, so the flip is noticed; the
        // rescan it triggers passes the feeds and decides for real.
        guard !bundleFeeds.isEmpty else {
            return checkTestRelease ? ResolvedChannel(channel: .beta) : nil
        }
        guard let testing = bundleFeeds[testingKey],
              let final = bundleFeeds[finalKey] ?? bundleFeeds["SUFeedURL"],
              testing != final
        else { return nil }
        return checkTestRelease
            ? ResolvedChannel(channel: .beta, feedOverride: testing)
            : ResolvedChannel(channel: .stable, feedOverride: final)
    }

    static func resolveCurrent(bundleFeeds: [String: URL]) -> ResolvedChannel? {
        resolve(checkTestRelease: readCheckTestRelease(), bundleFeeds: bundleFeeds)
    }

    static func readCheckTestRelease() -> Bool {
        // Force a fresh read from cfprefsd: this long-running menu-bar process can
        // otherwise serve a value cached from before iTerm2 wrote the toggle.
        CFPreferencesAppSynchronize(bundleID as CFString)
        guard let value = CFPreferencesCopyAppValue(
            "CheckTestRelease" as CFString, bundleID as CFString
        ) else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
