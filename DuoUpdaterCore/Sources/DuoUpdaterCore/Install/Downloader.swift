import Foundation

/// Downloads a URL to a temporary file, reporting progress (0...1). Backed by a
/// URLSession download task so large dmg/zip files stream to disk instead of
/// being held in memory.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    enum DownloadError: LocalizedError {
        case httpStatus(Int)
        case unsafeFilename(String)
        var errorDescription: String? {
            switch self {
            case .httpStatus(let code):
                return "The server returned HTTP \(code) instead of the file."
            case .unsafeFilename(let name):
                return "The server suggested an unsafe download filename: \(name)"
            }
        }
    }

    private var continuation: CheckedContinuation<URL, Error>?
    /// Guards `continuation` so the two delegate callbacks (which can fire on a
    /// concurrent delegate queue) can't double-resume or race a leaked resume.
    private let lock = NSLock()
    private let onProgress: @Sendable (Double) -> Void
    private let destinationDir: URL
    private var session: URLSession!

    /// Exact number of bytes transferred to disk, for per-app traffic accounting.
    /// Updated on every `didWriteData` (cumulative `totalBytesWritten`), so after
    /// `download` returns it holds the full size of the downloaded file. Guarded
    /// by a lock because the delegate fires on a background queue while a caller
    /// reads this from the awaiting task.
    private let bytesLock = NSLock()
    private var _bytesDownloaded: Int64 = 0
    var bytesDownloaded: Int64 {
        bytesLock.lock(); defer { bytesLock.unlock() }
        return _bytesDownloaded
    }

    init(
        destinationDir: URL,
        configuration: URLSessionConfiguration = .default,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.destinationDir = destinationDir
        self.onProgress = onProgress
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Download `url`, returning the location of the downloaded file on disk.
    ///
    /// `headers` lets a caller add request headers a vendor's CDN demands — some
    /// sit behind a WAF that only serves the file to browser-like requests (e.g.
    /// Oray's `dw.oray.com` requires a `Referer`; without it you get an anti-bot
    /// JS challenge page instead of the dmg). They override the default UA.
    func download(_ url: URL, headers: [String: String] = [:]) async throws -> URL {
        // Enforce TLS before a single byte moves: every installer routes through
        // here, so this one gate covers Sparkle, Vendor, GitHub, and pkg
        // downloads. A plaintext http:// payload is a downgrade vector even with
        // the later signature gates, so we refuse it outright.
        try SecureScheme.requireSecureDownload(url)
        bytesLock.withLock {
            _bytesDownloaded = 0
        }
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            self.continuation = cont
            lock.unlock()
            var request = URLRequest(url: url)
            request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
            // Force identity encoding. URLSession otherwise advertises
            // `Accept-Encoding: gzip` and some CDNs (Google's edgedl.me.gvt1.com,
            // serving the Android Studio dmg) honour it even for already-compressed
            // archives. URLSession then decompresses transparently and reports
            // `totalBytesExpectedToWrite == -1` (it can't know the inflated size
            // up front), which stalls the progress bar at 0% while bytes stream to
            // disk. gzip buys nothing on a dmg/zip/pkg, so we opt out and get a
            // real Content-Length. Caller headers below may still override.
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            request.timeoutInterval = 60
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            finish(.failure(URLError(.badURL)))
            completionHandler(nil)
            return
        }
        do {
            try SecureScheme.requireSecureDownload(url)
            completionHandler(request)
        } catch {
            finish(.failure(error))
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        bytesLock.lock()
        _bytesDownloaded = totalBytesWritten
        bytesLock.unlock()

        let total = effectiveTotal(totalBytesExpectedToWrite, response: downloadTask.response)
        guard total > 0 else { return }
        onProgress(min(1.0, Double(totalBytesWritten) / Double(total)))
    }

    /// The expected byte count. URLSession reports -1 when the server streams
    /// without a `Content-Length` — notably Google Cloud Storage (Warp's CDN),
    /// which instead exposes the size in `x-goog-stored-content-length`. Fall back
    /// to that (then to the response's own expected length) so the bar still moves.
    private func effectiveTotal(_ reported: Int64, response: URLResponse?) -> Int64 {
        if reported > 0 { return reported }
        guard let http = response as? HTTPURLResponse else { return reported }
        if let header = http.value(forHTTPHeaderField: "x-goog-stored-content-length"),
           let n = Int64(header) { return n }
        // Google's edgedl CDN exposes the uncompressed size here even when it
        // gzip-encodes the body and drops the usable Content-Length.
        if let header = http.value(forHTTPHeaderField: "x-identity-content-length"),
           let n = Int64(header) { return n }
        if http.expectedContentLength > 0 { return http.expectedContentLength }
        return reported
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Reject error responses: a 403/404/anti-bot challenge page is "downloaded"
        // successfully to disk and would otherwise be handed to the extractor as if
        // it were a valid archive (failing later with a confusing error, or worse).
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            finish(.failure(DownloadError.httpStatus(http.statusCode)))
            return
        }
        // The temp file is deleted when this delegate returns, so move it now.
        let suggested = downloadTask.response?.suggestedFilename ?? location.lastPathComponent
        do {
            let dest = try destinationURL(forSuggestedFilename: suggested)
            try FileManager.default.moveItem(at: location, to: dest)
            // Backstop the byte count from the file on disk in case no
            // `didWriteData` fired (e.g. a tiny or cached response): the moved
            // file's size is the exact number of bytes we received.
            bytesLock.lock()
            if _bytesDownloaded == 0,
               let size = try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64 {
                _bytesDownloaded = size
            }
            bytesLock.unlock()
            finish(.success(dest))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error { finish(.failure(error)) }
    }

    /// Resume the continuation exactly once, under the lock — whichever delegate
    /// callback fires first wins; later ones become no-ops.
    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }

    private func destinationURL(forSuggestedFilename suggested: String) throws -> URL {
        let filename = Self.safeSuggestedFilename(suggested)
        let dest = uniqueDestination(named: filename)
        let base = destinationDir.resolvingSymlinksInPath().standardizedFileURL.path
        let parent = dest.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard parent == base else {
            throw DownloadError.unsafeFilename(suggested)
        }
        return dest
    }

    private func uniqueDestination(named filename: String) -> URL {
        let fm = FileManager.default
        let first = destinationDir.appendingPathComponent(filename, isDirectory: false)
        guard fm.fileExists(atPath: first.path) else { return first }

        let ns = filename as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension.isEmpty ? "download" : ns.deletingPathExtension
        let uniqued = ext.isEmpty
            ? "\(stem)-\(UUID().uuidString)"
            : "\(stem)-\(UUID().uuidString).\(ext)"
        return destinationDir.appendingPathComponent(uniqued, isDirectory: false)
    }

    static func safeSuggestedFilename(_ suggested: String) -> String {
        let trimmed = suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if last.isEmpty || last == "." || last == ".." {
            return "download"
        }
        return last
    }
}
