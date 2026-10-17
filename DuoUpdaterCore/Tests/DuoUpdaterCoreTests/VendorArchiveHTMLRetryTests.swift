import Foundation
import Network
import Testing
@testable import DuoUpdaterCore

/// A vendor that answers part of its requests with its home page (corkmac.app:
/// HTTP 200, the site's HTML, for any URL including the zip) gets the archive
/// download retried instead of handing the page to the extractor.
struct VendorArchiveHTMLRetryTests {
    private func file(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("html-retry-\(UUID().uuidString)")
        try Data(bytes).write(to: url)
        return url
    }

    private func file(_ text: String) throws -> URL { try file(Array(text.utf8)) }

    @Test func recognisesAWebPageButNotAnArchive() throws {
        // The shape corkmac.app serves, and the other common openings.
        #expect(VendorInstaller.isHTMLDocument(at: try file("<!DOCTYPE html>\n<html lang=\"en\"><head><title>Cork: The Homebrew GUI</title>")))
        #expect(VendorInstaller.isHTMLDocument(at: try file("\n  <html><head><title>Index</title>")))
        #expect(VendorInstaller.isHTMLDocument(at: try file([0xEF, 0xBB, 0xBF] + Array("<!doctype HTML>".utf8))))
        // Archives: zip local header, gzip, and a disk image's leading zeros.
        #expect(!VendorInstaller.isHTMLDocument(at: try file([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])))
        #expect(!VendorInstaller.isHTMLDocument(at: try file([0x1F, 0x8B, 0x08, 0x00])))
        #expect(!VendorInstaller.isHTMLDocument(at: try file([UInt8](repeating: 0, count: 64))))
        // Not HTML just for mentioning it, and nothing to read is not HTML.
        #expect(!VendorInstaller.isHTMLDocument(at: try file("PK<html>")))
        #expect(!VendorInstaller.isHTMLDocument(at: try file([UInt8]())))
        #expect(!VendorInstaller.isHTMLDocument(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")))
    }

    @Test func aWebPageIsFetchedAgainAndDeleted() async throws {
        let page = try file("<!DOCTYPE html><title>Cork: …</title>")
        let zip = try file([0x50, 0x4B, 0x03, 0x04])
        var answers = [page, zip]
        var calls = 0
        let got = try await VendorInstaller.fetchArchive(maxAttempts: 4) {
            calls += 1
            return answers.removeFirst()
        }
        #expect(got == zip)
        #expect(calls == 2)
        #expect(!FileManager.default.fileExists(atPath: page.path))
    }

    @Test func givesUpAfterTheLastAttemptAndHandsBackThePage() async throws {
        var calls = 0
        var last: URL?
        let got = try await VendorInstaller.fetchArchive(maxAttempts: 4) {
            calls += 1
            last = try file("<!DOCTYPE html>")
            return last!
        }
        #expect(calls == 4)
        #expect(got == last)
        #expect(FileManager.default.fileExists(atPath: got.path))
    }

    @Test func oneAttemptMeansNoRetry() async throws {
        var calls = 0
        _ = try await VendorInstaller.fetchArchive(maxAttempts: 1) {
            calls += 1
            return try file("<!DOCTYPE html>")
        }
        #expect(calls == 1)
    }

    // MARK: - `duo verify-install`

    /// Loopback HTTP/1.1 server answering its Nth request with `bodies[N]` (the
    /// last one again once they run out), every one a 200 — the way corkmac.app
    /// answers its zip URL with its home page.
    private final class Server: @unchecked Sendable {
        private final class State: @unchecked Sendable {
            let lock = NSLock()
            var requests = 0
        }
        private let listener: NWListener
        private let queue = DispatchQueue(label: "VendorArchiveHTMLRetryTests.Server")
        private let state = State()
        let port: UInt16

        init(bodies: [Data]) throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let state = self.state
            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    let index = state.lock.withLock { () -> Int in
                        defer { state.requests += 1 }
                        return state.requests
                    }
                    let body = bodies[min(index, bodies.count - 1)]
                    let head = "HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\n"
                        + "Connection: close\r\n\r\n"
                    conn.send(content: Data(head.utf8) + body,
                              completion: .contentProcessed { _ in conn.cancel() })
                }
            }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 5) == .success,
                  let bound = listener.port?.rawValue
            else { throw URLError(.cannotConnectToHost) }
            self.port = bound
        }

        deinit { listener.cancel() }

        var url: URL { URL(string: "http://127.0.0.1:\(port)/RLS/2.0.3/Cork.zip")! }
        var requests: Int { state.lock.withLock { state.requests } }
    }

    /// `duo verify-install` reads the installer through `ArtifactInspection`,
    /// which downloaded once: corkmac.app's home page reached `ditto` and the
    /// sweep reported "Couldn't read PKZip signature" while one-click retried
    /// past it (#1372).
    ///
    /// Mutation: download once in `inspect` → `.failure` at `.unpack`, one request.
    @Test func verifyInstallFetchesAgainPastAWebPage() async throws {
        let dir = try DigestOnlyInstallTests.scratch("html-retry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("src/Cork.app"), signing: .sealed(identifier: nil))
        let zip = dir.appendingPathComponent("Cork.zip")
        try await DigestOnlyInstallTests.zip(app, to: zip)
        let page = Data("<!DOCTYPE html>\n<html lang=\"en\"><head><title>Cork</title>".utf8)
        let archive = try Data(contentsOf: zip)
        let server = try Server(bodies: [page, archive])

        let workDir = dir.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let remote = RemoteVersion(
            shortVersion: "2.0.0", version: nil, downloadURL: server.url,
            sourceName: "Vendor", vendorInstallerKind: .zip)
        let result = await ArtifactInspection.inspect(remote, bundleName: "Cork", workDir: workDir)

        #expect(server.requests == 2)
        switch result {
        case .success(let inspected):
            #expect(inspected.identity?.bundleIdentifier == DigestOnlyInstallTests.bundleID)
            #expect(inspected.bytes == Int64(page.count + archive.count))
        case .failure(let failure):
            Issue.record("\(failure.stage): \(failure.message)")
        }
    }
}
