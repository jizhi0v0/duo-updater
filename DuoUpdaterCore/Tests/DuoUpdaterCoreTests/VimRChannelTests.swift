import Testing
import Foundation
@testable import DuoUpdaterCore

/// `VimRChannel`: the feed VimR's own `UpdaterDelegate` picks in code, stable or
/// snapshot, from `UserDefaults["168"]["use-snapshot-update-channel"]`.
@Suite struct VimRChannelTests {
    /// `qvacua/vimr` `appcast.xml` (2026-10-10), signature and notes cut.
    private static let stableFeed = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <item>
          <title>v0.67.0-20261010.130648</title>
          <sparkle:version>20261010.130648</sparkle:version>
          <sparkle:shortVersionString>v0.67.0</sparkle:shortVersionString>
          <minimumSystemVersion>14.8</minimumSystemVersion>
          <enclosure url="https://github.com/qvacua/vimr/releases/download/v0.67.0-20261010.130648/VimR-v0.67.0.tar.bz2"
                     sparkle:edSignature="x" length="19530909" type="application/octet-stream"/>
        </item>
      </channel>
    </rss>
    """#

    /// `appcast_snapshot.xml` at qvacua/vimr@245d6ad3 (2025-07-15), when it held
    /// a snapshot newer than the stable 0.55.0 (build 20250713.101600).
    private static let snapshotFeed = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <item>
          <title>SNAPSHOT-20250715.204752</title>
          <sparkle:version>20250715.204752</sparkle:version>
          <sparkle:shortVersionString>SNAPSHOT-20250715.204752</sparkle:shortVersionString>
          <minimumSystemVersion>13.5</minimumSystemVersion>
          <enclosure url="https://github.com/qvacua/vimr/releases/download/snapshot/20250715.204752/VimR-SNAPSHOT-20250715.204752.tar.bz2"
                     sparkle:edSignature="x" length="16970438" type="application/octet-stream"/>
        </item>
      </channel>
    </rss>
    """#

    private func offered(
        from feed: String, short: String, build: String, useSnapshot: Bool
    ) -> String? {
        let binding = VimRChannel.resolve(useSnapshot: useSnapshot)
        let app = InstalledApp(
            name: "VimR", bundleID: VimRChannel.bundleID,
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-VimR.app"),
            isMASApp: false,
            sparkleFeedURL: binding.feedOverride,
            sparkleEdPublicKey: "key",
            releaseChannel: binding.channel,
            channelIsAuthoritative: true)
        return SparkleAppcastSource.bestItem(
            for: app, from: SparkleAppcastParser.parse(Data(feed.utf8)),
            osVersion: "26.0", hostArch: .arm64, allowingIntelTranslation: true
        )?.version
    }

    @Test func theToggleSwapsTheFeed() {
        #expect(VimRChannel.resolve(useSnapshot: false)
            == ResolvedChannel(channel: .stable, feedOverride: VimRChannel.stableFeed))
        #expect(VimRChannel.resolve(useSnapshot: true)
            == ResolvedChannel(channel: .preview, feedOverride: VimRChannel.snapshotFeed))
        #expect(VimRChannel.stableFeed.absoluteString
            == "https://raw.githubusercontent.com/qvacua/vimr/master/appcast.xml")
        #expect(VimRChannel.snapshotFeed.absoluteString
            == "https://raw.githubusercontent.com/qvacua/vimr/master/appcast_snapshot.xml")
    }

    /// The `v`-prefixed `shortVersionString` is not the key: the date-stamped build is.
    @Test func anOlderStableCopyIsOfferedTheNewestStable() {
        #expect(offered(from: Self.stableFeed, short: "0.66.1", build: "20260920.105849",
                        useSnapshot: false) == "20261010.130648")
        // An x86_64-only copy from before the date-stamped builds (0.34.0, build 355).
        #expect(offered(from: Self.stableFeed, short: "0.34.0", build: "355",
                        useSnapshot: false) == "20261010.130648")
    }

    @Test func aStableCopyWithSnapshotTickedIsOfferedTheSnapshot() {
        #expect(offered(from: Self.snapshotFeed, short: "0.55.0", build: "20250713.101600",
                        useSnapshot: true) == "20250715.204752")
    }

    /// What `PrefMiddleware` writes: the whole `AppState` as one dictionary.
    @Test func readsTheNestedStateKey() {
        #expect(VimRChannel.useSnapshot(fromState: ["use-snapshot-update-channel": NSNumber(value: true)]))
        #expect(!VimRChannel.useSnapshot(fromState: ["use-snapshot-update-channel": NSNumber(value: false)]))
        #expect(!VimRChannel.useSnapshot(fromState: ["open-new-window-when-launching": NSNumber(value: true)]))
        #expect(!VimRChannel.useSnapshot(fromState: nil))
        #expect(VimRChannel.stateKey == "168")
    }

    /// VimR's 2023 bump to `"169"` left `"168"` behind untouched. A stale `true`
    /// there must not keep a user VimR now treats as stable on snapshots.
    @Test func aNewerStateKeyMakesTheOldToggleStale() {
        let ticked: [String: Any] = ["use-snapshot-update-channel": NSNumber(value: true)]
        #expect(!VimRChannel.useSnapshot(fromState: ticked, domainKeys: ["168", "169"]))
        #expect(!VimRChannel.useSnapshot(fromState: ticked, domainKeys: ["168", "1000"]))
        // Older keys, VimR's own non-state keys and Sparkle's keys leave it alone.
        #expect(VimRChannel.useSnapshot(fromState: ticked, domainKeys: ["128", "168", "SUHasLaunchedBefore", "NSWindow Frame 1"]))
        #expect(VimRChannel.useSnapshot(fromState: ticked, domainKeys: []))
    }

    /// A snapshot bundle carries no channel signal of its own: same id, name and
    /// Team, and its version reads stable. The preference is the only signal.
    @Test func theSnapshotBundleReadsStable() {
        #expect(ReleaseChannel.detect(
            name: "VimR", bundleID: VimRChannel.bundleID,
            keystoneChannel: nil, version: "SNAPSHOT-20250715.204752") == .stable)
    }

    @Test func vimRIsBound() {
        #expect(ChannelBinding.boundBundleIDs.contains(VimRChannel.bundleID.lowercased()))
        #expect(ChannelBinding.hasResolver(bundleID: VimRChannel.bundleID))
    }
}

