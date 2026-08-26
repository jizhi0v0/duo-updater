import Testing
import Foundation
@testable import DuoUpdaterCore

/// BetterDisplay ships three tracks through ONE appcast, tagged `pre` and
/// `internal` — spellings `ReleaseChannel.rawValue` cannot produce. The binding
/// therefore names the feed's tags outright (`sparkleChannelNames`); these tests
/// pin that down against the vendor's REAL feed.
///
/// Four items captured verbatim from
/// `betterdisplay.pro/betterdisplay/sparkle/appcast.xml` on 2026-08-26 — one per
/// distinct channel spelling in that feed, plus the untagged stable line. Kept
/// byte-for-byte (indentation, the newline inside `<sparkle:releaseNotesLink>`)
/// because the whitespace is exactly what the parser has to survive.
private let betterDisplayFeedFixture = #"""
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <item>
            <title>5.0.4</title>
            <pubDate>Mon, 24 Aug 2026 21:45:16 +0200</pubDate>
            <sparkle:channel>internal</sparkle:channel>
            <sparkle:releaseNotesLink>
                https://waydabber.github.io/BetterDisplay/changelog.html?tag=pre
            </sparkle:releaseNotesLink>
            <sparkle:version>52989</sparkle:version>
            <sparkle:shortVersionString>5.0.4</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.3</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/waydabber/BetterDisplay/releases/download/pre/BetterDisplay-v5.0.4-b52989.zip" length="25544140" type="application/octet-stream" sparkle:edSignature="o3JbwYVFXaNQlxz8lxfcPRKdsPA9CdHGIUrNtZWcUiDbZnAkvNGINVJQlPLDgIwRdMCrJ2W/TuwqjONgcLsyCw=="/>
        </item>
        <item>
            <title>5.0.3</title>
            <pubDate>Tue, 18 Aug 2026 22:37:01 +0200</pubDate>
            <sparkle:channel>pre</sparkle:channel>
            <sparkle:releaseNotesLink>
                https://waydabber.github.io/BetterDisplay/changelog.html?tag=v5.0.3
            </sparkle:releaseNotesLink>
            <sparkle:version>52922</sparkle:version>
            <sparkle:shortVersionString>5.0.3</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.3</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/waydabber/BetterDisplay/releases/download/v5.0.3/BetterDisplay-v5.0.3-pre-release.dmg" length="25605853" type="application/octet-stream" sparkle:edSignature="GD8V8LBBghqh7R+bEiJH5M58DhbaUR3Of/P2S4AblpnvKY9rh0IBI7xjaTPgRkXcpa+OgDB0qzcqPDVTAVeODQ=="/>
        </item>
        <item>
            <title>4.3.6</title>
            <pubDate>Tue, 11 Aug 2026 14:40:39 +0200</pubDate>
            <sparkle:releaseNotesLink>
                https://waydabber.github.io/BetterDisplay/changelog.html?tag=v4.3.6
            </sparkle:releaseNotesLink>
            <sparkle:version>50119</sparkle:version>
            <sparkle:shortVersionString>4.3.6</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.2</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/waydabber/BetterDisplay/releases/download/v4.3.6/BetterDisplay-v4.3.6.dmg" length="23958493" type="application/octet-stream" sparkle:edSignature="i7Gbqcw7Lg8mciAil2EE7U6rQSQnK/ZfMvWe0TxPHdikFY0qqNFXaBzrISGmpwDku5jgwLzzPNyKASiSC7MGCw=="/>
        </item>
        <item>
            <title>5.0.1</title>
            <pubDate>Thu, 23 Jul 2026 09:09:51 +0200</pubDate>
            <sparkle:channel>arm64_pre</sparkle:channel>
            <sparkle:releaseNotesLink>
                https://waydabber.github.io/BetterDisplay/changelog.html?tag=v5.0.1
            </sparkle:releaseNotesLink>
            <sparkle:version>52622</sparkle:version>
            <sparkle:shortVersionString>5.0.1</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.3</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/waydabber/BetterDisplay/releases/download/v5.0.1/BetterDisplay-v5.0.1-pre-release.dmg" length="16831019" type="application/octet-stream" sparkle:edSignature="E2Ix6WdRBQqK/ww1PeSwTu9B8w1CnzlBwtoOfHddZD3yGZdgq446fe21QUOmPfVqNeDaMga7oi+SKG70d+bcCw=="/>
        </item>
    </channel>
