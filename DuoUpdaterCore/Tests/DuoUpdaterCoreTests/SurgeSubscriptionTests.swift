import Testing
import Foundation
@testable import DuoUpdaterCore

/// Surge offers only the releases its subscription covers (`SurgeSubscription`),
/// and so must we: a build dated at or after `fusDate` will not open on that
/// licence. The dates below are Surge's beta feed on 2026-10-17 and the
/// `fusDate` read on the development Mac the same day.
struct SurgeSubscriptionTests {
    static let fusDate = 1_792_162_109  // 2026-10-16 22:48:29 +0800

    /// The head of `appcast-signed-beta.xml`, 2026-10-17.
    static let feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <sparkle:version>12560</sparkle:version>
          <sparkle:shortVersionString>6.11.0</sparkle:shortVersionString>
          <pubDate>1792168472</pubDate>
          <enclosure url="https://example.com/12560.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
        </item>
        <item>
          <sparkle:version>12500</sparkle:version>
          <sparkle:shortVersionString>6.10.0</sparkle:shortVersionString>
          <pubDate>1791818674</pubDate>
          <enclosure url="https://example.com/12500.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
        </item>
        <item>
          <sparkle:version>12290</sparkle:version>
          <sparkle:shortVersionString>6.9.1</sparkle:shortVersionString>
          <pubDate>1788968251</pubDate>
          <enclosure url="https://example.com/12290.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
        </item>
      </channel>
    </rss>
    """

    // MARK: - The licence cache

    /// The attribute's shape: JSON whose `policy` is base64 of JSON. Values are
    /// made up apart from the two dates.
    static func attribute(policy: [String: Any]) -> Data {
        let inner = try! JSONSerialization.data(withJSONObject: policy)
        return try! JSONSerialization.data(withJSONObject: [
            "policy": inner.base64EncodedString(), "sign": "x", "messages": [String](),
        ])
    }

    @Test func readsFusDateNotExpiresOnDate() {
        let data = Self.attribute(policy: [
            "fusDate": Self.fusDate, "expiresOnDate": 1_792_833_413, "type": "x",
        ])
        #expect(SurgeSubscription.window(fromAttribute: data) == .before(Self.fusDate))
    }

    @Test func anythingElseIsUnreadable() {
        #expect(SurgeSubscription.window(fromAttribute: nil) == .unreadable)
        #expect(SurgeSubscription.window(fromAttribute: Data("not json".utf8)) == .unreadable)
        #expect(SurgeSubscription.window(fromAttribute: Self.attribute(policy: ["expiresOnDate": 1])) == .unreadable)
        let notBase64 = try! JSONSerialization.data(withJSONObject: ["policy": "%%%"])
        #expect(SurgeSubscription.window(fromAttribute: notBase64) == .unreadable)
    }

    @Test func coversOnlyReleasesStrictlyBefore() {
        let window = SurgeSubscription.Window.before(Self.fusDate)
        #expect(SurgeSubscription.covers(pubDate: "1792162108", under: window))
        #expect(!SurgeSubscription.covers(pubDate: "1792162109", under: window))
        #expect(!SurgeSubscription.covers(pubDate: "1792168472", under: window))
        // Surge's `integerValue` would read these as 0 and admit them.
        #expect(!SurgeSubscription.covers(pubDate: "Sat, 17 Oct 2026 00:34:32 +0800", under: window))
        #expect(!SurgeSubscription.covers(pubDate: nil, under: window))
        #expect(!SurgeSubscription.covers(pubDate: "1", under: .unreadable))
    }

    // MARK: - The offer

    static func app(short: String, build: String, feed: URL, bundleID: String = SurgeChannel.bundleID) -> InstalledApp {
        InstalledApp(
            name: "Surge", bundleID: bundleID, shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/Surge.app"),
            isMASApp: false, sparkleFeedURL: feed, sparkleEdPublicKey: "key")
    }

    static func feedFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("surge-subscription-\(UUID().uuidString).xml")
        try Data(feed.utf8).write(to: url)
        return url
    }

    static func source(_ window: SurgeSubscription.Window?) -> SparkleAppcastSource {
        SparkleAppcastSource(
            session: URLSession(configuration: .ephemeral), loginWalls: [],
            subscriptionWindow: { app in
                app.bundleID == SurgeChannel.bundleID ? window : nil
            })
    }

    /// The case on the development Mac: 6.10.0 installed, 6.11.0 published after
    /// the window closed. Nothing is offered, and the row is told why.
    @Test func newestBeyondWindowIsNotOffered() async throws {
        let feed = try Self.feedFile()
        defer { try? FileManager.default.removeItem(at: feed) }
        let app = Self.app(short: "6.10.0", build: "12500", feed: feed)
        let remote = try #require(try await Self.source(.before(Self.fusDate)).latestVersion(for: app))
        #expect(remote.version == "12500")
        #expect(remote.subscriptionHold == SubscriptionHold(
            version: "6.11.0", coveredBefore: Date(timeIntervalSince1970: TimeInterval(Self.fusDate))))
        let result = UpdateResult(app: app, remote: remote, status: UpdateChecker.evaluate(installed: app, remote: remote))
        #expect(!result.hasUpdate)
        #expect(result.heldBySubscription?.version == "6.11.0")
        // The withheld release's notes are not offered either.
        #expect(remote.structuredChangelog?.entries.contains { $0.version == "6.11.0" } != true)
    }

    /// A copy further back is still offered the newest release the window covers,
    /// as Surge's own updater would.
    @Test func newestCoveredReleaseIsOffered() async throws {
        let feed = try Self.feedFile()
        defer { try? FileManager.default.removeItem(at: feed) }
        let app = Self.app(short: "6.9.1", build: "12290", feed: feed)
        let remote = try #require(try await Self.source(.before(Self.fusDate)).latestVersion(for: app))
        #expect(remote.version == "12500")
        let result = UpdateResult(app: app, remote: remote, status: UpdateChecker.evaluate(installed: app, remote: remote))
        #expect(result.hasUpdate)
        #expect(result.heldBySubscription == nil)
    }

    /// An unreadable licence offers nothing newer and keeps the row's answer.
    @Test func unreadableWithholdsEveryNewerRelease() async throws {
        let feed = try Self.feedFile()
        defer { try? FileManager.default.removeItem(at: feed) }
        let app = Self.app(short: "6.9.1", build: "12290", feed: feed)
        let remote = try #require(try await Self.source(.unreadable).latestVersion(for: app))
        #expect(remote.version == "12290")
        #expect(remote.subscriptionHold == SubscriptionHold(version: "6.11.0", coveredBefore: nil))
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .upToDate)
    }

    /// A copy older than every release in the feed, none of them covered: the
    /// answer is still "nothing newer for you, and here is why" — never nil, which
    /// would read as "no source covers this app" and lose the lock with it.
    @Test(arguments: [SurgeSubscription.Window.unreadable, .before(1_700_000_000)])
    func everyReleaseWithheldStillAnswers(window: SurgeSubscription.Window) async throws {
        let feed = try Self.feedFile()
        defer { try? FileManager.default.removeItem(at: feed) }
        let app = Self.app(short: "6.9.0", build: "12200", feed: feed)
        let remote = try #require(try await Self.source(window).latestVersion(for: app))
        #expect(remote.version == "12200")
        #expect(remote.downloadURL == nil)
        #expect(remote.subscriptionHold?.version == "6.11.0")
        let result = UpdateResult(app: app, remote: remote, status: UpdateChecker.evaluate(installed: app, remote: remote))
        #expect(result.status == .upToDate)
        #expect(result.heldBySubscription?.version == "6.11.0")
        #expect(UpdatePolicy.laggingRemoteVersion(result) == nil)
    }

    /// A renewed window covers 6.11.0 again.
    @Test func renewedWindowOffersNewest() async throws {
        let feed = try Self.feedFile()
        defer { try? FileManager.default.removeItem(at: feed) }
        let app = Self.app(short: "6.10.0", build: "12500", feed: feed)
        let remote = try #require(try await Self.source(.before(1_823_698_109)).latestVersion(for: app))
        #expect(remote.version == "12560")
        #expect(remote.subscriptionHold == nil)
    }

    /// Only Surge is gated: the default resolver answers nil for anyone else.
    @Test func otherAppsAreNotGated() {
        let other = Self.app(short: "1", build: "1", feed: URL(fileURLWithPath: "/x"), bundleID: "com.example.other")
        #expect(SparkleAppcastSource.subscriptionWindow(for: other) == nil)
    }

    /// The recheck key changes for Surge only; every other bound app keys on its
    /// channel exactly as before.
    @Test func recheckFingerprintAddsTheWindowForSurgeOnly() {
        let fork = ForkChannel.bundleID
        #expect(ChannelSwitchDetector.recheckFingerprint(bundleID: fork)
            == ChannelSwitchDetector.fingerprint(of: ChannelBinding.resolve(bundleID: fork)))
        #expect(ChannelSwitchDetector.recheckFingerprint(bundleID: SurgeChannel.bundleID)
            .hasSuffix("|subscription=" + String(describing: SurgeSubscription.currentWindow())))
    }

    /// The hold takes the checkmark's place, and only there: an install in
    /// flight or a pending restart still outranks it, as they outrank `.upToDate`.
    @Test func actionLadderPutsTheLockWhereTheCheckmarkGoes() {
        let hold = SubscriptionHold(version: "6.11.0", coveredBefore: nil)
        #expect(RowAction.state(for: RowActionFacts(status: .upToDate, subscriptionHold: hold))
            == .subscriptionHold(hold))
        #expect(RowAction.state(for: RowActionFacts(status: .upToDate)) == .upToDate(channel: .none))
        #expect(RowAction.state(for: RowActionFacts(
            status: .upToDate, needsRestart: true, subscriptionHold: hold)) == .restartToApply)
    }
}
