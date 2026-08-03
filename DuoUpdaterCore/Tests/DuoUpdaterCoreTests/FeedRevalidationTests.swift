import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// A version feed must never be answered from cache without asking the server.
///
/// The failure this pins is silent by construction: the probe *succeeds*, returns
/// the version from a stale cached body, and the row reads "up to date" with no
/// error logged anywhere. It shipped twice — Fork's appcast (a ~10-year
/// `Cache-Control: max-age`) and OrbStack's (no `Cache-Control` at all, so
/// `URLCache` applied *heuristic* freshness derived from `Last-Modified` and
/// served 2.2.1 for days while 2.2.2 was live).
///
/// The regression here is the second, nastier shape: a response with validators
/// but no explicit freshness. Under the default `.useProtocolCachePolicy` the
/// second probe never leaves the process; with
/// `URLRequest.versionFeedCachePolicy` it sends a conditional GET and sees the
/// new release.
@Suite(.serialized)
struct FeedRevalidationTests {

    /// Loopback HTTP/1.1 server that serves a *different* body to each successive
    /// request, so "did the client actually ask again?" is observable from the
    /// answer alone. Cache-relevant headers mirror the real OrbStack CDN:
    /// `ETag` + a `Last-Modified` far enough in the past that heuristic freshness
    /// (~10% of document age) covers any plausible test duration — i.e. a client
    /// that trusts freshness will NOT re-request.
    ///
    /// Dedicated serial queue for all Network.framework callbacks, for the same
    /// starvation reason documented in `DownloaderTrafficTests`.
    private final class SequenceHTTPServer: @unchecked Sendable {
        private let listener: NWListener
        private let bodies: [String]
        private let queue = DispatchQueue(label: "SequenceHTTPServer")
        private let counter = Counter()
        let port: UInt16

        /// Request count, so the test can assert the second probe hit the network.
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
            var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        }

        var requestCount: Int { counter.count }

        init(bodies: [String]) throws {
            self.bodies = bodies
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let counter = self.counter

            // Set before start so the very first connection is served.
            listener.newConnectionHandler = { [bodies] conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    let n = counter.next()
                    let body = Data(bodies[min(n, bodies.count) - 1].utf8)
                    var header = "HTTP/1.1 200 OK\r\n"
                    header += "Content-Type: application/xml\r\n"
                    header += "Content-Length: \(body.count)\r\n"
                    // Validators but NO Cache-Control — the OrbStack shape.
                    header += "ETag: \"rev-\(n)\"\r\n"
                    header += "Last-Modified: Thu, 01 Jan 2015 00:00:00 GMT\r\n"
                    header += "Connection: close\r\n\r\n"
                    conn.send(
                        content: Data(header.utf8) + body,
                        completion: .contentProcessed { _ in conn.cancel() })
                }
            }
            listener.start(queue: queue)

            // Spin until the OS assigns a concrete port. `port` reads back as 0
            // until then, and dialing 0 fails instantly rather than connecting.
            var resolved: UInt16?
            for _ in 0..<500 {
                if let p = listener.port?.rawValue, p != 0 { resolved = p; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let bound = resolved else { throw URLError(.cannotConnectToHost) }
            self.port = bound
        }

        func stop() { listener.cancel() }
    }

    /// A session shaped like `URLSession.updates`: private on-disk-capable
    /// `URLCache`, default request policy. The cache is what makes the bug
    /// possible, so the test must have one.
    private static func cachingSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }

    private static func app(bundleID: String, version: String) -> InstalledApp {
        InstalledApp(
            name: "Feedy", bundleID: bundleID,
            shortVersion: version, buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/Feedy.app"),
            isMASApp: false, sparkleFeedURL: nil)
    }

    /// The regression: probe twice against a feed that changed in between. Without
    /// `versionFeedCachePolicy` the second probe is served from cache and still
    /// reports 1.0.0 — the OrbStack 2.2.1→2.2.2 blind spot.
    @Test func vendorProbeRefetchesFeedThatChangedDespiteCacheFreshness() async throws {
        let server = try SequenceHTTPServer(bodies: [
            "<rss><item>Feedy_v1.0.0_mac.dmg</item></rss>",
            "<rss><item>Feedy_v2.0.0_mac.dmg</item></rss>",
        ])
        defer { server.stop() }

        let bundleID = "com.example.feedy"
        let recipe = VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string: "http://127.0.0.1:\(server.port)/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"Feedy_v([0-9.]+)_mac\.dmg"#)
        let source = VendorProbeSource(recipes: [recipe], session: Self.cachingSession())

        let first = try await source.latestVersion(for: Self.app(bundleID: bundleID, version: "1.0.0"))
        #expect(first?.shortVersion == "1.0.0")

        let second = try await source.latestVersion(for: Self.app(bundleID: bundleID, version: "1.0.0"))
        #expect(second?.shortVersion == "2.0.0")
        // Belt and braces: the second answer came from a real second request.
        #expect(server.requestCount == 2)
    }

    /// Every source that reads a version feed must opt in — this is the thing that
    /// was true of exactly one source (Sparkle) while the rest silently cached.
    /// Cheap source-level guard so a new source added later doesn't quietly
    /// reintroduce the default policy.
    @Test func everyVersionFeedSourceSetsTheCachePolicy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DuoUpdaterCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DuoUpdaterCore
            .appendingPathComponent("Sources/DuoUpdaterCore/Sources")

        // Sources that fetch a mutable "what is the latest version" document.
        let feedSources = [
            "SparkleAppcastSource.swift", "VendorProbeSource.swift",
            "GitHubReleasesSource.swift", "MacAppStoreSource.swift",
            "ToolboxSource.swift", "AlcoveUpdateSource.swift",
            "HomebrewCaskCatalog.swift", "ChangelogService.swift",
        ]
        for file in feedSources {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            // Count GET-able request builders vs. policy assignments. A POST
            // (Alcove's issue-token) is never cached, so allow policy count < requests.
            #expect(
                text.contains("URLRequest.versionFeedCachePolicy"),
                "\(file) builds a version-feed request without versionFeedCachePolicy")
        }
    }
}

