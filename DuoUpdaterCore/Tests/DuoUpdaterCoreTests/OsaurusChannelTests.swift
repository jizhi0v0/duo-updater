import Testing
import Foundation
@testable import DuoUpdaterCore

/// Osaurus tags every appcast item `<sparkle:channel>release</sparkle:channel>`;
/// none is untagged (160 of 160 on 2026-09-29). The feed keeps history, but not
/// all of it: 317 GitHub releases up to 0.15.12 have no item, so an install at
/// one of those versions is absent from the feed.
///
/// The first three items of `https://osaurus-ai.github.io/osaurus/appcast.xml`
/// as read on 2026-09-29, verbatim except the markdown `<description>` bodies,
/// which are cut (no bearing on selection).
private let osaurusFeedFixture = #"""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Osaurus</title>
        <item>
            <title>0.25.14</title>
            <pubDate>Sun, 27 Sep 2026 07:10:28 +0000</pubDate>
            <sparkle:channel>release</sparkle:channel>
            <sparkle:version>0.25.14</sparkle:version>
            <sparkle:shortVersionString>0.25.14</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <enclosure url="https://github.com/osaurus-ai/osaurus/releases/download/0.25.14/Osaurus-0.25.14.dmg" length="79256834" type="application/octet-stream" sparkle:edSignature="H+sC9KHzEDiE5wY55YKKLo8wz84pLenOH2QQCwIJXoXMajUmdEtHh9KVX+Rf1ZYDi4SKMXuorKezHwDQyZgQAA=="/>
            <description sparkle:format="markdown"><![CDATA[
## What's Changed
]]></description>
        </item>
        <item>
            <title>0.25.13</title>
            <pubDate>Sat, 26 Sep 2026 01:26:07 +0000</pubDate>
            <sparkle:channel>release</sparkle:channel>
            <sparkle:version>0.25.13</sparkle:version>
            <sparkle:shortVersionString>0.25.13</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <enclosure url="https://github.com/osaurus-ai/osaurus/releases/download/0.25.13/Osaurus-0.25.13.dmg" length="78909784" type="application/octet-stream" sparkle:edSignature="/Cn3bCbpVK645sLNa+JCQG6sl69K5ZtTsvs1AYUyiAdosZpHy58lp8WJfUZgSBcq8Ck3kda+12ndw94kcwfrBw=="/>
            <description sparkle:format="markdown"><![CDATA[
## What's Changed
]]></description>
        </item>
        <item>
            <title>0.25.12</title>
            <pubDate>Wed, 23 Sep 2026 07:48:33 +0000</pubDate>
            <sparkle:channel>release</sparkle:channel>
            <sparkle:version>0.25.12</sparkle:version>
            <sparkle:shortVersionString>0.25.12</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <enclosure url="https://github.com/osaurus-ai/osaurus/releases/download/0.25.12/Osaurus-0.25.12.dmg" length="78613244" type="application/octet-stream" sparkle:edSignature="Z8cZfSIAOsHC60TWk25tAekICbvWkKUKdHKS42dTIO1F5QJAUCQ+TZ2xli49EvWNdb/8C/T5zESAWTVUmLBSAA=="/>
            <description sparkle:format="markdown"><![CDATA[
## What's Changed
]]></description>
        </item>
  </channel>
</rss>
"""#

@Suite struct OsaurusChannelTests {
    /// Spelled out rather than taken from the binding: it is what the real bundle
    /// reports (`CFBundleIdentifier` of the 0.25.14 dmg), so a binding keyed on
    /// anything else fails here instead of silently never matching.
    private static let bundleID = "com.dinoki.osaurus"
    private static let feedURL = URL(string: "https://osaurus-ai.github.io/osaurus/appcast.xml")

    private var items: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data(osaurusFeedFixture.utf8))
    }

    /// An install at a given version, wearing whatever `ChannelBinding` resolves
    /// for Osaurus — the same fields `AppScanner` copies out of it, including
    /// `channelIsAuthoritative`, which is only true when a binding answered.
    /// Osaurus's `CFBundleVersion` equals its short version.
    private func scannedApp(version: String) -> InstalledApp {
        let bound = ChannelBinding.resolve(bundleID: Self.bundleID)
        return InstalledApp(
            name: "Osaurus", bundleID: Self.bundleID,
            shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Osaurus.app"),
            isMASApp: false,
            sparkleFeedURL: Self.feedURL,
            sparkleChannelNames: bound?.sparkleChannelNames ?? [],
            sparkleEdPublicKey: "key",
            releaseChannel: bound?.channel ?? .stable,
            channelIsAuthoritative: bound != nil)
    }

    private func best(for app: InstalledApp) -> String? {
        SparkleAppcastSource.bestItem(
            for: app, from: items, osVersion: "27.0", hostArch: .arm64,
            allowingIntelTranslation: true
        )?.shortVersionString
    }

    // MARK: - The fixture itself

    @Test func theFeedHasNoDefaultChannel() {
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.channel == "release" },
                "every item is tagged; none sits on the default channel")
    }

    // MARK: - Selection

    /// The case the binding exists for: an install older than every item is not
    /// in the feed, so without a binding `allowedChannels` falls back to the
    /// default channel alone and matches nothing.
    ///
    /// Mutations that turn this red: removing Osaurus's case from the
    /// `ChannelBinding` switch; resolving with empty `sparkleChannelNames`
    /// (a `.stable` channel derives no tag); retyping the tag.
    @Test func anInstallAbsentFromTheFeedIsOfferedTheNewest() {
        #expect(best(for: scannedApp(version: "0.15.12")) == "0.25.14")
    }

    /// The up-to-date install is in the feed, so this passed before the binding
    /// too. It is still a mutation target: an authoritative binding switches the
    /// build-match inference OFF, so an empty or retyped tag loses this install
    /// as well.
    @Test func theCurrentInstallIsUpToDate() {
        #expect(best(for: scannedApp(version: "0.25.14")) == "0.25.14")
    }

    /// Why a binding and not the generic inference. A fixture guard, not a
    /// mutation target — it holds whatever the binding does, and fails only if
    /// the fixture stops describing Osaurus's feed.
    @Test func withoutABindingAnInstallAbsentFromTheFeedSeesNothing() {
        let unbound = InstalledApp(
            name: "Osaurus", bundleID: Self.bundleID,
            shortVersion: "0.15.12", buildVersion: "0.15.12",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Osaurus.app"),
            isMASApp: false,
            sparkleFeedURL: Self.feedURL,
            sparkleEdPublicKey: "key",
            releaseChannel: .stable, channelIsAuthoritative: false)
        #expect(best(for: unbound) == nil)
    }
}
