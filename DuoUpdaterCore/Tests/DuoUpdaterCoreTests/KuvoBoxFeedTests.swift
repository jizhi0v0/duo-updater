import Foundation
import Testing
@testable import DuoUpdaterCore

struct KuvoBoxFeedTests {
    private static let oldFeed = "https://github.com/serhatandic/kuvo/releases/latest/download/appcast.xml"
    private static let boxFeed = "https://github.com/serhatandic/box/releases/latest/download/appcast.xml"
    private static let signature = "XlVrea/0KSmui0Pi3njHy7E+zTLJ8HS0II+r5W/A1goWiOXMec/B9uKcumlHNx7j70ke+GlzlZwHfhWJdKU/DA=="

    private func bundle(id: String, feed: String) throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-Kuvo-\(UUID().uuidString).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": id, "CFBundleName": "Kuvo",
                     "CFBundleShortVersionString": "0.1.2", "CFBundleVersion": "0.1.2", "SUFeedURL": feed]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    @Test func theScannerMovesOnlyTheDockerProductsOldFeed() throws {
        let scanner = AppScanner(testflight: TestFlightInventory(macRows: []))
        for (id, feed, expected) in [
            ("run.kuvo.app", Self.oldFeed, Self.boxFeed),
            ("run.kuvo.code", Self.oldFeed, Self.oldFeed),
            ("run.kuvo.app", "https://example.com/custom.xml", "https://example.com/custom.xml"),
        ] {
            let path = try bundle(id: id, feed: feed)
            defer { try? FileManager.default.removeItem(at: path) }
            let app = try #require(scanner.readApp(at: path))
            #expect(app.sparkleFeedURL?.absoluteString == expected)
            #expect(app.recipeBundleID == id)
        }
    }

    /// The real Box feed still names the old repository in its enclosure. A
    /// corrected feed alone would detect 0.1.3 but download a 404 on Update.
    @Test func theBoxOfferKeepsItsVersionAndSignatureWithTheRelocatedDownload() async throws {
        let path = try bundle(id: "run.kuvo.app", feed: Self.oldFeed)
        defer { try? FileManager.default.removeItem(at: path) }
        let scanner = AppScanner(testflight: TestFlightInventory(macRows: []))
        let app = try #require(scanner.readApp(at: path))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoxFeedProtocol.self]
        let source = SparkleAppcastSource(session: URLSession(configuration: configuration))
        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "0.1.3")
        #expect(remote.downloadURL?.absoluteString
            == "https://github.com/serhatandic/box/releases/download/v0.1.3/Kuvo.dmg")
        #expect(remote.edSignature == Self.signature)
        #expect(remote.downloadSize == 3_659_402)
        #expect(remote.minimumSystemVersion == "15.0")
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .updateAvailable(latest: "0.1.3"))
        let reading = try await source.readFeed(URL(string: Self.boxFeed)!, bundleID: "run.kuvo.app")
        guard case .success(let feed) = reading else {
            Issue.record("the feed verification path did not read the Box feed")
            return
        }
        #expect(feed.headEnclosure == remote.downloadURL)
    }

    @Test func onlyTheRecordedRepositorysReleaseLinksMove() {
        let feed = URL(string: Self.boxFeed)!
        for path in ["download/v0.1.3/Kuvo.dmg?download=1", "tag/v0.1.3"] {
            let old = URL(string: "https://github.com/serhatandic/kuvo/releases/\(path)")!
            #expect(SparkleFeedCatalog.relocatedReleaseURL(old, forBundleID: "run.kuvo.app", feedURL: feed)
                .absoluteString == "https://github.com/serhatandic/box/releases/\(path)")
        }
        for raw in [
            "https://github.com/serhatandic/box/releases/download/v0.1.3/Kuvo.dmg",
            "https://github.com/serhatandic/kuvo-code/releases/download/v0.7.2/KuvoCode.dmg",
            "https://github.com/serhatandic/kuvo-fork/releases/download/v0.1.3/Kuvo.dmg",
            "https://github.com/another/kuvo/releases/download/v0.1.3/Kuvo.dmg",
            "https://github.com/serhatandic/kuvo/issues/1",
            "https://example.com/serhatandic/kuvo/releases/download/v0.1.3/Kuvo.dmg",
            "http://github.com/serhatandic/kuvo/releases/download/v0.1.3/Kuvo.dmg",
            "https://github.com:8443/serhatandic/kuvo/releases/download/v0.1.3/Kuvo.dmg",
            "https://user@github.com/serhatandic/kuvo/releases/download/v0.1.3/Kuvo.dmg",
        ] {
            let url = URL(string: raw)!
            #expect(SparkleFeedCatalog.relocatedReleaseURL(url, forBundleID: "run.kuvo.app", feedURL: feed) == url)
        }
        let old = URL(string: "https://github.com/serhatandic/kuvo/releases/download/v0.1.3/Kuvo.dmg")!
        for id in ["run.kuvo.code", "com.example.other", nil] {
            #expect(SparkleFeedCatalog.relocatedReleaseURL(old, forBundleID: id, feedURL: feed) == old)
        }
        for otherFeed in [Self.oldFeed, "https://example.com/custom.xml"] {
            #expect(SparkleFeedCatalog.relocatedReleaseURL(old, forBundleID: "run.kuvo.app",
                feedURL: URL(string: otherFeed)!) == old)
        }
    }

    @Test func boxAndCodeCannotReplaceOneAnotherEvenWithTheirSharedSigningTeam() {
        for (installed, downloaded) in [("run.kuvo.app", "run.kuvo.code"), ("run.kuvo.code", "run.kuvo.app")] {
            #expect(BundleIDMigration.migration(installed: installed, downloaded: downloaded,
                installedVersion: "0.1.2", installedTeam: "C8Y523R7T5", downloadedTeam: "C8Y523R7T5") == nil)
        }
    }

    private final class BoxFeedProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let xml = """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel><title>Kuvo</title><item>
                <sparkle:version>0.1.3</sparkle:version>
                <sparkle:shortVersionString>0.1.3</sparkle:shortVersionString>
                <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
                <enclosure url="https://github.com/serhatandic/kuvo/releases/download/v0.1.3/Kuvo.dmg"
                  sparkle:edSignature="\(KuvoBoxFeedTests.signature)" length="3659402" type="application/octet-stream"/>
              </item></channel>
            </rss>
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(xml.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
