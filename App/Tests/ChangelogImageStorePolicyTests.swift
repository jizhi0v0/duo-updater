import AppKit
import Foundation
import Network
import Testing
import DuoUpdaterCore

/// A changelog image is fetched on its own, in the background, as soon as the notes
/// are prewarmed: nobody clicked anything. The URL comes out of a vendor's page, so
/// `ImageStore.data(for:)` holds it to `ChangelogURLPolicy` like the web view does
/// and does not request what the policy refuses, however a scraper got hold of it.
///
/// The loopback server is the probe: it is reachable (the app carries no ATS
/// exception, so loopback `http://` loads), so a request that reaches it proves
/// the gate let the URL through.
@Suite(.serialized)
struct ChangelogImageStorePolicyTests {

    /// Answers every request with a PNG and counts them.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "ChangelogImageStorePolicyTests.Server")
        private let lock = NSLock()
        private var _hits = 0
        private var _port: UInt16 = 0
        var port: UInt16 { lock.withLock { _port } }
        var hits: Int { lock.withLock { _hits } }

        init(png: Data) throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: self?.queue ?? .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    self?.countHit()
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(png.count)\r\n"
                        + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
                    conn.send(content: Data(header.utf8) + png,
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
            lock.withLock { _port = bound }
        }

        func stop() { listener.cancel() }

        private func countHit() { lock.withLock { _hits += 1 } }
    }

    private static func pngData() throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ChangelogImageStorePolicyTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// An `http://` loopback URL is what the policy refuses (not https, an IP
    /// literal, a non-standard port), so it is not requested and nothing is cached.
    @Test func aURLThePolicyRefusesIsNotRequested() async throws {
        let server = try Server(png: try Self.pngData())
        defer { server.stop() }
        let directory = Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ImageStore(directory: directory)

        let url = URL(string: "http://127.0.0.1:\(server.port)/screenshot.png")!
        #expect(!ChangelogURLPolicy.isDisplayable(url), "premise: the policy refuses this URL")

        let data = await store.data(for: url)

        #expect(data == nil)
        #expect(server.hits == 0, "the server was asked for the image \(server.hits) time(s)")
        let cached = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(cached.isEmpty, "nothing is written for a refused URL: \(cached)")
    }
}
