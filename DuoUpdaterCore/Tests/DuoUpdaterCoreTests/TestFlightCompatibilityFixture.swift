import Foundation
@testable import DuoUpdaterCore

/// Gives the platform/membership tests a compatible API response for their exact
/// beta, without reading the host's session cache or contacting Apple.
enum TestFlightCompatibilityFixture {
    static func client(for build: TestFlightCompatibility.Build) -> TestFlightCompatibility {
        let body = try! JSONSerialization.data(withJSONObject: ["data": [
            "bundleId": build.bundleID, "builds": [[
                "id": build.buildID, "bundleId": build.bundleID, "platform": build.platform,
                "cfBundleShortVersion": build.shortVersion, "cfBundleVersion": build.version, "compatible": true
            ]]
        ]])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Server.self]
        return TestFlightCompatibility(session: URLSession(configuration: config), credentials: {
            .init(accountID: "11111111-1111-4111-8111-111111111111",
                  headers: ["X-Fixture-Response": body.base64EncodedString()])
        })
    }

    private final class Server: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let encoded = request.value(forHTTPHeaderField: "X-Fixture-Response"),
                  let data = Data(base64Encoded: encoded) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
