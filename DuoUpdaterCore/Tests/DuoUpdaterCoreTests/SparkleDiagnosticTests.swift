import Foundation
import Testing
@testable import DuoUpdaterCore

struct SparkleDiagnosticTests {
    private final class FeedProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!
            if url.path.contains("offline") {
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
            }
            let status = url.path.contains("missing") ? 404 : url.path.contains("busy") ? 503 : 200
            let body = if url.path.hasSuffix("versionCheck.cgi") {
                """
                <?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                <sparkle:version>4.6.1</sparkle:version><sparkle:minimumSystemVersion>14.4</sparkle:minimumSystemVersion>
                <enclosure url="https://rogueamoeba.com/audiohijack/download.php"/>
                </item></channel></rss>
                """
            } else if url.path.hasSuffix("acorn8update.xml") {
                """
                <?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                <sparkle:minimumSystemVersion>$(MACOSX_DEPLOYMENT_TARGET)</sparkle:minimumSystemVersion>
                <enclosure sparkle:version="18029" sparkle:shortVersionString="8.7.3"
                  url="https://s3.amazonaws.com/flyingmeat/Acorn8.zip" length="0"/>
                </item></channel></rss>
                """
            } else if url.path.contains("malformed") {
                "not an appcast; token=secret"
            } else {
                """
                <?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                <sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
                <enclosure url="https://example.com/App.zip" sparkle:edSignature="sig" length="10"/>
                </item></channel></rss>
                """
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status,
                  httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/xml"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    private func source() -> SparkleAppcastSource {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FeedProtocol.self]
        return SparkleAppcastSource(session: URLSession(configuration: config))
    }
    private func app(_ path: String) -> InstalledApp {
        InstalledApp(name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1", buildVersion: "1",
                     path: URL(fileURLWithPath: "/nonexistent/Fixture.app"), isMASApp: false,
                     sparkleFeedURL: URL(string: "https://feed.example/\(path)"))
    }
    @Test func successfulDiagnosticUsesProductionOfferAndIntegrityFields() async throws {
        let source = source(), app = app("good")
        let answer = await source.probeDiagnostic(for: app)
        #expect(answer.remote == (try await source.latestVersion(for: app)))
        #expect(answer.remote?.edSignature == "sig" && answer.remote?.version == "200")
        #expect(answer.bodySample == nil && answer.failure == nil)
    }
    @Test func noAnswerCannotLookLikeACleanFeed() async {
        let source = source()
        #expect(await source.probeDiagnostic(for: app("missing")).failure == .httpStatus(404))
        #expect(await source.probeDiagnostic(for: app("busy")).failure?.classification == .infra)
        #expect(await source.probeDiagnostic(for: app("offline")).failure?.classification == .infra)
        let malformed = await source.probeDiagnostic(for: app("malformed"))
        #expect(malformed.failure?.classification == .recipe && malformed.bodySample == nil)
    }

    @Test func audioHijackOffersTheFeedEnclosureWithBuildVerification() async throws {
        let bundleID = "com.rogueamoeba.audiohijack"
        let feed = try #require(SparkleFeedCatalog.feed(forBundleID: bundleID))
        let app = InstalledApp(name: "Audio Hijack", bundleID: bundleID,
                               shortVersion: "4.6.0", buildVersion: "4.6.0",
                               path: URL(fileURLWithPath: "/nonexistent/Audio Hijack.app"),
                               isMASApp: false, sparkleFeedURL: feed)
        let source = source()
        let remote = try #require(try await source.latestVersion(for: app))
        #expect(remote.downloadURL?.absoluteString == "https://rogueamoeba.com/audiohijack/download.php")
        #expect(remote.downloadHeaders["User-Agent"] == "DuoUpdater/0.1 Sparkle")
        #expect(remote.version == "4.6.1")
        #expect(remote.requiresMatchingSparkleBuild)
        let reading = try await source.readFeed(feed, bundleID: bundleID).get()
        #expect(reading.headEnclosure == remote.downloadURL)
        #expect(reading.headDownloadHeaders == remote.downloadHeaders)
    }

    @Test func acornOffersTheRollingArchiveWithAnExactBuildCheck() async throws {
        let acorn = com_flyingmeat_Acorn8.self
        let source = source()
        let cases = [
            (acorn.bundleID, acorn.stableFeed, true),
            (acorn.bundleID, acorn.betaFeed, true),
            (acorn.bundleID, URL(string: "https://flyingmeat.com/other/acorn8update.xml")!, false),
            ("com.example.OtherApp", acorn.stableFeed, false),
        ]
        for (bundleID, feed, requiresMatch) in cases {
            let app = InstalledApp(name: "Acorn", bundleID: bundleID,
                                   shortVersion: "8.7.2", buildVersion: "18025",
                                   path: URL(fileURLWithPath: "/nonexistent/Acorn.app"),
                                   isMASApp: false, sparkleFeedURL: feed)
            let remote = try #require(try await source.latestVersion(for: app))
            #expect(remote.downloadURL?.absoluteString == "https://s3.amazonaws.com/flyingmeat/Acorn8.zip")
            #expect(remote.version == "18029")
            #expect(remote.requiresMatchingSparkleBuild == requiresMatch)
            #expect(remote.downloadHeaders.isEmpty)
        }
    }
}