/// Four releases from `api.github.com/repos/qvacua/vimr/releases` (2026-11-11):
/// a stable release, the `neovim-v…` prerelease beside it (a bare nvim tarball),
/// a stable release with sub-bullets, and a `snapshot/…` prerelease.
private let vimRReleasesFixture = #"""
[
 {"tag_name": "v0.67.0-20261010.130648", "prerelease": false, "draft": false,
  "published_at": "2026-10-10T11:10:46Z",
  "body": "* Neovim 0.12.6 😀\n* New icon. Thanks @georgeharker!"},
 {"tag_name": "neovim-v0.12.6-20261010.102856", "prerelease": true, "draft": false,
  "published_at": "2026-10-10T08:51:04Z",
  "body": "Neovim universal build with libintl, not signed."},
 {"tag_name": "v0.62.0-20260408.124559", "prerelease": false, "draft": false,
  "published_at": "2026-04-08T10:50:07Z",
  "body": "* Neovim 0.12.1 😀\n* Dependencides updates:\n  - sparkle-project/Sparkle@2.9.1\n  - SimplyDanny/SwiftLintPlugins@0.63.2\n  - qvacua/MessagePack.swift@5.0.0\n  - Moved from Kitura/BlueSocket@2.0.2 to qvacua/BlueSocket@2.1.0"},
 {"tag_name": "snapshot/20250715.204752", "prerelease": true, "draft": false,
  "published_at": "2025-07-15T18:50:45Z",
  "body": "⚠️ WIP for making VimR Swift 6 compatible. Probably instable! Use it at your own risk!"}
]
"""#

@Suite struct VimRChangelogRecipeTests {
    private func parsed() throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: VimRChannel.bundleID, channel: .stable))
        return try #require(ChangelogService.parse(recipe, body: vimRReleasesFixture))
    }

    @Test func readsOnlyStableVimRReleasesAsTheBundleNamesThem() throws {
        let entries = try parsed().entries
        #expect(entries.map(\.version) == ["0.67.0", "0.62.0"])
        #expect(entries.first?.date == "2026-10-10")
        #expect(entries.first?.items == ["Neovim 0.12.6 😀", "New icon. Thanks @georgeharker!"])
    }

    @Test func keepsTheDependencySubBullets() throws {
        let older = try #require(try parsed().entries.last)
        #expect(older.items.contains("sparkle-project/Sparkle@2.9.1"))
        #expect(older.items.count == 6)
    }

    /// The snapshot track gets the snapshot feed's own notes instead.
    @Test func aSnapshotCopyIsNotHandedTheStableList() {
        #expect(ChangelogRecipeRegistry.recipe(forBundleID: VimRChannel.bundleID, channel: .preview) == nil)
    }
}
