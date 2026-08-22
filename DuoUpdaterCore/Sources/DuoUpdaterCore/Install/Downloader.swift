import Foundation

/// Downloads a URL to a temporary file, reporting progress (0...1).
///
/// Streams the body to its own partial file on disk (via a data task), so large
/// dmg/zip/pkg payloads never sit in memory. Two robustness layers sit on top,
/// because every installer (Sparkle, Vendor, GitHub, pkg) routes through here and
/// a flaky path — a VPN/proxy that resets long transfers, a CDN edge that drops a
/// connection mid-stream — otherwise surfaces as a bare "network connection was
/// lost" with nothing salvaged:
///
///   - **Resume.** Each attempt records how many bytes already landed on disk and
///     re-requests with `Range: bytes=<n>-`. A 263 MB download that dies at 85%
///     picks up from there instead of restarting from zero. If the server ignores
///     the range (replies `200` instead of `206`), we discard the partial and
///     start over — correctness over cleverness.
///   - **Retry.** Transient mid-transfer failures (`-1005` connection lost,
///     `-1001` timeout, TLS reset) are retried a few times with a short backoff,
///     resuming from the partial file each time. Definitive failures (an HTTP
///     error page, an insecure redirect, a disk error) are not retried.
final class Downloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {

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

    /// How many times a single `download` call will (re-)issue the request before
    /// giving up, counting the first attempt. Sized for the observed failure mode:
    /// a proxy that resets a transfer every ~200 MB needs a handful of resumes to
    /// carry a ~500 MB payload across the finish line.
    private let maxAttempts = 5

    private var continuation: CheckedContinuation<URL, Error>?
    /// Guards `continuation` so the delegate callbacks (which fire on a concurrent
    /// delegate queue) can't double-resume or race a leaked resume.
    private let lock = NSLock()
    private let onProgress: @Sendable (Double) -> Void
    private let destinationDir: URL
    /// Held so each `download` call can build its own session — see `session`.
    private let configuration: URLSessionConfiguration
    /// The session for the CURRENT `download` call, created at its start and
    /// invalidated when it returns.
    ///
    /// It deliberately does NOT live for the object's lifetime: a session created
    /// with `init(configuration:delegate:delegateQueue:)` keeps a **strong**
    /// reference to its delegate until it is invalidated, and our delegate is
    /// `self` — which also owns the session. That's a retain cycle ARC can't break,
    /// so every `Downloader` (and its session, delegate queue, and worker thread)
    /// leaked for the life of the process. Since a menu-bar app builds one
    /// `Downloader` per install and runs for weeks, those add up. Scoping the
    /// session to one `download` call and invalidating it in a `defer` breaks the
    /// cycle on every exit path, success or throw.
    private var session: URLSession?

    /// Exact number of bytes received over the network, for per-app traffic
    /// accounting. Accumulated across resume attempts, so it reflects real traffic
    /// (a partial transfer that was retried counts the bytes that were actually
    /// pulled, including any discarded on a `200` restart). Guarded by a lock
    /// because the delegate fires on a background queue while a caller reads this.
    private let bytesLock = NSLock()
    private var _bytesDownloaded: Int64 = 0
    var bytesDownloaded: Int64 {
        bytesLock.lock(); defer { bytesLock.unlock() }
        return _bytesDownloaded
    }

    /// The host that actually served the bytes, after redirects — the feed's
    /// URL frequently points at a host that bounces to a CDN (GitHub →
    /// `objects.githubusercontent.com`). Set from the final response; nil when
    /// no response arrived (a local `file://` copy, or a failed transfer).
    /// Read only after `download` returns, so no lock is needed.
    var finalHost: String?

    // MARK: Per-attempt streaming state
    //
    // Mutated only by one data task's serialized delegate callbacks, and by
    // `download` between awaited attempts (one task is fully complete before the
    // next begins). No two tasks run concurrently for a single `Downloader`.
    private var partialURL: URL?
    private var fallbackFilename = "download"
    private var fileHandle: FileHandle?
    private var attemptStartOffset: Int64 = 0   // bytes already on disk when the attempt began
    private var writtenOffset: Int64 = 0        // absolute bytes on disk now
    private var totalExpected: Int64 = 0
    private var suggestedFilename: String?
    /// Last whole-percent handed to `onProgress`, so the delegate only reports a
    /// visible change. `-1` means "nothing reported yet this attempt".
    private var lastReportedPercent = -1
    /// A definitive error captured at response time (bad status / disk write), to
    /// be surfaced from `didCompleteWithError` instead of the cancellation it
    /// triggers.
    private var pendingError: Error?

