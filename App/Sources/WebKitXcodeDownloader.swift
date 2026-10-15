import AppKit
import WebKit
import DuoUpdaterCore

/// Fetches an Xcode `.xip` through the Apple Developer sign-in session held by
/// `AppleDeveloperSession`, per the `XcodeArchiveDownloading` seam core declares.
///
/// One `WKWebView` per call, hosted in an off-screen `NSWindow` — never ordered
/// front, so nothing appears on the user's screen. WebKit's own download support
/// (`decidePolicyFor:navigationResponse:` → `.download`, then `WKDownloadDelegate`)
/// was verified end-to-end with a *visible* probe window (2026-09-22); whether a
/// web view with no window at all can still download is not documented anywhere
/// in WebKit's API reference, and `WKWebView` layout/rendering in general assumes
/// it is hosted somewhere — so this plays it safe with a real, off-screen window
/// rather than a bare, unhosted `WKWebView`.
@MainActor
final class WebKitXcodeDownloader: NSObject, XcodeArchiveDownloading, @unchecked Sendable {
    /// Nonisolated so `AppListModel`'s static `InstallCoordinator` can be built
    /// with one; the session is reached on the main actor, per call.
    nonisolated override init() {}

    func downloadXcodeArchive(
        from authorizedURL: URL,
        into directory: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> XcodeArchiveDownload {
        let session = AppleDeveloperSession.shared
        await session.restore()
        let job = DownloadJob(session: session, directory: directory, progress: progress)
        return try await job.run(authorizedURL: authorizedURL)
    }
}

/// One in-flight download's state. A fresh instance per call, so concurrent
/// downloads (unlikely today, but the protocol doesn't rule it out) never share
/// a web view or a continuation.
@MainActor
final class DownloadJob: NSObject {
    private let dataStore: WKWebsiteDataStore
    /// Apple sent the request to sign-in instead: the session has expired.
    private let onExpired: () -> Void
    /// A download finished: the response that authorized it may have brought a
    /// fresh session cookie, so this is when the session gets saved.
    private let onAuthorized: () async -> Void
    private let directory: URL
    private let onProgress: @Sendable (Double) -> Void

    private var window: NSWindow?
    private var webView: WKWebView?
    private var download: WKDownload?
    private var progressObservation: NSKeyValueObservation?

    private var continuation: CheckedContinuation<XcodeArchiveDownload, Error>?
    private var finished = false

    private var expectedFinalHost: String?
    private var destinationURL: URL?
    /// The first response's `Content-Length` (-1 when it sent none). A resumed
    /// download never asks for a destination again, so this stays the full size.
    private var expectedLength: Int64 = -1

    /// `WKDownload`s attached so far: the first, plus one per resume. Counts
    /// attempts the way `Downloader` does, against `DownloadRetryPolicy`.
    private var attempts = 0

    /// Set synchronously the moment `decidePolicyFor:navigationResponse:`
    /// answers `.download`, cleared once the handoff either lands
    /// (`didBecome download`) or is dealt with. Guards against a WebKit quirk
    /// measured 2026-09-22: answering `.download` makes WebKit immediately fail
    /// the *same* navigation with `WebKitErrorDomain` code 102 ("Frame load
    /// interrupted" / `WKError.frameLoadInterruptedByPolicyChange`) — logged in
    /// this order, same timestamp:
    ///   AUTHORIZED: downloading
    ///   provisional fail WebKitErrorDomain 102 Frame load interrupted
    ///   download -> …/Xcode_27_Release_Candidate.xip (expected 2014229334)
    ///   download 0% … DOWNLOAD FINISHED
    /// That failure is WebKit telling us the *page* load was interrupted
    /// because it turned into a download — not a real failure — so it must not
    /// reach `fail(_:)`. Only 102 while this flag is set is treated that way; a
    /// 102 with the flag clear is a genuine navigation failure.
    private var expectingDownloadHandoff = false

    /// `WebKitErrorDomain` doesn't have a public Swift constant for 102
    /// specifically as a plain NSError domain string (WKError's domain is
    /// `WKErrorDomain`, a different string) — matched by the values logged in
    /// the 2026-09-22 probe.
    private static let webKitErrorDomain = "WebKitErrorDomain"
    private static let frameLoadInterruptedCode = 102

