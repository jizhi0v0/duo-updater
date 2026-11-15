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
            let body = url.path.contains("malformed") ? "not an appcast; token=secret" : """
            <?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
            <sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
            <enclosure url="https://example.com/App.zip" sparkle:edSignature="sig" length="10"/>
            </item></channel></rss>
            """
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
}
