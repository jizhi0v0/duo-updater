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
    private let session: AppleDeveloperSession

    init(session: AppleDeveloperSession = .shared) {
        self.session = session
    }

    func downloadXcodeArchive(
        from authorizedURL: URL,
        into directory: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> XcodeArchiveDownload {
        await session.restore()
        let job = DownloadJob(session: session, directory: directory, progress: progress)
        return try await job.run(authorizedURL: authorizedURL)
    }
}

/// One in-flight download's state. A fresh instance per call, so concurrent
/// downloads (unlikely today, but the protocol doesn't rule it out) never share
/// a web view or a continuation.
@MainActor
private final class DownloadJob: NSObject {
    private let session: AppleDeveloperSession
    private let directory: URL
    private let onProgress: @Sendable (Double) -> Void

    private var window: NSWindow?
    private var webView: WKWebView?
    private var download: WKDownload?
    private var progressObservation: NSKeyValueObservation?

    private var continuation: CheckedContinuation<XcodeArchiveDownload, Error>?
    private var finished = false

    private var authorizedURL: URL!
    private var reloadedAfterSignIn = false
    /// Set synchronously — before the `Task` that presents the sign-in window
    /// even starts — so a second `didFinish` on idmsa while that window is
    /// still up (WebKit can re-fire `didFinish` more than once for the same
    /// page) can't open a second one.
    private var signInInFlight = false
    private var expectedFinalHost: String?
    private var destinationURL: URL?

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

    init(session: AppleDeveloperSession, directory: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.session = session
        self.directory = directory
        self.onProgress = progress
    }

    func run(authorizedURL: URL) async throws -> XcodeArchiveDownload {
        self.authorizedURL = authorizedURL
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = session.dataStore
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
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        expectingDownloadHandoff = false
        self.download = download
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let host = webView.url?.host, host.hasSuffix("idmsa.apple.com") else { return }
        guard !signInInFlight else { return }
        guard !reloadedAfterSignIn else {
            // We already completed one sign-in round trip for this call and
            // landed back on idmsa anyway — the user really did sign in, so
            // this is not a cancellation. Say what actually happened.
            fail(signInDidNotStickError())
            return
        }
        signInInFlight = true
        Task {
            let window = AppleDeveloperSignInWindow()
            let signedIn = await window.present()
            self.signInInFlight = false
            guard !self.finished else { return }
            guard signedIn else {
                self.fail(CancellationError())
                return
            }
            self.reloadedAfterSignIn = true
            webView.load(URLRequest(url: self.authorizedURL))
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

    private func signInDidNotStickError() -> Error {
        NSError(
            domain: "com.duoupdater.app.XcodeDownload",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: String(
                localized: "You signed in, but Apple's developer site asked for another sign-in right away. Try again from Settings → Xcode.")])
    }
}

// Split into its own extension: the compiler otherwise warns that this
// completion-handler overload "nearly matches" `WKNavigationDelegate`'s
// `async -> WKNavigationResponsePolicy` requirement, even though it resolves
// unambiguously (WebKit calls the completion-handler form when one is
// provided).
extension DownloadJob {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let http = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }
        let url = http.url ?? navigationResponse.response.url
        let looksLikeFile = !navigationResponse.canShowMIMEType || (url?.path.hasSuffix(".xip") ?? false)

        guard looksLikeFile else {
            decisionHandler(.allow)
            return
        }
        guard http.statusCode == 200 else {
            decisionHandler(.cancel)
            fail(networkRefusalError(status: http.statusCode))
            return
        }
        expectedFinalHost = url?.host
        expectingDownloadHandoff = true
        decisionHandler(.download)
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

        progressObservation = download.progress.observe(\.fractionCompleted, options: [.new]) { [onProgress] progress, _ in
            onProgress(progress.fractionCompleted)
        }

        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destinationURL else {
            fail(NSError(domain: "com.duoupdater.app.XcodeDownload", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Download finished with no destination."]))
            return
        }
        let bytes = download.progress.completedUnitCount
        Task {
            // The response that just got authorized is exactly the moment a
            // fresh session/auth cookie shows up — save it per the task's brief.
            await self.session.save()
            self.succeed(XcodeArchiveDownload(
                fileURL: destinationURL, bytesDownloaded: bytes, finalHost: self.expectedFinalHost))
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        fail(error)
    }
}
