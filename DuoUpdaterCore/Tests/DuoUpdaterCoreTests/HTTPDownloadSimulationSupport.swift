import Foundation
import Network
@testable import DuoUpdaterCore

/// Test-only transport. HTTPS here identifies a synthetic request; URLProtocol
/// supplies the response without DNS, sockets, a proxy or a TLS handshake.
final class HTTPDownloadSimulation: @unchecked Sendable {
    struct Request: Sendable, Equatable {
        let attempt: Int
        let method: String
        let url: URL
        let range: String?
        let ifRange: String?
        let authorization: String?
        let cookie: String?
        let proxyAuthorization: String?

        init(_ request: URLRequest, attempt: Int) {
            self.attempt = attempt
            method = request.httpMethod ?? "GET"
            url = request.url!
            range = request.value(forHTTPHeaderField: "Range")
            ifRange = request.value(forHTTPHeaderField: "If-Range")
            authorization = request.value(forHTTPHeaderField: "Authorization")
            cookie = request.value(forHTTPHeaderField: "Cookie")
            proxyAuthorization = request.value(forHTTPHeaderField: "Proxy-Authorization")
        }
    }

    enum Step: Sendable {
        /// `hold` deliberately leaves a transfer in flight until cancellation.
        case response(Int, headers: [String: String] = [:], body: Data = Data(), hold: Bool = false)
        case transportError(URLError.Code)
    }

    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private let steps: [Step]
        private var seen: [Request] = []
        private var failures: [String] = []
        private var stopped = false

        init(_ steps: [Step]) { self.steps = steps }

        func take(_ request: URLRequest) -> Step? {
            lock.withLock {
                seen.append(Request(request, attempt: seen.count + 1))
                guard !stopped, seen.count <= steps.count else {
                    failures.append("Unexpected request \(seen.count): \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "nil")")
                    return nil
                }
                return steps[seen.count - 1]
            }
        }

        var requests: [Request] { lock.withLock { seen } }
        var unexpectedRequests: [String] { lock.withLock { failures } }
        var remaining: Int { lock.withLock { max(0, steps.count - seen.count) } }
        func stop() { lock.withLock { stopped = true } }
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var scripts: [String: Script] = [:]
        func add(_ script: Script, token: String) { lock.withLock { scripts[token] = script } }
        func remove(_ token: String) { _ = lock.withLock { scripts.removeValue(forKey: token) } }
        func script(for request: URLRequest) -> Script? {
            guard let token = request.url?.pathComponents.dropFirst().first else { return nil }
            return lock.withLock { scripts[token] }
        }
    }

    private final class Transport: URLProtocol, @unchecked Sendable {
        static let registry = Registry()
        // stopLoading must serialize with client callbacks: cancellation must not
        // race a body/finish callback delivered after the protocol was stopped.
        private let callbackLock = NSRecursiveLock()
        private var stopped = false

        // This session catches EVERY URL. An unexpected URL fails locally rather
        // than falling through to Foundation's network protocol implementations.
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            guard !stopped else { return }
            guard let script = Self.registry.script(for: request),
                  let step = script.take(request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
                return
            }
            switch step {
            case .transportError(let code):
                client?.urlProtocol(self, didFailWithError: URLError(code))
            case .response(let status, let suppliedHeaders, let body, let hold):
                var headers = suppliedHeaders
                if headers["Content-Length"] == nil { headers["Content-Length"] = String(body.count) }
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: "HTTP/1.1", headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                guard !stopped else { return }
                if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
                guard !stopped else { return }
                if !hold { client?.urlProtocolDidFinishLoading(self) }
            }
        }

        override func stopLoading() {
            callbackLock.lock()
            stopped = true
            callbackLock.unlock()
        }
    }

    let token = UUID().uuidString
    let script: Script
    let sandbox: HTTPDownloadSandbox
    var url: URL { URL(string: "https://download-simulation.invalid/\(token)/payload.bin")! }

    init(_ steps: [Step]) throws {
        script = Script(steps)
        let configuration = HTTPDownloadSandbox.configuration()
        configuration.protocolClasses = [Transport.self]
        sandbox = try HTTPDownloadSandbox(configuration: configuration)
        Transport.registry.add(script, token: token)
    }

    func download(headers: [String: String] = [:]) async throws -> URL {
        try await sandbox.download(url, headers: headers)
    }

    func close() async throws {
        script.stop()
        Transport.registry.remove(token)
        try await sandbox.close()
    }
}

