import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// Why `URLSession.updates` has no disk cache, pinned so nobody restores one.
///
/// The tree used to carry a `willCacheResponse` guard plus a comment saying
/// credential-bearing responses were "excluded from the cache entirely". They were
/// not: 85 cached request blobs holding a live GitHub PAT in plaintext were found
/// under `~/Library/Caches` on 2026-08-22. The guard was never wrong about *what*
/// to refuse — it was never asked. `NSURLSession.h` on `NSURLSessionDataDelegate`:
/// "If you create a task using a method that takes a completion handler block, the
/// delegate methods for response and data delivery are not called."
/// `willCacheResponse` is one of those, and `data(for:)` is that path.
///
/// So the protection has to be structural, and these two tests are the pair that
/// says so: the first shows the delegate route is a dead end, the second shows the
/// route actually taken.
@Suite(.serialized)
struct CredentialCacheDelegateBypassTests {

    /// Loopback HTTP/1.1 server returning one small, explicitly cacheable body —
    /// the conditions `URLCache` needs to store a response at all (200, HTTP,
    /// `Cache-Control` allowing reuse, small enough for the capacity).
    ///
    /// Dedicated serial queue for the Network.framework callbacks, matching
    /// `FeedRevalidationTests` and `DownloaderTrafficTests`.
    private final class CacheableHTTPServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "CacheableHTTPServer")
        let port: UInt16

        init() throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    let body = Data("<rss><item>Feedy_v1.0.0_mac.dmg</item></rss>".utf8)
                    var header = "HTTP/1.1 200 OK\r\n"
                    header += "Content-Type: application/xml\r\n"
                    header += "Content-Length: \(body.count)\r\n"
                    header += "Cache-Control: max-age=3600\r\n"
                    header += "Connection: close\r\n\r\n"
                    conn.send(
                        content: Data(header.utf8) + body,
                        completion: .contentProcessed { _ in conn.cancel() })
                }
            }
            listener.start(queue: queue)

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

    /// Counts `willCacheResponse` calls and never vetoes, so the assertion is about
    /// reachability alone.
    private final class CacheDelegateRecorder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var calls: Int { lock.lock(); defer { lock.unlock() }; return value }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            willCacheResponse proposedResponse: CachedURLResponse,
            completionHandler: @escaping (CachedURLResponse?) -> Void
        ) {
            lock.lock(); value += 1; lock.unlock()
            completionHandler(proposedResponse)
        }
    }

    /// The finding itself. The response *is* cached — so a veto would have had
    /// something to veto — and the delegate still never hears about it. Holds for
    /// the per-task delegate too, so `data(for:delegate:)` is no escape hatch.
    @Test func willCacheResponseIsNeverCalledForAsyncDataFor() async throws {
        let server = try CacheableHTTPServer()
        defer { server.stop() }

        let recorder = CacheDelegateRecorder()
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        let session = URLSession(configuration: config, delegate: recorder, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/appcast.xml")!)
        _ = try await session.data(for: request, delegate: recorder)
        // The delegate queue is serial and separate; give it room to be wrong.
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(recorder.calls == 0, "delegate became reachable — re-check the disk-cache decision")
        #expect(config.urlCache?.cachedResponse(for: request) != nil,
                "response was not cached at all, so the call count proves nothing")
    }

    /// The contrast that makes the bypass a *bypass* rather than a broken delegate:
    /// the same recorder on the same kind of session hears the call when the task is
    /// delegate-driven — `dataTask(with:)` with no completion handler, which is how
    /// `Downloader` runs every installer fetch. So the guard kept there is live code,
    /// and the one on `URLSession.updates` is not.
    @Test func willCacheResponseIsCalledForADelegateDrivenDataTask() async throws {
        let server = try CacheableHTTPServer()
        defer { server.stop() }

        let recorder = CacheDelegateRecorder()
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        let session = URLSession(configuration: config, delegate: recorder, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let url = URL(string: "http://127.0.0.1:\(server.port)/appcast.xml")!
        session.dataTask(with: URLRequest(url: url)).resume()
        for _ in 0..<50 where recorder.calls == 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(recorder.calls == 1)
    }

    /// The protection that replaced it. A credentialed request through the real
    /// session must leave nothing on disk — asserted on the cache's own accounting
    /// rather than on the configuration, so it fails if a disk store appears by any
    /// route.
    @Test func credentialedRequestOnUpdatesSessionWritesNothingToDisk() async throws {
        let server = try CacheableHTTPServer()
        defer { server.stop() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/appcast.xml")!)
        request.setValue("Bearer ghp_notARealToken", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.updates.data(for: request)
        try await Task.sleep(nanoseconds: 300_000_000)

        let cache = URLSession.updates.configuration.urlCache
        #expect(cache?.diskCapacity == 0)
        #expect(cache?.currentDiskUsage == 0)
    }
}