    init(
        dataStore: WKWebsiteDataStore,
        directory: URL,
        progress: @escaping @Sendable (Double) -> Void,
        onExpired: @escaping () -> Void,
        onAuthorized: @escaping () async -> Void
    ) {
        self.dataStore = dataStore
        self.directory = directory
        self.onProgress = progress
        self.onExpired = onExpired
        self.onAuthorized = onAuthorized
    }

    convenience init(session: AppleDeveloperSession, directory: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.init(
            dataStore: session.dataStore,
            directory: directory,
            progress: progress,
            onExpired: { session.noteExpired() },
            onAuthorized: {
                await session.save()
                session.noteConfirmed()
            })
    }

    func run(authorizedURL: URL) async throws -> XcodeArchiveDownload {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        // Off-screen and never ordered front — see the type-level doc comment.
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true)
        window.contentView = webView
        window.setIsVisible(false)
        self.window = window

        webView.load(URLRequest(url: authorizedURL))

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                _ = await self.download?.cancel()
                self.fail(CancellationError())
            }
        }
    }

    // MARK: - Completion

    private func succeed(_ result: XcodeArchiveDownload) {
        guard !finished else { return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        teardown()
        continuation?.resume(returning: result)
    }

    private func fail(_ error: Error) {
        guard !finished else { return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        teardown()
        continuation?.resume(throwing: error)
    }

    private func teardown() {
        progressObservation?.invalidate()
        progressObservation = nil
        webView?.navigationDelegate = nil
        webView = nil
        window?.contentView = nil
        window = nil
        download = nil
    }

    /// A response the caller should hear about as "download refused", not
    /// "session expired" — a proxy or network fault, not an auth one. CDN `403`s
    /// (server `kngx`) were observed during unrelated proxy misbehavior on
    /// 2026-09-22, so this is deliberately worded to point there first.
    private func networkRefusalError(status: Int) -> Error {
        NSError(
            domain: "com.duoupdater.app.XcodeDownload",
            code: status,
            userInfo: [NSLocalizedDescriptionKey: String(
                localized: "Apple's download server refused the request. Check your network connection or proxy, then try again.")])
    }
}

// MARK: - WKNavigationDelegate

extension DownloadJob: WKNavigationDelegate {
    // In the extension that declares the conformance, with the SDK's exact
    // signature. It used to sit in a plain `extension DownloadJob` with a
    // `decisionHandler` lacking `@MainActor @Sendable`: the compiler warned it
    // "nearly matches" the requirement, the method was never exposed to
    // Objective-C, and WebKit — never asked — cancelled the unshowable `.xip`
    // itself with the same 102 the handoff guard expects, so every download failed
    // (2026-09-22, first real install). `DownloadJobDelegateTests` asks the runtime.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let http = navigationResponse.response as? HTTPURLResponse
        let url = http?.url ?? navigationResponse.response.url
        switch Self.responseDecision(
            isForMainFrame: navigationResponse.isForMainFrame,
            status: http?.statusCode,
            canShowMIMEType: navigationResponse.canShowMIMEType,
            path: url?.path ?? "") {
        case .allow:
            decisionHandler(.allow)
            return
        case .refuse(let status):
            decisionHandler(.cancel)
            fail(networkRefusalError(status: status))
            return
        case .download:
            break
        }
        expectedFinalHost = url?.host
        expectingDownloadHandoff = true
        decisionHandler(.download)
        // The 102 that follows `.download` is swallowed as the handoff; if the
        // `WKDownload` then never attaches, nothing else would resume the caller.
        // Measured: handoff, destination and first progress land within one
        // second, so 30 s is only a backstop.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.handoffDeadlineSeconds))
            guard let self, !self.finished, self.attempts == 0 else { return }
            self.fail(self.handoffStalledError())
        }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        expectingDownloadHandoff = false
        attach(download)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // No page is meant to finish loading here: the authorized URL redirects
        // either to the CDN (and becomes a download) or to idmsa (sign-in),
        // measured 2026-09-22. A page anywhere else is a dead end — say so,
        // rather than leave the caller waiting on a continuation forever.
        switch Self.finishedPageOutcome(host: webView.url?.host) {
        case .unexpectedPage:
            fail(unexpectedPageError())
        case .sessionExpired:
            // No sign-in window from here: a download the user clicked is not a
            // moment to be ambushed by one. The row turns to "Sign In…" instead,
            // and nothing has been downloaded.
            onExpired()
            fail(sessionExpiredError())
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if consumeExpectedDownloadHandoffFailure(error) { return }
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if consumeExpectedDownloadHandoffFailure(error) { return }
        fail(error)
    }

    /// True (and consumes the flag) when `error` is exactly the frame-load-
    /// interrupted failure WebKit raises for the navigation we just turned
    /// into a download — see `expectingDownloadHandoff`'s doc comment. Any
    /// other error, or the same error outside that window, is not swallowed.
    private func consumeExpectedDownloadHandoffFailure(_ error: Error) -> Bool {
        // `download != nil` as well as the flag: the probe logged the 102 before
        // the destination callback, but never logged where `didBecome download`
        // falls relative to it — if it comes first, the flag is already clear.
        guard expectingDownloadHandoff || download != nil else { return false }
        let nsError = error as NSError
        guard nsError.domain == Self.webKitErrorDomain,
              nsError.code == Self.frameLoadInterruptedCode
        else { return false }
        expectingDownloadHandoff = false
        return true
    }

    private static let handoffDeadlineSeconds = 30

    /// What a page that finished loading in the main frame means. Pure, so the
    /// dead-end cases are testable without loading a page.
    enum FinishedPageOutcome: Equatable {
        case sessionExpired, unexpectedPage
    }

    nonisolated static func finishedPageOutcome(host: String?) -> FinishedPageOutcome {
        guard let host, host == "idmsa.apple.com" || host.hasSuffix(".idmsa.apple.com") else {
            return .unexpectedPage
        }
        return .sessionExpired
    }

    enum ResponseDecision: Equatable {
        case allow, download, refuse(status: Int)
    }

    /// What to do with a navigation response. Pure, so it is testable without
    /// loading anything.
    ///
    /// Subframes are always allowed: the sign-in page embeds an iframe
    /// (`idmsa.apple.com/appleauth/auth/signin`), and this callback fires for it
    /// too — a failing subframe must not end the job. In the main frame, a file
    /// (not showable, or a `.xip` path) downloads on 200; anything else that is
    /// not 2xx is refused, because an error page would load, finish, and leave
    /// nothing to resume the caller.
    nonisolated static func responseDecision(
        isForMainFrame: Bool, status: Int?, canShowMIMEType: Bool, path: String
    ) -> ResponseDecision {
        guard isForMainFrame, let status else { return .allow }
        let looksLikeFile = !canShowMIMEType || path.hasSuffix(".xip")
        if looksLikeFile {
            return status == 200 ? .download : .refuse(status: status)
        }
        return (200..<300).contains(status) ? .allow : .refuse(status: status)
    }

    private func unexpectedPageError() -> Error {
        NSError(
            domain: "com.duoupdater.app.XcodeDownload",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: String(
                localized: "Apple's developer site answered with a page instead of the Xcode download. Try again; if it keeps happening, sign out and back in under Settings → Xcode.")])
    }

    private func handoffStalledError() -> Error {
        NSError(
            domain: "com.duoupdater.app.XcodeDownload",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: String(
                localized: "The Xcode download did not start. Try again.")])
    }

    private func incompleteDownloadError() -> Error {
        NSError(
            domain: "com.duoupdater.app.XcodeDownload",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: String(
                localized: "Apple's download server stopped sending the Xcode archive partway through. Try again.")])
    }

    /// The first bytes of a file that came out the wrong size, for the log: when
    /// a resume was refused, they are the server's own error page.
    nonisolated static func preview(of file: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "«unreadable»" }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 200)) ?? Data()
        return String(decoding: head, as: UTF8.self).debugDescription
    }

    private func sessionExpiredError() -> Error {
        NSError(
            domain: "com.duoupdater.app.XcodeDownload",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: AppleDeveloperSession.expiredMessage])
    }
}

