import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite(.serialized)
struct HomebrewCaskCatalogTests {
    private final class DelayedFailureProtocol: URLProtocol, @unchecked Sendable {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0

            func increment() {
                lock.lock()
                value += 1
                lock.unlock()
            }

            var count: Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }

        static let counter = Counter()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.counter.increment()
            // Leave enough time for the second actor call to join the in-flight task.
            Thread.sleep(forTimeInterval: 0.1)
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }

        override func stopLoading() {}
    }

    private static func failingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedFailureProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func concurrentFailedRefreshServesStaleIndexToEveryCaller() async throws {
        let entry = CaskEntry(
            token: "fixture", version: "2.0", url: nil,
            autoUpdates: false, isPkg: false)
        let index = CaskIndex(
            byAppFilename: ["fixture.app": entry],
            byBundleID: ["com.example.fixture": entry])
        let before = DelayedFailureProtocol.counter.count
        let catalog = HomebrewCaskCatalog(
            session: Self.failingSession(),
            staleTestIndex: index,
            loadedAt: Date().addingTimeInterval(-HomebrewCaskCatalog.indexTTL - 1))

        async let byName = catalog.entry(forAppFilename: "Fixture.app")
        async let byID = catalog.entry(forBundleID: "com.example.fixture")
        let (nameResult, idResult) = try await (byName, byID)

        #expect(nameResult?.token == "fixture")
        #expect(idResult?.token == "fixture")
        #expect(DelayedFailureProtocol.counter.count - before == 1)

        // The failure backoff serves stale data without immediately downloading the
        // full catalog again for the next app in the same check.
        let third = try await catalog.entry(forAppFilename: "Fixture.app")
        #expect(third?.token == "fixture")
        #expect(DelayedFailureProtocol.counter.count - before == 1)
    }
}