</rss>
"""#

@Suite struct BetterDisplayChannelTests {
    private static let bundleID = BetterDisplayChannel.bundleID

    private var items: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data(betterDisplayFeedFixture.utf8))
    }

    /// An install pinned to a version/build, wearing whatever the resolver
    /// produced for a given pair of toggle states — the same fields
    /// `AppScanner` copies out of `ChannelBinding`.
    private func app(
        short: String, build: String, preEnabled: Bool, internalEnabled: Bool
    ) -> InstalledApp {
        let bound = BetterDisplayChannel.resolve(
            preEnabled: preEnabled, internalEnabled: internalEnabled)
        return InstalledApp(
            name: "BetterDisplay", bundleID: Self.bundleID,
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/BetterDisplay.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://betterdisplay.pro/betterdisplay/sparkle/appcast.xml"),
            sparkleChannelNames: bound.sparkleChannelNames,
            sparkleEdPublicKey: "key",
            releaseChannel: bound.channel,
            channelIsAuthoritative: true)
    }

    private func best(
        short: String, build: String, preEnabled: Bool, internalEnabled: Bool,
        hostArch: HostArch = .arm64
    ) -> String? {
        SparkleAppcastSource.bestItem(
            for: app(short: short, build: build,
                     preEnabled: preEnabled, internalEnabled: internalEnabled),
            from: items, osVersion: "27.0", hostArch: hostArch,
            allowingIntelTranslation: true
        )?.shortVersionString
    }

    // MARK: - The fixture itself

    @Test func theFeedReallySpellsChannelsPreAndInternal() {
        let byVersion = Dictionary(
            uniqueKeysWithValues: items.map { ($0.shortVersionString ?? "", $0.channel) })
        #expect(byVersion["4.3.6"] == .some(nil), "stable line is untagged")
        #expect(byVersion["5.0.3"] == "pre")
        #expect(byVersion["5.0.4"] == "internal")
        #expect(byVersion["5.0.1"] == "arm64_pre")
    }

    /// The whole reason this binding exists: no `ReleaseChannel` case spells
    /// these, so deriving the tag from the channel would build an allowed set
    /// that matches nothing in the feed.
    @Test func noReleaseChannelCaseSpellsTheseTags() {
        for channel in ReleaseChannel.allCases {
            let derived = SparkleAppcastSource.sparkleChannelName(channel)
            #expect(derived != "pre")
            #expect(derived != "internal")
            #expect(derived != "arm64_pre")
        }
    }

    // MARK: - Resolver (two Bools → three tracks)

    @Test func bothOffIsStableAndClaimsNoTags() {
        let r = BetterDisplayChannel.resolve(preEnabled: false, internalEnabled: false)
        #expect(r.channel == .stable)
        #expect(r.sparkleChannelNames.isEmpty)
        #expect(r.feedOverride == nil, "channel-tag app: one feed, never a swap")
        #expect(r.feedHTTPHeaders.isEmpty)
    }

    @Test func preOnlyUnlocksPre() {
        let r = BetterDisplayChannel.resolve(preEnabled: true, internalEnabled: false)
        #expect(r.channel == .beta)
        #expect(r.sparkleChannelNames == ["pre"])
    }

    /// The GUI nests the internal toggle under the pre one, so opting into
    /// internal keeps the plain pre builds — the newer of the two must win.
    @Test func internalSubsumesPre() {
        let r = BetterDisplayChannel.resolve(preEnabled: true, internalEnabled: true)
        #expect(r.channel == .unstable)
        #expect(r.sparkleChannelNames == ["pre", "internal"])
    }

    @Test func internalWithoutPreStillResolvesToInternal() {
        // Not reachable through the GUI; a defaults write or a vendor bug could
        // produce it. Never silently downgrade someone below what they set.
        let r = BetterDisplayChannel.resolve(preEnabled: false, internalEnabled: true)
        #expect(r.channel == .unstable)
        #expect(r.sparkleChannelNames == ["pre", "internal"])
    }

    // MARK: - Gating against the real feed

    /// The regression this whole change exists for, reproduced from the real
    /// machine state on 2026-08-26: BetterDisplay 4.3.6 (build 50119, a
    /// STABLE-track build) with both toggles on. Build-inference alone sees a
    /// stable build and offers nothing; the vendor's own updater offers 5.0.4.
    @Test func stableBuildOptedIntoInternalIsOfferedTheInternalRelease() {
        #expect(best(short: "4.3.6", build: "50119",
                     preEnabled: true, internalEnabled: true) == "5.0.4")
    }

    @Test func stableBuildOptedIntoPreStopsAtPreNotInternal() {
        #expect(best(short: "4.3.6", build: "50119",
                     preEnabled: true, internalEnabled: false) == "5.0.3")
    }

    @Test func stableBuildWithBothTogglesOffStaysOnStable() {
        #expect(best(short: "4.3.6", build: "50119",
                     preEnabled: false, internalEnabled: false) == "4.3.6")
    }

    @Test func preUserIsNeverPushedTheInternalBuild() {
        #expect(best(short: "5.0.3", build: "52922",
                     preEnabled: true, internalEnabled: false) == "5.0.3")
    }

    /// `arm64_pre` is a real tag in this feed and its builds are arm64-only, but
    /// the feed declares no `<sparkle:hardwareRequirements>` and the enclosure
    /// carries no arch token — so `archVerdict` would rate it `.neutral` and
    /// offer it to an Intel Mac that cannot run it. It is excluded from every
    /// track; 5.0.2+ superseded it, so nothing is lost but changelog rows.
    @Test func arm64PreIsNeverInAnyAllowedSet() {
        for (pre, int) in [(false, false), (true, false), (true, true)] {
            let allowed = SparkleAppcastSource.allowedChannels(
                for: app(short: "4.3.6", build: "50119",
                         preEnabled: pre, internalEnabled: int),
                in: items)
            #expect(!allowed.contains("arm64_pre"))
        }
    }

    /// Every track keeps the untagged line available — Sparkle's own rule, and
    /// what lets a prerelease user land back on stable when it overtakes them.
    @Test func theDefaultChannelIsAllowedOnEveryTrack() {
        for (pre, int) in [(false, false), (true, false), (true, true)] {
            let allowed = SparkleAppcastSource.allowedChannels(
                for: app(short: "4.3.6", build: "50119",
                         preEnabled: pre, internalEnabled: int),
                in: items)
            #expect(allowed.contains(nil))
        }
    }

    /// The red this change turns green, pinned so it cannot come back: with the
    /// tags derived from the channel — which is all the code could do before
    /// `sparkleChannelNames` — the allowed set is {default, "unstable"}, and this
    /// feed has nothing tagged "unstable". The internal opt-in collapses to
    /// stable and 5.0.4 is never offered.
    @Test func derivingTagsFromTheChannelAloneWouldMissTheWholeV5Line() {
        let derivedOnly = InstalledApp(
            name: "BetterDisplay", bundleID: Self.bundleID,
            shortVersion: "4.3.6", buildVersion: "50119",
            path: URL(fileURLWithPath: "/Applications/BetterDisplay.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://betterdisplay.pro/betterdisplay/sparkle/appcast.xml"),
            sparkleChannelNames: [],   // what the old code effectively had
            sparkleEdPublicKey: "key",
            releaseChannel: .unstable, channelIsAuthoritative: true)
        #expect(SparkleAppcastSource.allowedChannels(for: derivedOnly, in: items)
            == [nil, "unstable"])
        #expect(SparkleAppcastSource.bestItem(
            for: derivedOnly, from: items, osVersion: "27.0",
            hostArch: .arm64, allowingIntelTranslation: true
        )?.shortVersionString == "4.3.6",
        "no item is tagged \"unstable\", so the opt-in silently collapses to stable")
    }

    /// Opting a 4.x install into a prerelease track walks it across BetterDisplay's
    /// PAID major boundary: v5 is a free upgrade only for Pro licenses bought after
    /// 2025-01-01, and the vendor's own notes warn that an outdated license "cannot
    /// activate a new or deactivated BetterDisplay 5 installation". So the offer
    /// this change unlocks must also carry the major-upgrade flag the UI warns on.
    /// It does, and by the fallback tier rather than the authoritative one: this
    /// feed declares no `minimumAutoupdateVersion` anywhere, and "Sparkle" is not a
    /// license-neutral source, so the marketing-major bump 4→5 is what trips it.
    @Test func theInternalOfferIsFlaggedAsAMajorUpgrade() throws {
        let installed = app(short: "4.3.6", build: "50119",
                            preEnabled: true, internalEnabled: true)
        let item = try #require(SparkleAppcastSource.bestItem(
            for: installed, from: items, osVersion: "27.0",
            hostArch: .arm64, allowingIntelTranslation: true))
        #expect(item.minimumAutoupdateVersion == nil, "no floor declared — tier 2 applies")
        let remote = RemoteVersion(
            shortVersion: item.shortVersionString, version: item.version,
            downloadURL: item.enclosureURL, sourceName: "Sparkle",
            minimumAutoupdateVersion: item.minimumAutoupdateVersion)
        let result = UpdateResult(app: installed, remote: remote, status: .updateAvailable(latest: item.shortVersionString ?? ""))
        #expect(result.isMajorUpgrade)
    }

    // MARK: - No regression for apps without the new field

    /// An app whose binding names no tags keeps deriving them from the channel,
    /// which is every binding that existed before `sparkleChannelNames`.
    @Test func anAppWithNoNamedTagsStillDerivesFromItsChannel() {
        let duoPaste = InstalledApp(
            name: "DuoPaste", bundleID: "io.duopaste.daemon",
            shortVersion: "1.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/DuoPaste.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
            sparkleEdPublicKey: "key",
            releaseChannel: .beta, channelIsAuthoritative: true)
        let allowed = SparkleAppcastSource.allowedChannels(for: duoPaste, in: items)
        #expect(allowed == [nil, "beta"])
    }

    /// And an app with no binding at all still infers from the running build.
    @Test func withoutABindingTheRunningBuildStillDecides() {
        let inferred = InstalledApp(
            name: "BetterDisplay", bundleID: Self.bundleID,
            shortVersion: "5.0.3", buildVersion: "52922",
            path: URL(fileURLWithPath: "/Applications/BetterDisplay.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://betterdisplay.pro/betterdisplay/sparkle/appcast.xml"),
            sparkleEdPublicKey: "key",
            releaseChannel: .stable, channelIsAuthoritative: false)
        #expect(SparkleAppcastSource.allowedChannels(for: inferred, in: items)
            == [nil, "pre"])
    }
}
