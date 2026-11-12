import Foundation
import Testing
@testable import DuoUpdaterCore

/// Characterization of Downloader itself, separate from version-feed retries and
/// the install-failure ledger. Every successful result is checked byte-for-byte;
/// every rejected HTTP response must leave no finalized file or kept error page.
struct HTTPDownloadStatusSimulationTests {
    private static let payload = Data([0x44, 0x55, 0x4f, 0x00, 0x01, 0xff])
    private static let errorPage = Data("<html>simulation: access denied</html>".utf8)

    private func withSimulation(
        _ steps: [HTTPDownloadSimulation.Step],
        operation: (HTTPDownloadSimulation) async throws -> Void
    ) async throws {
        let simulation = try HTTPDownloadSimulation(steps)
        do {
            try await operation(simulation)
            #expect(simulation.script.unexpectedRequests.isEmpty)
            #expect(simulation.script.remaining == 0, "A scripted response was never requested")
            try await simulation.close()
        } catch {
            try await simulation.close()
            throw error
        }
    }

    private func expectHTTPStatus(
        _ expected: Int, operation: () async throws -> URL
    ) async {
        do {
            let file = try await operation()
            Issue.record("HTTP \(expected) unexpectedly finalized \(file.lastPathComponent)")
        } catch let error as Downloader.DownloadError {
            guard case .httpStatus(let actual) = error else {
                Issue.record("Expected httpStatus(\(expected)), got \(error)")
                return
            }
            #expect(actual == expected)
        } catch {
            Issue.record("Expected httpStatus(\(expected)), got \(error)")
        }
    }

    @Test func fresh200PreservesPayloadAndCallerHeaders() async throws {
        try await withSimulation([.response(200, body: Self.payload)]) { simulation in
            let file = try await simulation.download(headers: [
                "Authorization": "Bearer simulation-only", "Cookie": "simulation=only",
                "Proxy-Authorization": "Basic simulation-only",
            ])
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(file.deletingLastPathComponent() == simulation.sandbox.destination)
            #expect(simulation.sandbox.downloader.bytesDownloaded == Int64(Self.payload.count))
            #expect(try simulation.sandbox.destinationFiles == [file.lastPathComponent])
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
            let requests = simulation.script.requests
            #expect(requests.count == 1)
            let request = try #require(requests.first)
            #expect(request.attempt == 1)
            #expect(request.method == "GET")
            #expect(request.url == simulation.url)
            #expect(request.range == nil)
            #expect(request.ifRange == nil)
            #expect(request.authorization == "Bearer simulation-only")
            #expect(request.cookie == "simulation=only")
            #expect(request.proxyAuthorization == "Basic simulation-only")
        }
    }

