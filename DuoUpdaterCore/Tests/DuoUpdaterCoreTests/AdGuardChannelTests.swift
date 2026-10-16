import Testing
import Foundation
@testable import DuoUpdaterCore

/// `AdGuardChannel`: a build's `AGChannel` names its track, and naming it does
/// not filter that track's own untagged feed item away.
@Suite struct AdGuardChannelTests {
    /// One untagged item per feed, as all three of AdGuard's feeds are. Item
    /// shape copied from the real beta and nightly appcasts (2026-10-16);
    /// enclosure and signature are placeholders.
    private static func feed(short: String, build: String, track: String) -> String {
        #"""
        <?xml version='1.0' encoding='UTF-8'?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>Version \#(short)</title>
              <sparkle:version>\#(build)</sparkle:version>
              <sparkle:shortVersionString>\#(short)</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>12.7.6</sparkle:minimumSystemVersion>
              <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>
              <sparkle:releaseNotesLink><![CDATA[https://link.adtidy.org/forward.html?app=mac&action=update_release_notes&from=updater&channel=\#(track)]]></sparkle:releaseNotesLink>
              <enclosure url="https://example.invalid/ZZFixture-AdGuard-\#(build).dmg" type="application/octet-stream" sparkle:edSignature="x" length="1" sparkle:installationType="package"></enclosure>
            </item>
          </channel>
        </rss>
        """#
    }

    /// The channel a copy is labelled with, and what the generic source offers
    /// it, resolved the way `AppScanner` resolves it: through
    /// `ChannelBinding.resolve` with the bundle's own Info.plist strings.
    private func scan(
        agChannel: String, shortVersion: String, build: String, feed: String
    ) -> (channel: ReleaseChannel?, offered: String?) {
        let bound = ChannelBinding.resolve(
            bundleID: AdGuardChannel.bundleID,
            bundleStrings: ChannelBinding.bundleStrings(fromInfoPlist: [
                "AGChannel": agChannel, "CFBundleShortVersionString": shortVersion,
                "CFBundleVersion": build,
            ]),
            bounded: BoundedBlockingWork(label: "test"))
        let app = InstalledApp(
            name: "AdGuard", bundleID: AdGuardChannel.bundleID,
            shortVersion: shortVersion, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Adguard.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.invalid/ZZFixture-appcast.xml"),
            sparkleChannelNames: bound?.sparkleChannelNames ?? [],
            sparkleEdPublicKey: "key",
            releaseChannel: bound?.channel ?? .stable,
            channelIsAuthoritative: bound != nil)
        let offered = SparkleAppcastSource.bestItem(
            for: app, from: SparkleAppcastParser.parse(Data(feed.utf8)),
            osVersion: "26.0", hostArch: .arm64, allowingIntelTranslation: false
        )?.shortVersionString
        return (bound?.channel, offered)
    }

    /// Mutation that turns the channel half red: dropping AdGuard's case from the
    /// resolver switch, or mapping `beta` to anything else. The offered half is
    /// the question the binding had to answer before it was added — an
    /// authoritative `.beta` admits `{untagged, "beta"}`, and the beta feed's
    /// only item is untagged.
    @Test func aBetaCopyIsLabelledBetaAndStillOfferedItsFeedsItem() {
        let feed = Self.feed(short: "2.20 RC 1", build: "2624", track: "beta")
        let older = scan(agChannel: "beta", shortVersion: "2.20 beta 3", build: "2600", feed: feed)
        #expect(older.channel == .beta)
        #expect(older.offered == "2.20 RC 1")
        let current = scan(agChannel: "beta", shortVersion: "2.20 RC 1", build: "2624", feed: feed)
        #expect(current.offered == "2.20 RC 1")
    }

    @Test func aNightlyCopyIsLabelledNightlyAndStillOfferedItsFeedsItem() {
        let feed = Self.feed(short: "2.20 Nightly 9", build: "2625", track: "nightly")
        let older = scan(agChannel: "nightly", shortVersion: "2.20 Nightly 8", build: "2610", feed: feed)
        #expect(older.channel == .nightly)
        #expect(older.offered == "2.20 Nightly 9")
        let current = scan(agChannel: "nightly", shortVersion: "2.20 Nightly 9", build: "2625", feed: feed)
        #expect(current.offered == "2.20 Nightly 9")
    }

    @Test func aReleaseCopyIsStable() {
        let feed = Self.feed(short: "2.20", build: "2626", track: "release")
        let older = scan(agChannel: "release", shortVersion: "2.19", build: "2500", feed: feed)
        #expect(older.channel == .stable)
        #expect(older.offered == "2.20")
    }

    /// A value AdGuard has not shipped, or no key at all, is not guessed at.
    @Test func anyOtherValueResolvesNothing() {
        #expect(AdGuardChannel.resolve(bundleStrings: [:]) == nil)
        #expect(AdGuardChannel.resolve(bundleStrings: ["AGChannel": "Beta"]) == nil)
        #expect(AdGuardChannel.resolve(bundleStrings: ["AGChannel": "alpha"]) == nil)
    }

    /// The wiring, end to end through `AppScanner.readApp(at:)`: the scanner has
    /// to hand the bundle's own Info.plist strings to the binding, or every test
    /// above passes while a real beta install is still labelled stable. The
    /// plists carry the real 2.20 RC 1 / 2.20 Nightly 9 bundles' identifying keys.
    ///
    /// Mutation that turns this red: passing `[:]` instead of
    /// `ChannelBinding.bundleStrings(fromInfoPlist: plist)` in `readApp`.
    @Test func theScanReadsTheTrackFromTheBundlesOwnInfoPlist() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duo-adguard-channel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        func bundle(_ track: String, short: String, build: String) throws -> URL {
            let app = root.appendingPathComponent("ZZFixture-Adguard-\(track).app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(
                at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": AdGuardChannel.bundleID,
                "CFBundleName": "Adguard",
                "CFBundleShortVersionString": short,
                "CFBundleVersion": build,
                "AGChannel": track,
                "SUFeedURL": "https://static.adtidy.org/mac/\(track)/adguard-\(track)-appcast.xml",
            ]
            try PropertyListSerialization
                .data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return app
        }

        let scanner = AppScanner(testflight: TestFlightInventory(macRows: []))
        let beta = try #require(scanner.readApp(at: try bundle("beta", short: "2.20 RC 1", build: "2624")))
        #expect(beta.releaseChannel == .beta)
        #expect(beta.channelIsAuthoritative)
        let nightly = try #require(scanner.readApp(
            at: try bundle("nightly", short: "2.20 Nightly 9", build: "2625")))
        #expect(nightly.releaseChannel == .nightly)
        #expect(nightly.channelIsAuthoritative)
    }

    /// No preference to watch, so not in `boundBundleIDs`, but a real resolver.
    @Test func adGuardHasAResolverButNothingToWatch() {
        #expect(ChannelBinding.hasResolver(bundleID: AdGuardChannel.bundleID))
        #expect(!ChannelBinding.boundBundleIDs.contains(AdGuardChannel.bundleID.lowercased()))
    }
}
