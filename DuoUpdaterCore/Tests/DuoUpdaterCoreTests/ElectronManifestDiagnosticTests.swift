import Foundation
import Testing
@testable import DuoUpdaterCore

struct ElectronManifestDiagnosticTests {
    private final class ManifestProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!
            if url.path.contains("offline") {
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                return
            }
            let body: String
            if url.path.contains("malformed") {
                body = "<html>not an update manifest; token=private-value</html>"
            } else if url.path.contains("version-only") {
                body = "version: 1.2.3\n"
            } else {
                body = """
                    version: 1.2.3
                    files:
                      - url: App-arm64.zip
                        sha512: ZIPSHA==
                        size: 123
                    """
            }
            let response = HTTPURLResponse(
                url: url, statusCode: url.path.contains("missing") ? 404 : 200,
                httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func source() -> ElectronManifestSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ManifestProtocol.self]
        return ElectronManifestSource(session: URLSession(configuration: config))
    }

    private func app(_ route: String) -> InstalledApp {
        InstalledApp(
            name: "Manifest fixture", bundleID: "com.example.\(route)",
            shortVersion: "1.0.0", buildVersion: "1.0.0",
            path: URL(fileURLWithPath: "/nonexistent/Manifest.app"), isMASApp: false,
            sparkleFeedURL: nil,
            electronUpdate: ElectronUpdateConfig(
                provider: "generic", url: "https://electron.example/\(route)",
                owner: nil, repo: nil, channel: "latest"))
    }

    @Test func aSuccessfulDiagnosticIsTheInteractiveSourcesOwnOffer() async throws {
        let source = source()
        let app = app("good")
        let diagnostic = await source.probeDiagnostic(for: app)
        let interactive = try await source.latestVersion(for: app)
        #expect(diagnostic.remote == interactive)
        #expect(diagnostic.remote?.downloadURL?.absoluteString
                == "https://electron.example/good/App-arm64.zip")
        #expect(diagnostic.remote?.expectedSHA512 == "ZIPSHA==")
        #expect(diagnostic.failure == nil)
        #expect(diagnostic.httpStatus == 200)
    }

    @Test func transportAndPermanentHTTPFailuresStayDistinguishable() async throws {
        let source = source()
        let missing = await source.probeDiagnostic(for: app("missing"))
        #expect(missing.failure == .httpStatus(404))
        #expect(missing.httpStatus == 404)
        let offline = await source.probeDiagnostic(for: app("offline"))
        if case .transport(let code, _) = offline.failure {
            #expect(code == URLError.timedOut.rawValue)
        } else {
            Issue.record("a failed request must retain its transport failure")
        }
        // The generic UI path still degrades rather than creating an error row.
        #expect(try await source.latestVersion(for: app("missing")) == nil)
    }

    @Test func aMalformedManifestDoesNotBecomeAnUnexplainedNilOrExposeItsBody() async {
        let answer = await source().probeDiagnostic(for: app("malformed"))
        #expect(answer.remote == nil)
        #expect(answer.httpStatus == 200)
        if case .versionPatternNoMatch = answer.failure {} else {
            Issue.record("an invalid manifest must be an observable parse failure")
        }
        #expect(answer.bodySample == nil)
    }

    @Test func aDetectionOnlyManifestRetainsItsVersionWithoutInventingAnInstaller() async {
        let answer = await source().probeDiagnostic(for: app("version-only"))
        #expect(answer.remote?.shortVersion == "1.2.3")
        #expect(answer.remote?.downloadURL == nil)
        #expect(answer.failure == nil)
    }
}
