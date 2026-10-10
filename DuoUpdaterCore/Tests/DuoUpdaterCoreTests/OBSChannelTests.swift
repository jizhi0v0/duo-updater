import Testing
import Foundation
@testable import DuoUpdaterCore

/// Five items of `https://obsproject.com/osx_update/updates_arm64_v2.xml` as read
/// on 2026-10-08, verbatim except that each item's `<sparkle:deltas>` block is cut
/// (no bearing on selection). In feed order: the newest beta (33.0.0-beta6), the
/// two newest stable releases, the 32.2.0-rc2 beta, and the one untagged item the
/// feed still carries (2023's 29.0.2). Every other item is tagged too: 31 stable,
/// 39 beta, 1 untagged.
private let obsFeedFixture = #"""
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>OBS Studio</title>
    <link>https://obsproject.com/</link>
    <item>
      <title>33.0.0</title>
      <pubDate>Fri, 02 Oct 2026 23:27:51 +0000</pubDate>
      <sparkle:releaseNotesLink>https://obsproject.com/osx_update/notes_beta.html</sparkle:releaseNotesLink>
      <sparkle:channel>beta</sparkle:channel>
      <sparkle:version>37074854565</sparkle:version>
      <sparkle:shortVersionString>33.0.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <enclosure url="https://cdn-fastly.obsproject.com/downloads/obs-studio-33.0.0-beta6-macos-apple.dmg" length="209597439" type="application/octet-stream" sparkle:edSignature="ZT/Xf1Uu+Puogc2U4R7zy7EOvGbjfp1AsDSwV+ff+TpRxCg5BPDDqPme/11CNsQB3LQbccmfu8MolE0HlSnSCA=="/>
    </item>
    <item>
      <title>32.2.2</title>
      <pubDate>Fri, 14 Aug 2026 22:44:16 +0000</pubDate>
      <sparkle:releaseNotesLink>https://obsproject.com/osx_update/notes_stable.html</sparkle:releaseNotesLink>
      <sparkle:channel>stable</sparkle:channel>
      <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>
      <sparkle:version>31845296735</sparkle:version>
      <sparkle:shortVersionString>32.2.2</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <enclosure url="https://cdn-fastly.obsproject.com/downloads/obs-studio-32.2.2-macos-apple.dmg" length="187703709" type="application/octet-stream" sparkle:edSignature="HJUDhp3y2uP0fIOHixl3fVDX2z21K766pmqyQbgEfPntlPQFEZiYtTImBn4Oj5QlGFocPu7SvnzEpK6ft68sDQ=="/>
    </item>
    <item>
      <title>32.2.1</title>
      <pubDate>Fri, 24 Jul 2026 22:59:05 +0000</pubDate>
      <sparkle:channel>stable</sparkle:channel>
      <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>
      <sparkle:version>30131037208</sparkle:version>
      <sparkle:shortVersionString>32.2.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <enclosure url="https://cdn-fastly.obsproject.com/downloads/obs-studio-32.2.1-macos-apple.dmg" length="187673506" type="application/octet-stream" sparkle:edSignature="H3jCimIWlI4AgCKOi/JD7piAuaMHrqL+ZOl3LaAD28NyFpykl6mwvZndlHux62ekjMT7yLBAj6YpE1z/V/liDQ=="/>
    </item>
    <item>
      <title>32.2.0</title>
      <pubDate>Thu, 16 Jul 2026 21:10:50 +0000</pubDate>
      <sparkle:channel>beta</sparkle:channel>
      <sparkle:version>29532805833</sparkle:version>
      <sparkle:shortVersionString>32.2.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <enclosure url="https://cdn-fastly.obsproject.com/downloads/obs-studio-32.2.0-rc2-macos-apple.dmg" length="187653027" type="application/octet-stream" sparkle:edSignature="5wcFmlSOecMSE77hfZArtzJuzMaQ6Oh2BOYXqqTHE8UaKV5/q6YSvUd6VY4w2+OYQboDDb741Q+1EdY/JooFBw=="/>
    </item>
    <item>
      <title>OBS Studio 29.0.2</title>
      <sparkle:releaseNotesLink>https://obsproject.com/osx_update/stable/notes.html</sparkle:releaseNotesLink>
      <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
      <pubDate>Sat, 04 Feb 2023 04:05:49 -0800</pubDate>
      <enclosure url="https://cdn-fastly.obsproject.com/downloads/obs-studio-29.0.2-macos-arm64.dmg" sparkle:version="4091379838" sparkle:shortVersionString="29.0.2" sparkle:dsaSignature="MCwCFHkPWpne8fCP+O5oM8VYy2wqCc9hAhQkoGrGYR0PoGAXoZDgheyj3W9hRw==" length="153250975" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""#