    init(
        destinationDir: URL,
        configuration: URLSessionConfiguration = .default,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.destinationDir = destinationDir
        self.onProgress = onProgress
        self.configuration = configuration
        super.init()
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
        bytesLock.withLock { _bytesDownloaded = 0 }

        // Local files (only ever `file://` in tests) copy straight across: no
        // network, no range, no retry — and the byte count comes from the file
        // size exactly. No session is created, so nothing to tear down.
        if url.isFileURL {
            return try copyLocalFile(url)
        }

        // One session per call, released on every exit path (see `session`). By the
        // time we return, the data task has already completed — the continuation is
        // only resumed from `didCompleteWithError` / a redirect rejection — so
        // `finishTasksAndInvalidate` has nothing outstanding to wait on; it just
        // drops the session's strong reference to us.
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
        }

        // The partial file we accumulate into across resume attempts, in the dir
        // we own. A fresh name per call means attempt 1 always starts at zero (no
        // stale-partial range that could land us on a 416).
        let partial = destinationDir
            .appendingPathComponent(".duo-download-\(UUID().uuidString).partial", isDirectory: false)
        try? FileManager.default.removeItem(at: partial)
        partialURL = partial
        suggestedFilename = nil
        fallbackFilename = Self.safeSuggestedFilename(url.lastPathComponent)
        // On any exit: a leftover partial is swept (on success it's already moved).
        defer { try? FileManager.default.removeItem(at: partial) }

