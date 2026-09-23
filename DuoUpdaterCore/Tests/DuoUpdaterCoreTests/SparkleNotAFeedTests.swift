import Testing
import Foundation
@testable import DuoUpdaterCore

/// A feed URL that answers with a web page is a failed check, not "no source".
///
/// Muse (`com.meta.endo`) points `SUFeedURL` at facebook.com, which answers most
/// requests with a 302 to `/login` — 13 real appcasts out of 189 of the menu-bar
/// app's fetches in one machine's request ledger, the ~16 hours from 2026-09-22
/// 12:43Z to 09-23 04:16Z. `URLSession` follows the redirect and hands back
/// a 200 HTML page with zero `<item>`s. Returned as `nil`, that was `.unknown`, so
/// the Update click's re-check replaced the row with one carrying no offer and the
/// row vanished. Thrown, it is `.error` — see `PreInstallGate.cannotConfirm`.
@Suite struct SparkleNotAFeedTests {

    private static let app = InstalledApp(
        name: "Subject", bundleID: "com.example.subject", shortVersion: "1.0",
        buildVersion: "100", path: URL(fileURLWithPath: "/Applications/Subject.app"),
        isMASApp: false, sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))

    private static func source(_ proto: AnyClass) -> SparkleAppcastSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [proto]
        return SparkleAppcastSource(session: URLSession(configuration: config))
    }

    /// Mutation: drop the `items.isEmpty, isHTML` throw in `latestVersion` → red.
    @Test func aLoginPageInPlaceOfTheFeedThrows() async {
        do {
            let remote = try await Self.source(LoginPageProtocol.self).latestVersion(for: Self.app)
            Issue.record("expected SparkleError.notAFeed, got \(String(describing: remote))")
        } catch let error as SparkleAppcastSource.SparkleError {
            guard case .notAFeed = error else { Issue.record("wrong case: \(error)"); return }
            #expect(error.errorDescription?.contains("web page") == true)
        } catch {
            Issue.record("expected SparkleError.notAFeed, got \(error)")
        }
    }

    /// End to end through the checker: the row must come back `.error`, the status
    /// the pre-install gate reads as "could not confirm", not `.unknown`.
    @Test func theCheckerReportsItAsAnError() async {
        let checker = UpdateChecker(sources: [Self.source(LoginPageProtocol.self)])
        let result = await checker.check(Self.app)
        guard case .error = result.status else {
            Issue.record("expected .error, got \(result.status)")
            return
        }
    }

    /// The guard's other half: a real feed with no items is still an answer of
    /// nothing, not a failure. Mutation: throw on `items.isEmpty` alone → red.
    @Test func anEmptyRealFeedIsStillNil() async throws {
        let remote = try await Self.source(EmptyFeedProtocol.self).latestVersion(for: Self.app)
        #expect(remote == nil)
    }

    private final class LoginPageProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com/login/?next=%2Fappcast.xml")!,
                statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=\"utf-8\""])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(
                "<!DOCTYPE html><html><head><title>Log in</title></head><body><form></form></body></html>".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private final class EmptyFeedProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("""
                <?xml version="1.0" encoding="utf-8"?>
                <rss version="2.0"><channel><title>Subject</title></channel></rss>
                """.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