// MARK: - WKDownloadDelegate

extension DownloadJob: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let destination = directory.appendingPathComponent(suggestedFilename)
        try? FileManager.default.removeItem(at: destination)
        destinationURL = destination
        expectedLength = response.expectedContentLength
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destinationURL else {
            fail(NSError(domain: "com.duoupdater.app.XcodeDownload", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Download finished with no destination."]))
            return
        }
        let bytes = download.progress.completedUnitCount
        // WebKit finishes a resumed download whatever the server answered: a
        // resume refused with a small error page (measured against a local
        // server, 2026-10-15) ends here with the page written over the whole
        // file and no error. Only the size the first response declared can tell.
        let onDisk = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? nil
        if expectedLength > 0, onDisk != expectedLength {
            Log.install.error(
                "xcode download incomplete: \(onDisk ?? -1, privacy: .public) of \(self.expectedLength, privacy: .public) bytes on disk after attempt \(self.attempts, privacy: .public) — starts with \(Self.preview(of: destinationURL), privacy: .public)")
            fail(incompleteDownloadError())
            return
        }
        Log.install.notice(
            "xcode download ok: \(bytes, privacy: .public) bytes from \(self.expectedFinalHost ?? "«unknown host»", privacy: .public) (attempt \(self.attempts, privacy: .public))")
        Task {
            // The response that just got authorized is exactly the moment a
            // fresh session/auth cookie shows up — save it per the task's brief.
            await self.onAuthorized()
            self.succeed(XcodeArchiveDownload(
                fileURL: destinationURL, bytesDownloaded: bytes, finalHost: self.expectedFinalHost))
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        // A stop already answered the caller; the cancel it sent lands here.
        guard !finished else { return }
        let host = expectedFinalHost ?? "«unknown host»"
        let bytes = download.progress.completedUnitCount
        let max = DownloadRetryPolicy.maxAttempts
        guard let resumeData,
              Self.shouldResume(after: error, attempts: attempts, hasResumeData: true) else {
            Log.install.error(
                "xcode download failed: \(host, privacy: .public) after attempt \(self.attempts, privacy: .public)/\(max, privacy: .public), \(bytes, privacy: .public) bytes, transient=\(DownloadRetryPolicy.isTransient(error), privacy: .public), resumeData=\(resumeData != nil, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            fail(error)
            return
        }
        Log.install.notice(
            "xcode download retry \(self.attempts, privacy: .public)/\(max, privacy: .public): resuming from \(bytes, privacy: .public) bytes — \(error.localizedDescription, privacy: .public)")
        progressObservation?.invalidate()
        progressObservation = nil
        self.download = nil
        // Same growing backoff as `Downloader` (0.5 s, 1.0 s, …).
        let delay = Duration.milliseconds(500 * attempts)
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            // A stop during the backoff has already answered the caller.
            guard let self, !self.finished, let webView = self.webView else { return }
            webView.resumeDownload(fromResumeData: resumeData) { [weak self] resumed in
                guard let self, !self.finished else {
                    resumed.cancel()
                    return
                }
                self.attach(resumed)
            }
        }
    }

    /// Whether a failed attempt is worth resuming: the failures and the attempt
    /// count `Downloader` uses, and only with WebKit's resume data in hand.
    /// `attempts` counts the attempts made so far, the failed one included.
    nonisolated static func shouldResume(after error: Error, attempts: Int, hasResumeData: Bool) -> Bool {
        hasResumeData && attempts < DownloadRetryPolicy.maxAttempts && DownloadRetryPolicy.isTransient(error)
    }

    /// Takes over a `WKDownload`, the first or a resumed one; each carries its
    /// own `progress`, so the observation moves with it.
    private func attach(_ download: WKDownload) {
        attempts += 1
        self.download = download
        download.delegate = self
        progressObservation?.invalidate()
        progressObservation = download.progress.observe(\.fractionCompleted, options: [.new]) { [onProgress] progress, _ in
            onProgress(progress.fractionCompleted)
        }
    }
}