/// `[General]` of `global.ini` after a prerelease build's first run: the keys
/// OBS 33.0.0-beta6 added (`UpdateBranch`, `AutoBetaOptIn`) beside the ones
/// 32.2.1 had already written, as read off the real file on 2026-10-08.
/// `InstallGUID` is replaced with a placeholder.
private let globalINIAfterBetaRun = """
[General]
MaxLogs=10
InfoIncrement=-1
ProcessPriority=Normal
EnableAutoUpdates=true
BrowserHWAccel=true
MacOSPermissionsDialogLastShown=1
InstallGUID=0000000000000000000000000000000000000000
LastVersion=537001986
UpdateBranch=beta
AutoBetaOptIn=true

[Video]
Renderer=OpenGL
DisableOSXVSync=true
ResetOSXVSyncOnExit=true
"""

@Suite struct OBSChannelTests {
    /// Spelled out rather than taken from the binding: it is what the real
    /// bundles report (`CFBundleIdentifier` of the 32.2.1, 32.2.2 and
    /// 33.0.0-beta6 dmgs), so a binding keyed on anything else fails here.
    private static let bundleID = "com.obsproject.obs-studio"
    private static let feedURL = URL(string: "https://obsproject.com/osx_update/updates_arm64_v2.xml")

    private var items: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data(obsFeedFixture.utf8))
    }

    /// An install at a given build, wearing what the binding resolves for the
    /// given `UpdateBranch` — the same fields `AppScanner` copies out of a
    /// resolution, including `channelIsAuthoritative`, which is only true when the
    /// binding answered. The branch is handed in rather than read off this Mac's
    /// `global.ini`, so the answer does not depend on the machine running it.
    private func app(short: String, build: String, branch: String?) -> InstalledApp {
        let bound = OBSChannel.resolve(updateBranch: branch)
        return InstalledApp(
            name: "OBS", bundleID: Self.bundleID,
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-OBS.app"),
            isMASApp: false,
            sparkleFeedURL: Self.feedURL,
            sparkleChannelNames: bound?.sparkleChannelNames ?? [],
            sparkleEdPublicKey: "key",
            releaseChannel: bound?.channel ?? .stable,
            channelIsAuthoritative: bound != nil)
    }

    /// The offered item's BUILD: beta builds strip their suffix, so 33.0.0-beta6
    /// and a future 33.0.0 final share the short version and only the build
    /// (`sparkle:version`) tells them apart.
    private func offeredBuild(
        for app: InstalledApp, in feed: [SparkleAppcastItem]? = nil
    ) -> String? {
        SparkleAppcastSource.bestItem(
            for: app, from: feed ?? items, osVersion: "27.0", hostArch: .arm64,
            allowingIntelTranslation: true
        )?.version
    }

    private let beta6 = "37074854565"
    private let stable2 = "31845296735"

    // MARK: - The fixture itself

    @Test func theFeedPutsStableOffTheDefaultChannel() {
        #expect(items.count == 5)
        #expect(items.filter { $0.channel == nil }.compactMap(\.shortVersionString) == ["29.0.2"])
        #expect(items.filter { $0.channel == "stable" }.count == 2)
    }

    // MARK: - Reading the file

    @Test func theRealFileReadsAsBeta() {
        #expect(OBSChannel.updateBranch(inINI: globalINIAfterBetaRun) == "beta")
        #expect(OBSChannel.resolve(updateBranch: "beta")?.channel == .beta)
    }

    /// No key is OBS's default of stable, but it answers nil: the resolution is
    /// authoritative, and a never-launched beta build has no file yet.
    @Test func noChoiceOnDiskLeavesTheDecisionToTheBuild() {
        #expect(OBSChannel.updateBranch(inINI: "[General]\nMaxLogs=10") == nil)
        #expect(OBSChannel.resolve(updateBranch: nil) == nil)
        #expect(OBSChannel.resolve(updateBranch: "nightly") == nil)
        #expect(OBSChannel.resolve(updateBranch: "") == nil)
    }

    @Test func theKeyCountsOnlyUnderGeneral() {
        #expect(OBSChannel.updateBranch(inINI: "[Video]\nUpdateBranch=beta") == nil)
    }

    @Test func obsIsBound() {
        #expect(ChannelBinding.boundBundleIDs.contains(Self.bundleID))
        #expect(ChannelBinding.hasResolver(bundleID: Self.bundleID))
    }

    // MARK: - Selection

    /// The case the binding exists for (measured on the real 32.2.2 dmg with
    /// `UpdateBranch=beta`: "up to date" before this binding).
    ///
    /// Mutation that turns this red: mapping `beta` to anything but `.beta`.
    /// Removing OBS's case from the `ChannelBinding` switch does NOT — this
    /// builds the app from the pure resolver — and is `obsIsBound`'s to catch.
    @Test func aStableBuildOptedIntoBetaIsOfferedTheBeta() {
        #expect(offeredBuild(for: app(short: "32.2.2", build: stable2, branch: "beta")) == beta6)
    }

    /// Mutation that turns this red: dropping `sparkleChannelNames` from the
    /// stable resolution. `.stable` derives "the default channel only", where the
    /// only item is 29.0.2.
    @Test func anExplicitStableChoiceStaysOnStable() {
        #expect(offeredBuild(for: app(short: "32.2.1", build: "30131037208", branch: "stable")) == stable2)
    }

    /// OBS's own updater allows exactly one channel, so a release candidate is
    /// not offered the final release or its hotfixes — it waits for the next
    /// beta. Mirrored rather than improved on.
    ///
    /// Asked of the feed as it stood before 33.0.0-beta4 (the fixture minus
    /// beta6), when stable was AHEAD of beta: with beta6 present it is newest on
    /// either reading and the assertion could not tell them apart. Mutation that
    /// turns this red: adding `stable` to the beta resolution's tags.
    @Test func aBetaUserIsNotOfferedAStableRelease() {
        let beforeBeta4 = items.filter { $0.version != beta6 }
        let rc2 = app(short: "32.2.0", build: "29532805833", branch: "beta")
        #expect(offeredBuild(for: rc2, in: beforeBeta4) == "29532805833")
        #expect(offeredBuild(for: rc2) == beta6)
    }

    /// With no choice on disk the build decides, which is what made a nil answer
    /// safe: a stable build stays on stable, a beta build stays on beta.
    @Test func withoutAChoiceTheRunningBuildDecides() {
        #expect(offeredBuild(for: app(short: "32.2.1", build: "30131037208", branch: nil)) == stable2)
        #expect(offeredBuild(for: app(short: "32.2.0", build: "29532805833", branch: nil)) == beta6)
    }

    // MARK: - duo verify's stand-in install

    /// The page `duo verify` resolves for the changelog recipe, which has no
    /// installed copy to ask (#1112). A fresh OBS has no `UpdateBranch`, which OBS
    /// reads as `stable`, so it is offered 32.2.2 and its `notes_stable.html`.
    /// Mutation that turns this red: dropping OBS from
    /// `ChannelBinding.freshInstallResolution` — the stand-in is then on the
    /// default channel alone, whose only item is 29.0.2 and its
    /// `stable/notes.html`, a page the recipe refuses: `noFeedPage`.
    @Test func verifyReadsTheStablePageAFreshInstallIsOffered() throws {
        let feedURL = try #require(Self.feedURL)
        let link = SparkleAppcastSource.probeReleaseNotesLink(
            in: Data(obsFeedFixture.utf8), feedURL: feedURL, bundleID: Self.bundleID)
        #expect(link?.absoluteString == "https://obsproject.com/osx_update/notes_stable.html")
    }
}
