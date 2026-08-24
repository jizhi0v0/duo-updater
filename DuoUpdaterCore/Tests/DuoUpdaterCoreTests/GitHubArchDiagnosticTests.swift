import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite(.serialized)
struct GitHubArchDiagnosticTests {
    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let body = """
            {
              "tag_name": "v2.0.0",
              "assets": [
                {
                  "name": "Example-2.0.0-x86_64.dmg",
                  "browser_download_url": "https://example.com/Example-2.0.0-x86_64.dmg",
                  "size": 42
                }
              ],
              "prerelease": false,
              "draft": false
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @Test func architectureOnlyMissIsSkippedByDiagnostics() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let source = GitHubReleasesSource(
            rules: [], session: URLSession(configuration: configuration))
        let rule = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            versionPattern: #"^v([0-9.]+)$"#,
            installAssetPattern: #"^Example-[0-9.]+-x86_64\.dmg$"#,
            installerKind: .dmg)

        let outcome = await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote == nil)
        #expect(outcome.failure?.classification == .notApplicable)
        #expect(outcome.failure?.kind == "notApplicable")
        #expect(outcome.bodySample == "v2.0.0")
    }
}