/// Owns the exact temporary root it deletes. Every download explicitly binds the
/// real resumable store to this sandbox and injects a private event store.
final class HTTPDownloadSandbox: @unchecked Sendable {
    private final class BlockNonLoopback: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool {
            !["127.0.0.1", "localhost", "::1"].contains(request.url?.host?.lowercased() ?? "")
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            // Also closes the escape hatch if the production redirect guard is
            // accidentally removed: this fixture still cannot reach the Internet.
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
        }
        override func stopLoading() {}
    }

    let root: URL
    let destination: URL
    let resumeRoot: URL
    let store: EventStore
    let downloader: Downloader

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.protocolClasses = [BlockNonLoopback.self]
        return configuration
    }

    init(configuration: URLSessionConfiguration = HTTPDownloadSandbox.configuration()) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HTTPDownloadSimulation-\(UUID().uuidString)", isDirectory: true)
        destination = root.appendingPathComponent("downloads", isDirectory: true)
        resumeRoot = root.appendingPathComponent("resume", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resumeRoot, withIntermediateDirectories: true)
        store = EventStore(fileURL: root.appendingPathComponent("events.sqlite"))
        downloader = Downloader(destinationDir: destination, configuration: configuration, store: store) { _ in }
    }

    func download(_ url: URL, headers: [String: String] = [:]) async throws -> URL {
        try await ResumableDownloadStore.$rootOverride.withValue(resumeRoot) {
            try await downloader.download(url, headers: headers)
        }
    }

    /// Seed through the production store's lease/record/close operations, exactly
    /// as a previous cancelled download would leave its bytes and validator.
    func seedPartial(for url: URL, body: Data, validator: String) throws {
        try ResumableDownloadStore.$rootOverride.withValue(resumeRoot) {
            guard let lease = ResumableDownloadStore.open(for: url, appID: nil) else {
                throw URLError(.cannotCreateFile)
            }
            defer { ResumableDownloadStore.close(lease, keep: true) }
            try body.write(to: lease.entry.partial)
            ResumableDownloadStore.record(lease, validator: validator, bytesWritten: Int64(body.count))
        }
    }

    var destinationFiles: [String] {
        get throws { try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted() }
    }
    var resumeFiles: [String] {
        get throws { try FileManager.default.contentsOfDirectory(atPath: resumeRoot.path).sorted() }
    }

    func close() async throws {
        await store.flush()
        try FileManager.default.removeItem(at: root)
    }
}

/// Real HTTP redirect handling over explicitly bound loopback only. This covers
/// Foundation's redirect delegate dispatch, but deliberately makes no TLS claim.
final class HTTPDownloadLoopbackServer: @unchecked Sendable {
    struct Response: Sendable {
        let status: Int
        var headers: [String: String] = [:]
        var body = Data()
        var interimStatuses: [Int] = []
        var hold = false
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var connections: [ObjectIdentifier: NWConnection] = [:]
        var stopped = false
        var requests: [String] = []
        var unexpected: [String] = []
        let responses: [Response]
        init(_ responses: [Response]) { self.responses = responses }
        func accept(_ connection: NWConnection) -> Bool {
            lock.withLock {
                guard !stopped else { return false }
                connections[ObjectIdentifier(connection)] = connection
                return true
            }
        }
        func next(_ request: String) -> Response? {
            lock.withLock {
                guard !stopped else { return nil }
                requests.append(request)
                guard requests.count <= responses.count else {
                    unexpected.append(request)
                    return nil
                }
                return responses[requests.count - 1]
            }
        }
        func release(_ connection: NWConnection) {
            _ = lock.withLock { connections.removeValue(forKey: ObjectIdentifier(connection)) }
            connection.cancel()
        }
    }

    private let listener: NWListener
    private let state: State
    private let queue = DispatchQueue(label: "HTTPDownloadLoopbackServer")
    let port: UInt16
    var url: URL { URL(string: "http://127.0.0.1:\(port)/payload.bin")! }
    var requests: [String] { state.lock.withLock { state.requests } }
    var unexpectedRequests: [String] { state.lock.withLock { state.unexpected } }

    init(_ responses: [Response]) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
        state = State(responses)
        let state = self.state
        let queue = self.queue
        listener.newConnectionHandler = { connection in
            guard state.accept(connection) else { connection.cancel(); return }
            connection.start(queue: queue)
            @Sendable func receive(_ prefix: Data) {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { chunk, _, done, error in
                    guard !state.lock.withLock({ state.stopped }) else { state.release(connection); return }
                    var head = prefix
                    if let chunk { head.append(chunk) }
                    guard head.range(of: Data("\r\n\r\n".utf8)) != nil else {
                        if done || error != nil || head.count > 64 * 1024 { state.release(connection) }
                        else { receive(head) }
                        return
                    }
                    guard let response = state.next(String(decoding: head, as: UTF8.self)) else {
                        state.release(connection)
                        return
                    }
                    var headers = response.headers
                    if headers["Content-Length"] == nil { headers["Content-Length"] = String(response.body.count) }
                    headers["Connection"] = response.hold ? "keep-alive" : "close"
                    // Informational heads precede the final response on the same
                    // socket. They are not standalone responses with a body.
                    var output = response.interimStatuses.map {
                        "HTTP/1.1 \($0) Simulation\r\n\r\n"
                    }.joined()
                    output += "HTTP/1.1 \(response.status) Simulation\r\n"
                    for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
                        output += "\(name): \(value)\r\n"
                    }
                    var bytes = Data((output + "\r\n").utf8)
                    bytes.append(response.body)
                    connection.send(content: bytes, completion: .contentProcessed { error in
                        // A held response deliberately leaves the declared body
                        // incomplete. State retains it until the client cancels
                        // or stop() closes all connections.
                        if error != nil || !response.hold { state.release(connection) }
                    })
                }
            }
            receive(Data())
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { status in
            switch status {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success,
              let port = listener.port?.rawValue, port != 0 else {
            listener.cancel()
            throw URLError(.cannotConnectToHost)
        }
        self.port = port
    }

    func stop() {
        let connections = state.lock.withLock {
            state.stopped = true
            let connections = Array(state.connections.values)
            state.connections.removeAll()
            return connections
        }
        listener.cancel()
        connections.forEach { $0.cancel() }
    }
}
