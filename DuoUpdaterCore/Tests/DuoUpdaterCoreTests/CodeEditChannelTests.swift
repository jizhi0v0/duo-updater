import Testing
import Foundation
@testable import DuoUpdaterCore

/// CodeEdit publishes ONE appcast item per release and tags every one of them
/// `<sparkle:channel>dev</sparkle:channel>` — there is no untagged item, ever.
/// The installed bundle's `SUFeedURL` (`releases/latest/download/appcast.xml`)
/// therefore always serves a feed with no default channel, and the only item in
/// it is the newest release.
///
/// Captured verbatim from the v0.3.6 release asset on 2026-09-12, except the
/// `<description>` body, which is cut down to its heading (25 KB of GitHub
/// markup with no bearing on selection). v0.2.0, v0.3.4 and v0.3.5 have the same
/// shape: one item, tagged `dev`.
private let codeEditFeedFixture = #"""
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>CodeEdit</title>
        <item>
            <title>0.3.6</title>
            <pubDate>Tue, 26 Aug 2025 11:24:14 -0700</pubDate>
            <link>https://github.com/CodeEditApp/CodeEdit</link>
            <sparkle:fullReleaseNotesLink>https://codeedit.app/whats-new/</sparkle:fullReleaseNotesLink>
            <sparkle:channel>dev</sparkle:channel>
            <sparkle:version>47</sparkle:version>
            <sparkle:shortVersionString>0.3.6</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/CodeEditApp/CodeEdit/releases/download/v0.3.6/CodeEdit.dmg" length="35962501" type="application/octet-stream" sparkle:edSignature="TrnQ8D6wY4q3zM3/LoubifHSMypcBL+Fvm0J9gaumqAAjhBqdiayaj3cWbSuaUOIqgp/qUgKF+dTNxVOG2shAw=="/>
            <description><![CDATA[
<h1>Task Output, External File Changes, Invisible Characters</h1>
            ]]></description>
        </item>
    </channel>
</rss>
"""#

@Suite struct CodeEditChannelTests {
    /// Spelled out rather than taken from the binding: it is what the real bundle
    /// reports (`CFBundleIdentifier` of the v0.3.6 dmg), so a binding keyed on
    /// anything else fails here instead of silently never matching.
    private static let bundleID = "app.codeedit.CodeEdit"

    private var items: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data(codeEditFeedFixture.utf8))
    }

    /// An install at a given version, wearing whatever `ChannelBinding` resolves
    /// for CodeEdit — the same fields `AppScanner` copies out of it, including
    /// `channelIsAuthoritative`, which is only true when a binding answered.
    private func scannedApp(short: String, build: String) -> InstalledApp {
        let bound = ChannelBinding.resolve(bundleID: Self.bundleID)
        return InstalledApp(
            name: "CodeEdit", bundleID: Self.bundleID,
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-CodeEdit.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://github.com/CodeEditApp/CodeEdit/releases/latest/download/appcast.xml"),
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
        #expect(items.count == 1)
        #expect(items.allSatisfy { $0.channel == "dev" },
                "every item is tagged; none sits on the default channel")
    }

    // MARK: - Selection

    /// The case the binding exists for. The feed only ever holds the newest
    /// release, so an install one version behind is NOT in it — and without a
    /// binding `allowedChannels` falls back to the default channel alone, which
    /// matches zero items: the row reads unknown instead of offering 0.3.6.
    ///
    /// Mutations that turn this red: removing CodeEdit's case from the
    /// `ChannelBinding` switch; resolving with empty `sparkleChannelNames`
    /// (a `.stable` channel derives no tag); retyping the tag.
    @Test func anInstallBehindTheFeedIsOfferedTheNewRelease() {
        #expect(best(for: scannedApp(short: "0.3.5", build: "46")) == "0.3.6")
    }

    /// The up-to-date install is in the feed, so this passed before the binding
    /// too (the running build's own item names `dev`). It is still a mutation
    /// target: an authoritative binding switches the build-match inference OFF,
    /// so resolving with empty `sparkleChannelNames` or a retyped tag loses this
    /// install as well — both turn it red.
    @Test func theCurrentInstallStillMatchesItsOwnItem() {
        #expect(best(for: scannedApp(short: "0.3.6", build: "47")) == "0.3.6")
    }

    /// Why a binding and not the generic inference: with nothing authoritative,
    /// an install missing from the feed is assumed to be on the default channel.
    /// A fixture guard, not a mutation target — it holds whatever the binding
    /// does, and fails only if the fixture stops describing CodeEdit's feed.
    @Test func withoutABindingAnInstallBehindTheFeedSeesNothing() {
        let unbound = InstalledApp(
            name: "CodeEdit", bundleID: Self.bundleID,
            shortVersion: "0.3.5", buildVersion: "46",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-CodeEdit.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://github.com/CodeEditApp/CodeEdit/releases/latest/download/appcast.xml"),
            sparkleEdPublicKey: "key",
            releaseChannel: .stable, channelIsAuthoritative: false)
        #expect(best(for: unbound) == nil)
    }
}