        var lastError: Error = URLError(.unknown)
        for attempt in 0..<maxAttempts {
            do {
                return try await runAttempt(url: url, headers: headers, partial: partial)
            } catch {
                lastError = error
                // Only transient mid-transfer failures are worth another pass; the
                // partial file persists so the next attempt resumes from it.
                guard attempt < maxAttempts - 1, Self.isTransient(error) else { throw error }
                // Brief, growing backoff (0.5s, 1.0s, …) so we don't hammer a CDN
                // that's momentarily resetting connections.
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
            }
        }
        throw lastError
    }

    /// One request/response cycle: (re)issue the GET — ranged if a partial exists —
    /// and stream the body into the partial file. Returns the finalized file on
    /// success; throws on failure (the caller decides whether to resume).
    private func runAttempt(url: URL, headers: [String: String], partial: URL) async throws -> URL {
        let existing = (try? FileManager.default
            .attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? 0

        var request = URLRequest(url: url)
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        // Force identity encoding. URLSession otherwise advertises
        // `Accept-Encoding: gzip` and some CDNs (Google's edgedl.me.gvt1.com,
        // serving the Android Studio dmg) honour it even for already-compressed
        // archives. URLSession then decompresses transparently and reports
        // `totalBytesExpectedToWrite == -1` (it can't know the inflated size up
        // front), which stalls the progress bar at 0% while bytes stream to disk.
        // gzip buys nothing on a dmg/zip/pkg, so we opt out and get a real
        // Content-Length. Caller headers below may still override.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.timeoutInterval = 60
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }

        attemptStartOffset = existing
        writtenOffset = existing
        totalExpected = 0
        fileHandle = nil
        pendingError = nil
        lastReportedPercent = -1

        guard let session else { throw URLError(.unknown) }
        return try await withCheckedThrowingContinuation { cont in
            lock.lock(); continuation = cont; lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    // MARK: - Data delegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // The response arrives AFTER redirects, so `response.url` is the host
        // that will actually serve the bytes — the per-install gate keys on
        // this (see `hostInstallGate` in the app).
        finalHost = response.url?.host
        if let name = response.suggestedFilename, suggestedFilename == nil {
            suggestedFilename = name
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 200

        do {
            if status == 206, attemptStartOffset > 0 {
                // Server honoured our range — append to what we already have.
                totalExpected = Self.contentRangeTotal(http)
                    ?? (attemptStartOffset + max(0, response.expectedContentLength))
                let handle = try FileHandle(forWritingTo: partialURL!)
                try handle.seekToEnd()
                fileHandle = handle
                writtenOffset = attemptStartOffset
            } else if status == 200 || http == nil {
                // Fresh download, or the server ignored our range and re-sent the
                // whole body: discard any partial bytes and start from zero so we
                // never append a full body onto a partial one.
                totalExpected = effectiveTotal(response.expectedContentLength, response: response)
                try? FileManager.default.removeItem(at: partialURL!)
                FileManager.default.createFile(atPath: partialURL!.path, contents: nil)
                fileHandle = try FileHandle(forWritingTo: partialURL!)
                writtenOffset = 0
            } else {
                // Any other non-2xx (a 403/404 anti-bot page, a stray 416): reject.
                // Such a body must never reach the extractor as if it were the
                // archive.
                pendingError = DownloadError.httpStatus(status)
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        } catch {
            pendingError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard let handle = fileHandle else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            // Disk write failed (e.g. out of space) — abort and surface on
            // completion. Not retryable.
            pendingError = error
            dataTask.cancel()
            return
        }
        writtenOffset += Int64(data.count)
        bytesLock.lock(); _bytesDownloaded += Int64(data.count); bytesLock.unlock()

        // Report only when the whole percent actually moves. URLSession delivers a
        // body in many small chunks — thousands for a large dmg — and every caller
        // routes `onProgress` through a hop onto the main actor
        // (`Task { @MainActor in setStage(…) }`). The model already discards
        // same-percent ticks, but it does so *after* that hop, so the hop itself was
        // still paid thousands of times per download (times however many installs
        // run in parallel). Filtering here means the actor only hears the ~100
        // transitions a progress bar can actually show.
        guard totalExpected > 0 else { return }
        let fraction = min(1.0, Double(writtenOffset) / Double(totalExpected))
        let percent = Int(fraction * 100)
        guard percent != lastReportedPercent else { return }
        lastReportedPercent = percent
        onProgress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        try? fileHandle?.close()
        fileHandle = nil

        // A status/disk rejection captured earlier wins over the cancellation it
        // produced.
        if let pending = pendingError {
            pendingError = nil
            finish(.failure(pending))
            return
        }
        if let error {
            finish(.failure(error))
            return
        }
        // Success: the full body streamed to the partial file. Move it into place.
        do {
            finish(.success(try finalizePartial()))
        } catch {
            finish(.failure(error))
        }
    }

    // MARK: - Caching

    /// Never cache a download. The bytes are streamed straight to disk, so a cache
    /// copy is pure duplication — and the archived request would carry whatever
    /// `headers` the caller passed, which for Alcove is a licensed `Authorization:
    /// Bearer`. This session runs on `.default`, i.e. `URLCache.shared`, so without
    /// this the credential's only protection is the installer being too big to cache.
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping (CachedURLResponse?) -> Void
    ) {
        completionHandler(nil)
    }

    // MARK: - Redirects

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
            // Strip credential headers when a redirect crosses to a different host,
            // so a caller-supplied `Authorization`/`Cookie` (e.g. a license-bearing
            // download header) can't be forwarded to a third-party redirect target.
            var forwarded = request
            if url.host != task.originalRequest?.url?.host {
                for field in ["Authorization", "Cookie", "Proxy-Authorization"] {
                    forwarded.setValue(nil, forHTTPHeaderField: field)
                }
            }
            completionHandler(forwarded)
        } catch {
            finish(.failure(error))
            completionHandler(nil)
        }
    }

    // MARK: - Finalize

    /// Move the completed partial file to its safe destination, deriving the name
    /// from the server's suggestion (confined to `destinationDir`).
    private func finalizePartial() throws -> URL {
        guard let partial = partialURL else { throw URLError(.unknown) }
        let dest = try destinationURL(forSuggestedFilename: suggestedFilename ?? fallbackFilename)
        // Backstop the byte count from the file on disk in case no `didReceive`
        // data fired (a tiny or fully cached response): the moved file's size is
        // the exact number of bytes we received.
        bytesLock.lock()
        if _bytesDownloaded == 0,
           let size = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value {
            _bytesDownloaded = size
        }
        bytesLock.unlock()
        try FileManager.default.moveItem(at: partial, to: dest)
        return dest
    }

    /// Copy a `file://` source straight into the destination dir.
    private func copyLocalFile(_ url: URL) throws -> URL {
        let dest = try destinationURL(forSuggestedFilename: url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: dest)
        let size = (try? FileManager.default
            .attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
        bytesLock.withLock { _bytesDownloaded = size }
        return dest
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

    // MARK: - Helpers

    /// The expected total byte count. URLSession reports -1 when the server streams
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

    /// The total size from a `Content-Range: bytes <start>-<end>/<total>` header
    /// (total may be `*` when unknown, which yields nil).
    private static func contentRangeTotal(_ http: HTTPURLResponse?) -> Int64? {
        guard let value = http?.value(forHTTPHeaderField: "Content-Range"),
              let slash = value.lastIndex(of: "/") else { return nil }
        let total = value[value.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return Int64(total)
    }

    /// `URLError` codes that represent a transient mid-transfer hiccup worth
    /// resuming — a connection the network/proxy/CDN dropped while bytes were
    /// flowing, not a definitive "this won't work" answer.
    private static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost,   // -1005: the proxy/CDN reset mid-transfer
             .timedOut,                // -1001: stalled long enough to time out
             .cannotConnectToHost,     // -1004: a transient proxy/connect hiccup
             .secureConnectionFailed:  // -1200: TLS connection reset ("unexpected eof")
            return true
        default:
            return false
        }
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
