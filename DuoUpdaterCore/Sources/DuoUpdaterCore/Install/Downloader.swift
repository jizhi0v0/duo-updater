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
///     re-requests with `Range: bytes=<n>-` (and `If-Range`, so a server whose
///     object changed in between answers with the whole new one). A 263 MB
///     download that dies at 85% picks up from there instead of restarting from
///     zero. If the server ignores the range — replies `200`, or `206` from byte
///     0 — we discard the partial and start over: correctness over cleverness. A
///     `206` is only appended when its `Content-Range` starts exactly where the
///     partial ends, and a clean close that leaves fewer bytes on disk than the
///     server's own declared total is another resume, not a finished file (#225).
///   - **Retry.** Transient mid-transfer failures (`-1005` connection lost,
///     `-1001` timeout, TLS reset) are retried a few times with a short backoff,
///     resuming from the partial file each time. Definitive failures (an HTTP
///     error page, an insecure redirect, a disk error) are not retried.
final class Downloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    /// The UA every installer fetch carries.
    ///
    /// Shared rather than inlined because the sweep's install-URL reachability
    /// probe (`VendorProbeSource.installURLReachability`) has to send the SAME
    /// one to be asking about the same thing. SourceForge answers 403 to a
    /// browser-like agent and 200 to this, so a probe that drifted off this
    /// constant would report healthy recipes as broken.
    static let userAgent = "DuoUpdater/0.1"


    enum DownloadError: LocalizedError {
        case httpStatus(Int)
        case unsafeFilename(String)
        /// A `206` whose `Content-Range` is missing, invalid, or describes a range
        /// that cannot be joined onto the bytes already on disk. Not retried: the
        /// same request would draw the same answer.
        case badPartialContent(String)
        /// The connection closed cleanly with a different number of bytes on disk
        /// than the server itself declared as the object's length. Transient when
        /// short — the next attempt resumes from where this one stopped.
        case lengthMismatch(received: Int64, expected: Int64)
        var errorDescription: String? {
            switch self {
            case .httpStatus(let code):
                return "The server returned HTTP \(code) instead of the file."
            case .unsafeFilename(let name):
                return "The server suggested an unsafe download filename: \(name)"
            case .badPartialContent(let reason):
                return "The server sent a partial response that cannot be used: \(reason)."
            case .lengthMismatch(let received, let expected):
                return "The server closed the connection after \(received) of \(expected) bytes."
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
    /// The object's complete length as the server itself declared it in a
    /// `Content-Range` — the only figure a clean close is checked against. Nil on
    /// a `200` (its `Content-Length` is not authoritative for us: gzip and
    /// `x-goog-stored-content-length` both make it describe something else, and
    /// URLSession already fails a body that stops short of it) and for a `*`
    /// total.
    private var declaredTotal: Int64?
    /// The validator a resume sends as `If-Range`, captured from the response
    /// that started the file on disk. A server whose object changed in between
    /// then answers `200`, which discards the partial, instead of `206`, which
    /// would splice two different builds. RFC 9110 §13.1.5: a strong `ETag`;
    /// never a weak (`W/`) one; `Last-Modified` only when there is no `ETag` at
    /// all. Reset per `download`, and whenever the file on disk starts over.
    private var resumeValidator: String?
    private var suggestedFilename: String?
    /// Last whole-percent handed to `onProgress`, so the delegate only reports a
    /// visible change. `-1` means "nothing reported yet this attempt".
    private var lastReportedPercent = -1
    /// A definitive error captured at response time (bad status / disk write), to
    /// be surfaced from `didCompleteWithError` instead of the cancellation it
    /// triggers.
    private var pendingError: Error?

    /// What the request ledger should call these bytes. Every current caller is
    /// installing an app; carried as a parameter rather than hard-coded so a route
    /// that downloads something else through this class has to say so.
    private let ledgerPurpose: RequestPurpose
    private let store: EventStore

    init(
        destinationDir: URL,
        configuration: URLSessionConfiguration = .default,
        purpose: RequestPurpose = .install,
        store: EventStore = .shared,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.destinationDir = destinationDir
        self.onProgress = onProgress
        self.configuration = configuration
        self.ledgerPurpose = purpose
        self.store = store
        super.init()
    }

    /// File the transfer with the request ledger.
    ///
    /// Separate from `_bytesDownloaded`, which counts body bytes and becomes the
    /// `install` event the Traffic window reads — the number the user sees against
    /// an app. This one records the same transfer as *network activity*: per host,
    /// including every redirect hop and the request/response headers. The two
    /// answer different questions and are allowed to differ, which is why both are
    /// kept rather than one being derived from the other. A resumed transfer
    /// reports one transaction per attempt here, which is what actually happened.
    ///
    /// Unlike `URLSession.updates`, this session's tasks are delegate-driven, so
    /// the callback would arrive either way; it is implemented here rather than via
    /// a per-task delegate only because `self` is already the delegate.
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let events = RequestMetricsRecorder.events(
            from: metrics, task: task, purpose: ledgerPurpose, appID: attributedApp)
        guard !events.isEmpty else { return }
        store.stage(events.map {
            DuoEvent(date: $0.responseEnd ?? $0.fetchStart ?? Date(), payload: .request($0))
        })
    }

    /// Download `url`, returning the location of the downloaded file on disk.
    ///
    /// `headers` lets a caller add request headers a vendor's CDN demands — some
    /// sit behind a WAF that only serves the file to browser-like requests (e.g.
    /// Oray's `dw.oray.com` requires a `Referer`; without it you get an anti-bot
    /// JS challenge page instead of the dmg). They override the default UA.
    /// Which app this download is for, captured when `download` is called.
    ///
    /// Behind `bytesLock` for the same reason `_bytesDownloaded` is: it is
    /// written on the caller's task and read on the session's delegate queue.
    private var _attributedApp: String?
    private var attributedApp: String? {
        get { bytesLock.withLock { _attributedApp } }
        set { bytesLock.withLock { _attributedApp = newValue } }
    }

    func download(_ url: URL, headers: [String: String] = [:]) async throws -> URL {
        // Enforce TLS before a single byte moves: every installer routes through
        // here, so this one gate covers Sparkle, Vendor, GitHub, and pkg
        // downloads. A plaintext http:// payload is a downgrade vector even with
        // the later signature gates, so we refuse it outright.
        try SecureScheme.requireSecureDownload(url)
        bytesLock.withLock { _bytesDownloaded = 0 }
        // Read here, in the calling task, and stored for the metrics callback —
        // which runs on the session's delegate queue, outside this task's tree,
        // where the task-local reads back as its default. This is the same trap
        // `RequestMetricsRecorder` documents; the difference is that this class
        // is its own session delegate rather than going through `countedData`,
        // so it has to do the capture itself. Without it the biggest rows in the
        // log — the installers — are the only ones with no app against them.
        attributedApp = RequestAttribution.appID

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
        resumeValidator = nil
        fallbackFilename = Self.safeSuggestedFilename(url.lastPathComponent)
        // On any exit: a leftover partial is swept (on success it's already moved).
        defer { try? FileManager.default.removeItem(at: partial) }

        // `.notice`, not `.debug`: this is the longest and least reliable step in
        // the whole app, and the report it has to answer — "it said it updated and
        // nothing changed" — arrives hours later, when only persisted levels are
        // still readable. Host only, never the path or query: a licensed feed
        // carries its key in the query (CleanShot), and a signed URL can carry one
        // in a path segment instead — which is exactly why `Redactor.host` exists.
        // Which app and which version this is for is already on the
        // `InstallCoordinator` line above it.
        Log.install.notice("download start: \(Redactor.host(url), privacy: .public)")
        let started = Date()

        var lastError: Error = URLError(.unknown)
        for attempt in 0..<maxAttempts {
            do {
                let result = try await runAttempt(url: url, headers: headers, partial: partial)
                let secs = Date().timeIntervalSince(started)
                Log.install.notice(
                    "download ok: \(self.bytesDownloaded, privacy: .public) bytes transferred in \(Int(secs), privacy: .public)s from \(Redactor.host(url), privacy: .public) (attempt \(attempt + 1, privacy: .public))")
                return result
            } catch {
                lastError = error
                // Bytes already on disk: the next attempt resumes from here, so it
                // is the one number that says whether a retry is making progress.
                let attrs = try? FileManager.default.attributesOfItem(atPath: partial.path)
                let onDisk = (attrs?[.size] as? Int64) ?? 0
                // Only transient mid-transfer failures are worth another pass; the
                // partial file persists so the next attempt resumes from it.
                guard attempt < maxAttempts - 1, Self.isTransient(error) else {
                    Log.install.error(
                        "download failed: \(Redactor.host(url), privacy: .public) after attempt \(attempt + 1, privacy: .public)/\(self.maxAttempts, privacy: .public), \(onDisk, privacy: .public) bytes on disk, transient=\(Self.isTransient(error), privacy: .public) — \(error.localizedDescription, privacy: .public)")
                    throw error
                }
                Log.install.notice(
                    "download retry \(attempt + 1, privacy: .public)/\(self.maxAttempts, privacy: .public): resuming from \(onDisk, privacy: .public) bytes on disk — \(error.localizedDescription, privacy: .public)")
                // Brief, growing backoff (0.5s, 1.0s, …) so we don't hammer a CDN
                // that's momentarily resetting connections.
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
            }
        }
        Log.install.error(
            "download gave up: \(Redactor.host(url), privacy: .public) after \(self.maxAttempts, privacy: .public) attempts — \(lastError.localizedDescription, privacy: .public)")
        throw lastError
    }

    /// One request/response cycle: (re)issue the GET — ranged if a partial exists —
    /// and stream the body into the partial file. Returns the finalized file on
    /// success; throws on failure (the caller decides whether to resume).
    private func runAttempt(url: URL, headers: [String: String], partial: URL) async throws -> URL {
        let existing = (try? FileManager.default
            .attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? 0

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
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
            if let validator = resumeValidator {
                request.setValue(validator, forHTTPHeaderField: "If-Range")
            }
        }

        attemptStartOffset = existing
        writtenOffset = existing
        totalExpected = 0
        declaredTotal = nil
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
            if status == 206 {
                // A 206 is only ever joined onto the partial on the strength of its
                // Content-Range. RFC 9110 §15.3.7.1 requires the header on a
                // single-part 206; without it (or with one that is invalid, §14.4)
                // there is no way to know where these bytes belong — appending is
                // the double-append in #225, writing from zero is a different
                // corruption — so the response is rejected. Not retried: the same
                // request would draw the same answer.
                let raw = http?.value(forHTTPHeaderField: "Content-Range")
                guard let raw, let range = Self.parseContentRange(raw) else {
                    throw DownloadError.badPartialContent(
                        raw.map { "invalid Content-Range '\($0)'" } ?? "no Content-Range")
                }
                declaredTotal = range.total
                if attemptStartOffset > 0, range.first == attemptStartOffset {
                    // Server honoured our range — append to what we already have.
                    totalExpected = range.total
                        ?? (attemptStartOffset + max(0, response.expectedContentLength))
                    let handle = try FileHandle(forWritingTo: partialURL!)
                    try handle.seekToEnd()
                    fileHandle = handle
                    writtenOffset = attemptStartOffset
                } else if range.first == 0 {
                    // The whole object from byte zero, just labelled 206: a server
                    // that ignored our range but kept the status, or an always-206
                    // proxy answering a request that carried no Range. Same as a
                    // 200 — discard the partial and start fresh.
                    totalExpected = range.total
                        ?? effectiveTotal(response.expectedContentLength, response: response)
                    try startFresh(from: http)
                } else {
                    throw DownloadError.badPartialContent(
                        "Content-Range starts at \(range.first), \(attemptStartOffset) bytes on disk")
                }
            } else if status == 200 || http == nil {
                // Fresh download, or the server ignored our range and re-sent the
                // whole body: discard any partial bytes and start from zero so we
                // never append a full body onto a partial one.
                totalExpected = effectiveTotal(response.expectedContentLength, response: response)
                try startFresh(from: http)
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
        // A clean close only means "done" when the server's own declared length
        // agrees. A ranged answer may legitimately stop short of the remainder
        // (a CDN's per-request cap, a proxy that closes politely at a timeout),
        // and URLSession has no reason to complain: its Content-Length was
        // honest. Before #225 that short file was finalized as the download.
        // Short is transient — the next attempt asks for `bytes=<writtenOffset>-`;
        // long (more bytes than the object has) is not, and fails here.
        if let total = declaredTotal, writtenOffset != total {
            finish(.failure(DownloadError.lengthMismatch(received: writtenOffset, expected: total)))
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

    /// Start the partial file over from byte zero for a response that carries the
    /// whole object, and adopt that response's validator for later resumes: the
    /// old one described bytes that are being thrown away.
    private func startFresh(from http: HTTPURLResponse?) throws {
        try? FileManager.default.removeItem(at: partialURL!)
        FileManager.default.createFile(atPath: partialURL!.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: partialURL!)
        writtenOffset = 0
        resumeValidator = Self.strongValidator(http)
    }

    /// The validator to send back as `If-Range`, per RFC 9110 §13.1.5: an entity
    /// tag unless it is weak (`W/…`), and a `Last-Modified` date only when the
    /// server gave no entity tag at all — a weak tag is still a tag, and it says
    /// the server cannot promise byte-identity, which is the one thing a resume
    /// needs. (The section also asks the date to be "strong" in the sense of
    /// §8.8.2.2, i.e. at least a minute older than the response's `Date`; not
    /// checked here. The failure mode of a too-fresh date is the one we already
    /// live with today without `If-Range` at all.)
    private static func strongValidator(_ http: HTTPURLResponse?) -> String? {
        guard let http else { return nil }
        if let etag = http.value(forHTTPHeaderField: "ETag")?
            .trimmingCharacters(in: .whitespaces), !etag.isEmpty {
            return etag.hasPrefix("W/") ? nil : etag
        }
        if let date = http.value(forHTTPHeaderField: "Last-Modified")?
            .trimmingCharacters(in: .whitespaces), !date.isEmpty {
            return date
        }
        return nil
    }

    /// A parsed `Content-Range: bytes <first>-<last>/<total>`; `total` is nil
    /// for `*`.
    struct ContentRange: Equatable {
        let first: Int64
        let last: Int64
        let total: Int64?
    }

    /// Parse a `Content-Range` value. Nil when it is not a byte range, is the
    /// `*/<total>` form (only meaningful on a 416), or is invalid in the RFC 9110
    /// §14.4 sense — last-pos below first-pos, or a total at or below last-pos —
    /// which a recipient "MUST NOT attempt to recombine" with what it has.
    static func parseContentRange(_ value: String) -> ContentRange? {
        let parts = value.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bytes" else { return nil }
        let spec = parts[1].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard spec.count == 2 else { return nil }
        let bounds = spec[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2,
              let first = Int64(bounds[0].trimmingCharacters(in: .whitespaces)),
              let last = Int64(bounds[1].trimmingCharacters(in: .whitespaces)),
              last >= first else { return nil }
        let totalText = spec[1].trimmingCharacters(in: .whitespaces)
        if totalText == "*" { return ContentRange(first: first, last: last, total: nil) }
        guard let total = Int64(totalText), total > last else { return nil }
        return ContentRange(first: first, last: last, total: total)
    }

    /// Failures worth another attempt from the partial file: a `URLError` for a
    /// connection the network/proxy/CDN dropped while bytes were flowing, or a
    /// clean close that left the file short of the server's declared total. Not
    /// a definitive "this won't work" answer.
    private static func isTransient(_ error: Error) -> Bool {
        if case .lengthMismatch(let received, let expected) = error as? DownloadError {
            return received < expected
        }
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
