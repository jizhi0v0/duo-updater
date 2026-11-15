import Foundation

/// A bounded, delegate-driven GET. Rejects ignored/malformed ranges at the
/// headers, before a CDN can stream a complete installer for each requested block.
final class ElectronBlockmapHTTP: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    final class Accounting: @unchecked Sendable {
        private let lock = NSLock()
        private var received: Int64 = 0
        var bytes: Int64 { lock.withLock { received } }
        func add(_ count: Int) { lock.withLock { received += Int64(count) } }
    }

    enum Failure: Error { case insecureURL, response, bodyLimit, range, redirects }
    @TaskLocal static var configurationOverride: URLSessionConfiguration?

    private let limit: Int
    private let range: Range<Int64>?
    private let total: Int64?
    private let accounting: Accounting
    private let metrics: RequestMetricsRecorder
    private let redirector = CrossHostCredentialStripper()
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var session: URLSession?
    private var continuation: CheckedContinuation<(Data, String?), Error>?
    private var body = Data()
    private var failure: Error?
    private var response: HTTPURLResponse?
    private var redirects = 0

    init(limit: Int, range: Range<Int64>?, total: Int64?,
         accounting: Accounting, appID: String) {
        self.limit = limit
        self.range = range
        self.total = total
        self.accounting = accounting
        self.metrics = RequestMetricsRecorder(.install, appID: appID)
    }

    static func allowed(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return false }
        do { try SecureScheme.requireSecureDownload(url); return true }
        catch { return false }
    }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, String?) {
        guard Self.allowed(url) else { throw Failure.insecureURL }
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue(Downloader.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let range {
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let configuration = Self.configurationOverride ?? .ephemeral
                configuration.urlCache = nil
                configuration.httpCookieStorage = nil
                configuration.urlCredentialStorage = nil
                configuration.timeoutIntervalForResource = 120
                if AutomaticInstall.active {
                    configuration.allowsConstrainedNetworkAccess = false
                    configuration.allowsExpensiveNetworkAccess = false
                }
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                self.continuation = continuation
                let task = session.dataTask(with: request)
                let wasCancelled = lock.withLock {
                    self.task = task
                    return cancelled
                }
                if wasCancelled { task.cancel() }
                task.resume()
            }
        } onCancel: {
            self.lock.withLock {
                self.cancelled = true
                self.task?.cancel()
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            failure = Failure.response; completionHandler(.cancel); return
        }
        self.response = http
        if let range {
            guard http.statusCode == 206, let total,
                  http.value(forHTTPHeaderField: "Content-Range") ==
                    "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(total)",
                  http.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) ?? true,
                  http.expectedContentLength < 0 || http.expectedContentLength == range.count
            else { failure = Failure.range; completionHandler(.cancel); return }
        } else if http.statusCode != 200 {
            failure = Failure.response; completionHandler(.cancel); return
        }
        guard http.expectedContentLength <= limit else {
            failure = Failure.bodyLimit; completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        accounting.add(data.count)
        guard data.count <= limit - body.count else {
            failure = Failure.bodyLimit; dataTask.cancel(); return
        }
        body.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        let continuation = self.continuation
        self.continuation = nil
        if lock.withLock({ cancelled }) { continuation?.resume(throwing: CancellationError()) }
        else if let error = failure ?? error { continuation?.resume(throwing: error) }
        else if response == nil || range.map({ Int64(body.count) != $0.count }) == true {
            continuation?.resume(throwing: Failure.response)
        } else { continuation?.resume(returning: (body, response?.url?.host)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 10, let url = request.url, Self.allowed(url) else {
            failure = Failure.redirects; completionHandler(nil); return
        }
        if task.originalRequest?.url?.scheme == "https", url.scheme != "https" {
            failure = Failure.insecureURL; completionHandler(nil); return
        }
        redirector.urlSession(session, task: task, willPerformHTTPRedirection: response,
                              newRequest: request) { forwarded in
            guard var forwarded else { completionHandler(nil); return }
            if !CrossHostCredentialStripper.sameOrigin(task.originalRequest?.url, url) {
                for key in ["Authorization", "Cookie", "Proxy-Authorization", "Private-Token", "X-Api-Key"] {
                    forwarded.setValue(nil, forHTTPHeaderField: key)
                }
            }
            // Range and encoding describe this GET, not the redirecting origin.
            if let range = self.range {
                forwarded.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
            }
            forwarded.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            completionHandler(forwarded)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        self.metrics.urlSession(session, task: task, didFinishCollecting: metrics)
    }
}
