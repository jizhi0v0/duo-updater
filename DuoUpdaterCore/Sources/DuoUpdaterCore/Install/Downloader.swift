import Foundation

/// Downloads a URL to a temporary file, reporting progress (0...1). Backed by a
/// URLSession download task so large dmg/zip files stream to disk instead of
/// being held in memory.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Double) -> Void
    private let destinationDir: URL
    private var session: URLSession!

    init(destinationDir: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destinationDir = destinationDir
        self.onProgress = onProgress
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    /// Download `url`, returning the location of the downloaded file on disk.
    ///
    /// `headers` lets a caller add request headers a vendor's CDN demands — some
    /// sit behind a WAF that only serves the file to browser-like requests (e.g.
    /// Oray's `dw.oray.com` requires a `Referer`; without it you get an anti-bot
    /// JS challenge page instead of the dmg). They override the default UA.
    func download(_ url: URL, headers: [String: String] = [:]) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            var request = URLRequest(url: url)
            request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            request.timeoutInterval = 60
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
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
        if http.expectedContentLength > 0 { return http.expectedContentLength }
        return reported
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temp file is deleted when this delegate returns, so move it now.
        let suggested = downloadTask.response?.suggestedFilename ?? location.lastPathComponent
        let dest = destinationDir.appendingPathComponent(suggested)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume(returning: dest)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
