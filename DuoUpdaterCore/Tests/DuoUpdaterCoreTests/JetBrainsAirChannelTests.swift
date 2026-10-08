import Foundation
import Testing

@testable import DuoUpdaterCore

/// JetBrains Air's nightly build, told apart from Public Preview by the train in
/// its own `SUFeedURL` — `ReleaseChannel.detect` step 0.97 — and kept off the
/// Public Preview changelog recipe.
///
/// The inputs are each package's own Info.plist values: both share
/// `com.jetbrains.air`, the name "Air" and the Team; the nightly reports
/// `262.1054` and bakes in the `nightly` feed, Public Preview reports
/// `262.1037.6` and bakes in the `eap` feed.
@Suite struct JetBrainsAirChannelTests {

    private static let bundleID = "com.jetbrains.air"
    private static let nightlyFeed =
        "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/nightly/macos_aarch64/feed.xml"
    private static let previewFeed =
        "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/macos_aarch64/feed.xml"

    private func detect(
        _ version: String, feed: String?, bundleID: String = Self.bundleID
    ) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "Air", bundleID: bundleID, keystoneChannel: nil, version: version,
            bundleFileName: "Air", sparkleFeedURL: feed)
    }

    @Test func theNightlyBuildReadsAsNightly() {
        #expect(detect("262.1054", feed: Self.nightlyFeed) == .nightly)
        // The Intel package names the same train.
        #expect(detect("262.1054", feed:
            "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/nightly/macos_x64/feed.xml")
            == .nightly)
    }

    @Test func thePublicPreviewBuildStaysStable() {
        #expect(detect("262.1037.6", feed: Self.previewFeed) == .stable)
        #expect(detect("262.834.70", feed: Self.previewFeed) == .stable)
    }

    /// The feed is the signal; the nightly's two-part version is not, and a copy
    /// with no feed has nothing to read.
    @Test func withoutTheNightlyFeedANightlyVersionReadsAsStable() {
        #expect(detect("262.1054", feed: nil) == .stable)
        #expect(detect("262.1054", feed: Self.previewFeed) == .stable)
    }

    /// Only the train segment right after `fleet-feed/AIR` counts.
    @Test func nightlyElsewhereInTheFeedIsNotASignal() {
        for feed in [
            "https://plugins.jetbrains.com/fleet-parts/fleet-feed/FL/nightly/macos_aarch64/feed.xml",
            "https://plugins.jetbrains.com/nightly/fleet-feed/AIR/eap/macos_aarch64/feed.xml",
            "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/nightly/feed.xml",
            "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/nightly-old/macos_aarch64/feed.xml",
            "https://nightly.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/macos_aarch64/feed.xml",
            "not a url with fleet-feed/AIR/nightly in it",
        ] {
            #expect(detect("262.1054", feed: feed) == .stable, "\(feed)")
        }
    }

    /// Scoped to Air: another app carrying the same feed is not judged by it.
    @Test func otherBundleIDsAreNotReadByThisRule() {
        #expect(detect("262.1054", feed: Self.nightlyFeed, bundleID: "com.jetbrains.fleet")
            == .stable)
    }

    /// The releases API lists Public Preview only, so a nightly copy gets no
    /// recipe — not even through the lookup's "any recipe" fallback — while
    /// Public Preview copies keep it.
    @Test func theReleasesAPIRecipeIsNotShownForANightlyCopy() {
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: Self.bundleID, channel: .nightly, version: "262.1054") == nil)
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: Self.bundleID, channel: .stable, version: "262.1037.6")?
            .structuredFormat == .jetBrainsProductReleases)
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: Self.bundleID, channel: nil, version: "262.1037.6") != nil)
    }

    /// The same, through the pane's own selection, for a nightly row Sparkle
    /// answered from the nightly feed.
    @Test func thePaneSelectsNoRecipeForANightlyRow() {
        func result(_ channel: ReleaseChannel, _ version: String) -> UpdateResult {
            let app = InstalledApp(
                name: "Air", bundleID: Self.bundleID,
                shortVersion: version, buildVersion: version,
                path: URL(fileURLWithPath: "/Applications/Air.app"),
                isMASApp: false,
                sparkleFeedURL: URL(string: channel == .nightly
                    ? Self.nightlyFeed : Self.previewFeed),
                releaseChannel: channel)
            return UpdateResult(app: app, remote: nil, status: .unknown)
        }
        #expect(ChangelogRecipeSelection.recipe(for: result(.nightly, "262.1054")) == nil)
        #expect(ChangelogRecipeSelection.recipe(for: result(.stable, "262.1037.6")) != nil)
    }
}
