import Testing
import Foundation
@testable import DuoUpdaterCore

/// `RuntimeViewerChannel`: Settings ▸ Updates ▸ "Include pre-release versions"
/// (`update.includePrereleases` in `settings.json`) → `<sparkle:channel>beta`.
@Suite struct RuntimeViewerChannelTests {
    /// Three items of the live appcast (2026-10-18), signatures and lengths cut:
    /// two beta-tagged 3.0.0 builds and the untagged 2.1.2.
    private static let feed = #"""
    <?xml version="1.0" encoding="utf-8" standalone="yes"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <title>3.0.0</title>
          <sparkle:channel>beta</sparkle:channel>
          <sparkle:version>20261016.12.58</sparkle:version>
          <sparkle:shortVersionString>3.0.0</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/releases/download/v3.0.0-beta.7/RuntimeViewer-macOS.zip" length="1" type="application/octet-stream" sparkle:edSignature="x"/>
        </item>
        <item>
          <title>3.0.0</title>
          <sparkle:channel>beta</sparkle:channel>
          <sparkle:version>20260929.01.44</sparkle:version>
          <sparkle:shortVersionString>3.0.0</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/releases/download/v3.0.0-beta.6/RuntimeViewer-macOS.zip" length="1" type="application/octet-stream" sparkle:edSignature="x"/>
        </item>
        <item>
          <title>2.1.2</title>
          <sparkle:version>20260815.06.34</sparkle:version>
          <sparkle:shortVersionString>2.1.2</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/releases/download/v2.1.2/RuntimeViewer-macOS.zip" length="1" type="application/octet-stream" sparkle:edSignature="x"/>
        </item>
      </channel>
    </rss>
    """#

    /// The build the source would offer an installed copy, with the binding's
    /// answer applied the way `AppScanner` applies it.
    private func offeredBuild(
        short: String, build: String, includePrereleases: Bool, bound: Bool = true
    ) -> String? {
        let binding = RuntimeViewerChannel.resolve(
            includePrereleases: includePrereleases, bundleFeeds: RuntimeViewerChannel.declaringBundleFeeds)
        let app = InstalledApp(
            name: "RuntimeViewer", bundleID: RuntimeViewerChannel.bundleID,
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-RuntimeViewer.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://mxiris-reverse-engineering.github.io/RuntimeViewer/appcast.xml"),
            sparkleChannelNames: binding.sparkleChannelNames,
            sparkleEdPublicKey: "key",
            releaseChannel: bound ? binding.channel : .stable,
            channelIsAuthoritative: bound)
        return SparkleAppcastSource.bestItem(
            for: app, from: SparkleAppcastParser.parse(Data(Self.feed.utf8)),
            osVersion: "27.0", hostArch: .arm64, allowingIntelTranslation: true
        )?.version
    }

    /// Mutation that turns this red: dropping the binding's beta answer.
    @Test func anOptedInStableCopyIsOfferedTheNewestBeta() {
        #expect(offeredBuild(short: "2.1.2", build: "20260815.06.34", includePrereleases: true)
            == "20261016.12.58")
    }

    @Test func anOptedOutStableCopyStaysOnUntaggedReleases() {
        #expect(offeredBuild(short: "2.1.2", build: "20260815.06.34", includePrereleases: false)
            == "20260815.06.34")
    }

    /// A beta build still listed in the feed would unlock the beta tag by feed
    /// inference alone. The app's own updater offers it nothing more once the box
    /// is unticked, and neither do we: that is what the authoritative `.stable`
    /// is for. The last line is the same copy with no binding, which the feed
    /// inference does move to the next beta.
    @Test func anOptedOutBetaCopyIsNotOfferedTheNextBeta() {
        #expect(offeredBuild(short: "3.0.0", build: "20260929.01.44", includePrereleases: false)
            == "20260815.06.34")
        #expect(offeredBuild(short: "3.0.0", build: "20260929.01.44", includePrereleases: true)
            == "20261016.12.58")
        #expect(offeredBuild(short: "3.0.0", build: "20260929.01.44", includePrereleases: false, bound: false)
            == "20261016.12.58")
    }

    /// `v3.0.0-beta.7` reads `3.0.0`: nothing in the bundle marks a beta.
    @Test func theBundleVersionCarriesNoChannel() {
        #expect(ReleaseChannel.detect(
            name: "RuntimeViewer", bundleID: RuntimeViewerChannel.bundleID,
            keystoneChannel: nil, version: "3.0.0") == .stable)
    }

    /// Only a JSON `true` at `update.includePrereleases` opts in.
    @Test func onlyJSONTrueUnderUpdateOptsIn() {
        func read(_ json: String?) -> ReleaseChannel {
            RuntimeViewerChannel.resolve(
                includePrereleases: RuntimeViewerChannel.includesPrereleases(
                    settings: json.map { Data($0.utf8) }),
                bundleFeeds: RuntimeViewerChannel.declaringBundleFeeds).channel
        }
        #expect(read(#"{"update":{"automaticallyChecks":true,"includePrereleases":true,"checkInterval":"daily"}}"#) == .beta)
        #expect(read(#"{"update":{"includePrereleases":false}}"#) == .stable)
        #expect(read(#"{"update":{"includePrereleases":1}}"#) == .stable)
        #expect(read(#"{"update":{"includePrereleases":"true"}}"#) == .stable)
        #expect(read(#"{"includePrereleases":true}"#) == .stable)
        #expect(read(#"{"general":{}}"#) == .stable)
        #expect(read("not json") == .stable)
        #expect(read(nil) == .stable)
    }

    @Test func theBindingIsRegisteredAndReadsTheSettingsFile() {
        #expect(ChannelBinding.hasResolver(bundleID: RuntimeViewerChannel.bundleID))
        #expect(ChannelBinding.boundBundleIDs.contains(RuntimeViewerChannel.bundleID.lowercased()))
        #expect(RuntimeViewerChannel.settingsFileURL.path.hasSuffix(
            "Library/Application Support/RuntimeViewer/settings.json"))
    }

    /// Copies before v2.0.0-RC.6 state no `SUFeedURL` and are handed the
    /// vendor's appcast; a copy that declares one keeps its own. Mutation that
    /// turns this red: overriding a declared feed, or dropping the fill-in.
    @Test func onlyCopiesWithoutAFeedAreHandedOne() {
        for flag in [false, true] {
            #expect(RuntimeViewerChannel.resolve(includePrereleases: flag, bundleFeeds: [:]).feedOverride
                == URL(string: "https://mxiris-reverse-engineering.github.io/RuntimeViewer/appcast.xml"))
            #expect(RuntimeViewerChannel.resolve(
                includePrereleases: flag, bundleFeeds: RuntimeViewerChannel.declaringBundleFeeds
            ).feedOverride == nil)
        }
        #expect(SparkleFeedCatalog.feed(forBundleID: RuntimeViewerChannel.bundleID) == nil)
    }

    /// Real tags (2026-10-18). The stable recipe takes only bare versions; the
    /// beta one takes every tag and keeps the suffix.
    @Test func changelogTagPatternsSplitTheTracks() throws {
        let recipes = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == RuntimeViewerChannel.bundleID }
        let stable = try #require(recipes.first { $0.channel == .stable }?.tagPattern)
        let beta = try #require(recipes.first { $0.channel == .beta }?.tagPattern)
        let cases: [(tag: String, stable: String?, beta: String)] = [
            ("v3.0.0-beta.7", nil, "3.0.0-beta.7"),
            ("v2.1.2", "2.1.2", "2.1.2"),
            ("v2.1.0-RC.3", nil, "2.1.0-RC.3"),
            ("v2.0.0", "2.0.0", "2.0.0"),
            ("v1.1.0", "1.1.0", "1.1.0"),
            ("v4.0.0", "4.0.0", "4.0.0"),
            ("v4.0.0-alpha.1", nil, "4.0.0-alpha.1"),
        ]
        for c in cases {
            #expect(VendorProbeRecipe.extractVersion(from: c.tag, pattern: stable) == c.stable, "\(c.tag)")
            #expect(VendorProbeRecipe.extractVersion(from: c.tag, pattern: beta) == c.beta, "\(c.tag)")
        }
    }
}