    @Test func freshComplete206IsAcceptedWithoutARangeRequest() async throws {
        try await withSimulation([.response(206, headers: ["Content-Range": "bytes 0-5/6"], body: Self.payload)]) { simulation in
            let file = try await simulation.download()
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(simulation.script.requests.count == 1)
            #expect(simulation.script.requests.first?.range == nil)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    /// Current behavior: only 200 and usable 206 are accepted. This intentionally
    /// records rejection of other successful statuses without calling it a policy
    /// requirement. 3xx here are final responses, not simulated redirect callbacks.
    @Test(arguments: [
        201, 202, 203, 204, 205, 207, 208, 226,
        300, 301, 302, 303, 304, 305, 306, 307, 308,
        400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413,
        414, 415, 416, 417, 418, 421, 422, 423, 424, 425, 426, 428, 429, 431, 451,
        500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511, 499, 599,
    ])
    func currentFreshHTTPStatusRejectionMakesExactlyOneRequest(status: Int) async throws {
        try await withSimulation([.response(status, headers: ["Retry-After": "0"], body: Self.errorPage)]) { (simulation: HTTPDownloadSimulation) async throws in
            await expectHTTPStatus(status) { try await simulation.download() }
            #expect(simulation.script.requests.count == 1)
            #expect(simulation.sandbox.downloader.bytesDownloaded == 0)
            #expect(try simulation.sandbox.destinationFiles.isEmpty)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    @Test(arguments: [
        nil, "invalid", "bytes 0-5/*oops", "bytes */6", "bytes 2-5/6",
        "bytes 0-6/6", "bytes 3-2/6", "items 0-5/6",
    ] as [String?])
    func malformedOrUnjoinableFresh206CannotBecomeAnArchive(contentRange: String?) async throws {
        let headers = contentRange.map { ["Content-Range": $0] } ?? [:]
        try await withSimulation([.response(206, headers: headers, body: Self.errorPage)]) { simulation in
            do {
                _ = try await simulation.download()
                Issue.record("An unusable 206 was finalized")
            } catch let error as Downloader.DownloadError {
                guard case .badPartialContent = error else {
                    Issue.record("Expected badPartialContent, got \(error)")
                    return
                }
            }
            #expect(simulation.script.requests.count == 1)
            #expect(simulation.sandbox.downloader.bytesDownloaded == 0)
            #expect(try simulation.sandbox.destinationFiles.isEmpty)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    @Test func shortClean206ResumesUntilTheDeclaredObjectIsComplete() async throws {
        let prefix = Self.payload.prefix(3)
        let suffix = Self.payload.suffix(3)
        try await withSimulation([
            .response(206, headers: ["Content-Range": "bytes 0-2/6", "ETag": "\"v1\""], body: Data(prefix)),
            .response(206, headers: ["Content-Range": "bytes 3-5/6", "ETag": "\"v1\""], body: Data(suffix)),
        ]) { simulation in
            let file = try await simulation.download()
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(simulation.sandbox.downloader.bytesDownloaded == 6)
            let requests = simulation.script.requests
            #expect(requests.count == 2)
            #expect(requests.map(\.range) == [nil, "bytes=3-"])
            #expect(requests.map(\.ifRange) == [nil, "\"v1\""])
        }
    }

    @Test func overlong206IsRejectedWithoutRetryOrFinalizedFile() async throws {
        try await withSimulation([.response(206, headers: ["Content-Range": "bytes 0-2/3"], body: Self.payload)]) { simulation in
            do {
                _ = try await simulation.download()
                Issue.record("An overlong 206 was finalized")
            } catch let error as Downloader.DownloadError {
                guard case .lengthMismatch(let received, let expected) = error else {
                    Issue.record("Expected lengthMismatch, got \(error)")
                    return
                }
                #expect(received == 6)
                #expect(expected == 3)
            }
            #expect(simulation.script.requests.count == 1)
            #expect(try simulation.sandbox.destinationFiles.isEmpty)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    @Test func keptPartialWithMatchingValidatorAppendsOnlyTheTail() async throws {
        try await withSimulation([
            .response(206, headers: ["Content-Range": "bytes 3-5/6", "ETag": "\"old\""], body: Data(Self.payload.suffix(3))),
        ]) { simulation in
            try simulation.sandbox.seedPartial(for: simulation.url, body: Data(Self.payload.prefix(3)), validator: "\"old\"")
            let file = try await simulation.download()
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(simulation.sandbox.downloader.bytesDownloaded == 6)
            #expect(simulation.script.requests.map(\.range) == ["bytes=3-"])
            #expect(simulation.script.requests.map(\.ifRange) == ["\"old\""])
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    @Test func a200IgnoringRangeReplacesTheOldPartialInsteadOfAppending() async throws {
        try await withSimulation([.response(200, headers: ["ETag": "\"new\""], body: Self.payload)]) { simulation in
            try simulation.sandbox.seedPartial(for: simulation.url, body: Data("OLD".utf8), validator: "\"old\"")
            let file = try await simulation.download()
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(simulation.script.requests.map(\.range) == ["bytes=3-"])
            #expect(simulation.script.requests.map(\.ifRange) == ["\"old\""])
            // Traffic counts previously fetched bytes even though they were discarded.
            #expect(simulation.sandbox.downloader.bytesDownloaded == 9)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    @Test(arguments: ["ETag", "Last-Modified"])
    func changedValidatorOn206RestartsFromZeroInsteadOfSplicing(field: String) async throws {
        let old = field == "ETag" ? "\"old\"" : "Wed, 11 Nov 2026 00:00:00 GMT"
        let new = field == "ETag" ? "\"new\"" : "Thu, 12 Nov 2026 00:00:00 GMT"
        try await withSimulation([
            .response(206, headers: ["Content-Range": "bytes 3-5/6", field: new], body: Data("BAD".utf8)),
            .response(200, headers: [field: new], body: Self.payload),
        ]) { simulation in
            try simulation.sandbox.seedPartial(for: simulation.url, body: Data("OLD".utf8), validator: old)
            let file = try await simulation.download()
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(simulation.script.requests.count == 2)
            #expect(simulation.script.requests.map(\.range) == ["bytes=3-", nil])
            #expect(simulation.script.requests.map(\.ifRange) == [old, nil])
            #expect(simulation.sandbox.downloader.bytesDownloaded == 9)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    /// Current behavior: a definitive error while resuming kept bytes earns one
    /// fresh request, even a 403/429/503. A fresh download of the same status earns
    /// none. This pins that asymmetry; it does not endorse the retry policy.
    @Test(arguments: [403, 404, 416, 429, 503])
    func currentKeptPartialStatusFailureDiscardsItAndRetriesOnce(status: Int) async throws {
        try await withSimulation([
            .response(status, body: Self.errorPage), .response(status, body: Self.errorPage),
        ]) { simulation in
            try simulation.sandbox.seedPartial(for: simulation.url, body: Data("OLD".utf8), validator: "\"old\"")
            await expectHTTPStatus(status) { try await simulation.download() }
            #expect(simulation.script.requests.count == 2)
            #expect(simulation.script.requests.map(\.range) == ["bytes=3-", nil])
            #expect(simulation.script.requests.map(\.ifRange) == ["\"old\"", nil])
            #expect(simulation.sandbox.downloader.bytesDownloaded == 3)
            #expect(try simulation.sandbox.destinationFiles.isEmpty)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    @Test func keptPartial403Then200NeverIncludesTheForbiddenPage() async throws {
        try await withSimulation([
            .response(403, body: Self.errorPage), .response(200, body: Self.payload),
        ]) { simulation in
            try simulation.sandbox.seedPartial(for: simulation.url, body: Data("OLD".utf8), validator: "\"old\"")
            let file = try await simulation.download()
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(simulation.script.requests.count == 2)
            #expect(simulation.script.requests.map(\.range) == ["bytes=3-", nil])
            #expect(simulation.sandbox.downloader.bytesDownloaded == 9)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    @Test(arguments: [
        URLError.Code.networkConnectionLost, .timedOut, .cannotConnectToHost, .secureConnectionFailed,
    ])
    func transientTransportErrorRetriesAndUsesTheSecondResponse(code: URLError.Code) async throws {
        try await withSimulation([.transportError(code), .response(200, body: Self.payload)]) { simulation in
            let file = try await simulation.download()
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(simulation.script.requests.count == 2)
            #expect(simulation.script.requests.map(\.range) == [nil, nil])
        }
    }

    @Test func persistentTransportFailureStopsAtFiveRequests() async throws {
        try await withSimulation(Array(repeating: .transportError(.networkConnectionLost), count: 5)) { simulation in
            do {
                _ = try await simulation.download()
                Issue.record("Persistent transport failure unexpectedly succeeded")
            } catch let error as URLError {
                #expect(error.code == .networkConnectionLost)
            }
            #expect(simulation.script.requests.map(\.attempt) == [1, 2, 3, 4, 5])
            #expect(DownloadRetryPolicy.maxAttempts == 5)
            #expect(try simulation.sandbox.destinationFiles.isEmpty)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    /// Certificate failures are injected Foundation errors, not a TLS negotiation.
    @Test(arguments: [
        URLError.Code.cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
        .serverCertificateUntrusted, .serverCertificateHasBadDate, .cancelled, .badServerResponse,
    ])
    func currentNonTransientTransportErrorIsNotRetried(code: URLError.Code) async throws {
        try await withSimulation([.transportError(code)]) { simulation in
            do {
                _ = try await simulation.download()
                Issue.record("Transport error unexpectedly succeeded")
            } catch let error as URLError {
                #expect(error.code == code)
            }
            #expect(simulation.script.requests.count == 1)
            #expect(try simulation.sandbox.destinationFiles.isEmpty)
            #expect(try simulation.sandbox.resumeFiles.isEmpty)
        }
    }

    @Test func cancellationStopsAnObservedInFlightTransferWithoutRetry() async throws {
        let prefix = Data(repeating: 0x64, count: 16_384)
        let server = try HTTPDownloadLoopbackServer([
            .init(status: 200,
                  headers: ["Content-Length": "1000000", "Content-Type": "application/octet-stream"],
                  body: prefix, hold: true),
        ])
        defer { server.stop() }
        let sandbox = try HTTPDownloadSandbox()
        do {
            let task = Task { try await sandbox.download(server.url) }
            // A harness liveness guard, not a download performance assertion.
            // Cancellation happens only after bytes demonstrably reached disk.
            let deadline = Date().addingTimeInterval(15)
            while sandbox.downloader.bytesDownloaded < Int64(prefix.count), Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(server.requests.count == 1, "Fixture never received the GET")
            #expect(sandbox.downloader.bytesDownloaded == Int64(prefix.count), "Fixture body never reached Downloader")
            task.cancel()
            do {
                _ = try await task.value
                Issue.record("A cancelled download unexpectedly completed")
            } catch is CancellationError {
                // Production must translate URLSession's cancellation to Swift cancellation.
            } catch {
                Issue.record("Expected CancellationError, got \(error)")
            }
            #expect(server.requests.count == 1)
            #expect(server.unexpectedRequests.isEmpty)
            #expect(try sandbox.destinationFiles.isEmpty)
            #expect(try sandbox.resumeFiles.isEmpty)
            try await sandbox.close()
        } catch {
            try await sandbox.close()
            throw error
        }
    }

    @Test func loopback302ToMirror403DoesNotRetryOrSaveThePage() async throws {
        let mirror = try HTTPDownloadLoopbackServer([.init(status: 403, body: Self.errorPage)])
        defer { mirror.stop() }
        let entry = try HTTPDownloadLoopbackServer([
            .init(status: 302, headers: ["Location": mirror.url.absoluteString]),
        ])
        defer { entry.stop() }
        let sandbox = try HTTPDownloadSandbox()
        do {
            await expectHTTPStatus(403) { try await sandbox.download(entry.url) }
            #expect(entry.requests.count == 1)
            #expect(mirror.requests.count == 1)
            #expect(entry.unexpectedRequests.isEmpty)
            #expect(mirror.unexpectedRequests.isEmpty)
            #expect(sandbox.downloader.finalHost == "127.0.0.1")
            #expect(try sandbox.destinationFiles.isEmpty)
            #expect(try sandbox.resumeFiles.isEmpty)
            try await sandbox.close()
        } catch {
            try await sandbox.close()
            throw error
        }
    }

    /// Genuine HTTP/1.1 informational heads on a loopback socket, followed by a
    /// final response. 101 switches protocols and is deliberately outside this
    /// downloader simulation. 104 exercises parsing only, not upload resumption.
    @Test(arguments: [100, 102, 103, 104])
    func loopbackInformationalResponseUsesTheFinal200Body(status: Int) async throws {
        let server = try HTTPDownloadLoopbackServer([
            .init(status: 200, body: Self.payload, interimStatuses: [status]),
        ])
        defer { server.stop() }
        let sandbox = try HTTPDownloadSandbox()
        do {
            let file = try await sandbox.download(server.url)
            #expect(try Data(contentsOf: file) == Self.payload)
            #expect(sandbox.downloader.bytesDownloaded == Int64(Self.payload.count))
            #expect(server.requests.count == 1)
            #expect(server.unexpectedRequests.isEmpty)
            #expect(try sandbox.destinationFiles == [file.lastPathComponent])
            #expect(try sandbox.resumeFiles.isEmpty)
            try await sandbox.close()
        } catch {
            try await sandbox.close()
            throw error
        }
    }

    @Test(arguments: [100, 102, 103, 104])
    func loopbackInformationalResponseDoesNotHideTheFinal403(status: Int) async throws {
        let server = try HTTPDownloadLoopbackServer([
            .init(status: 403, body: Self.errorPage, interimStatuses: [status]),
        ])
        defer { server.stop() }
        let sandbox = try HTTPDownloadSandbox()
        do {
            await expectHTTPStatus(403) { try await sandbox.download(server.url) }
            #expect(server.requests.count == 1)
            #expect(server.unexpectedRequests.isEmpty)
            #expect(sandbox.downloader.bytesDownloaded == 0)
            #expect(try sandbox.destinationFiles.isEmpty)
            #expect(try sandbox.resumeFiles.isEmpty)
            try await sandbox.close()
        } catch {
            try await sandbox.close()
            throw error
        }
    }

    @Test func loopbackRedirectToRemoteHTTPIsRefusedBeforeLeavingLoopback() async throws {
        let entry = try HTTPDownloadLoopbackServer([
            .init(status: 302, headers: ["Location": "http://remote-download.invalid/payload.bin"]),
        ])
        defer { entry.stop() }
        let sandbox = try HTTPDownloadSandbox()
        do {
            do {
                _ = try await sandbox.download(entry.url)
                Issue.record("An insecure redirect was followed")
            } catch let error as SecureScheme.SchemeError {
                guard case .insecureDownload(let scheme, let host) = error else { return }
                #expect(scheme == "http")
                #expect(host == "remote-download.invalid")
            }
            #expect(entry.requests.count == 1)
            #expect(entry.unexpectedRequests.isEmpty)
            #expect(try sandbox.destinationFiles.isEmpty)
            #expect(try sandbox.resumeFiles.isEmpty)
            try await sandbox.close()
        } catch {
            try await sandbox.close()
            throw error
        }
    }

    /// Directly exercises the production delegate; custom URLProtocol does not
    /// prove URLSession's real TLS redirect behavior or a multi-hop credential path.
    @Test(arguments: [false, true])
    func redirectDelegateStripsCredentialsOnlyWhenHostChanges(crossHost: Bool) async throws {
        let sandbox = try HTTPDownloadSandbox()
        let session = URLSession(configuration: HTTPDownloadSandbox.configuration())
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://origin-simulation.invalid/payload.bin")!
        let target = URL(string: "https://\(crossHost ? "mirror-simulation.invalid" : "origin-simulation.invalid")/payload.bin")!
        let task = session.dataTask(with: original) // Never resumed: no network access.
        var redirected = URLRequest(url: target)
        let credentials = ["Authorization": "Bearer simulation-only", "Cookie": "simulation=only",
                           "Proxy-Authorization": "Basic simulation-only"]
        for (field, value) in credentials { redirected.setValue(value, forHTTPHeaderField: field) }
        redirected.setValue("https://vendor-simulation.invalid/", forHTTPHeaderField: "Referer")
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        var forwarded: URLRequest?
        sandbox.downloader.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                     newRequest: redirected) { forwarded = $0 }
        do {
            let request = try #require(forwarded)
            #expect(request.url == target)
            for (field, value) in credentials {
                #expect(request.value(forHTTPHeaderField: field) == (crossHost ? nil : value))
            }
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://vendor-simulation.invalid/")
            try await sandbox.close()
        } catch {
            try await sandbox.close()
            throw error
        }
    }
}
