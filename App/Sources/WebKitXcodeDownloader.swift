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
        guard let http = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }
        let url = http.url ?? navigationResponse.response.url
        let looksLikeFile = !navigationResponse.canShowMIMEType || (url?.path.hasSuffix(".xip") ?? false)

        guard looksLikeFile else {
            // An error page is a dead end, not something to load and wait on:
            // nothing below would ever resume the caller for it.
            guard Self.pageResponseIsLoadable(status: http.statusCode) else {
                decisionHandler(.cancel)
                fail(networkRefusalError(status: http.statusCode))
                return
            }
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
        // The 102 that follows `.download` is swallowed as the handoff; if the
        // `WKDownload` then never attaches, nothing else would resume the caller.
        // Measured: handoff, destination and first progress land within one
        // second, so 30 s is only a backstop.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.handoffDeadlineSeconds))
            guard let self, !self.finished, self.download == nil else { return }
            self.fail(self.handoffStalledError())
        }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        expectingDownloadHandoff = false
        self.download = download
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // No page is meant to finish loading here: the authorized URL redirects
        // either to the CDN (and becomes a download) or to idmsa (sign-in),
        // measured 2026-09-22. A page anywhere else is a dead end — say so,
        // rather than leave the caller waiting on a continuation forever.
        switch Self.finishedPageOutcome(
            host: webView.url?.host, signInInFlight: signInInFlight,
            reloadedAfterSignIn: reloadedAfterSignIn) {
        case .ignore: return
        case .unexpectedPage: fail(unexpectedPageError()); return
        // We already completed one sign-in round trip for this call and landed
        // back on idmsa anyway — the user really did sign in, so this is not a
        // cancellation. Say what actually happened.
        case .signInDidNotStick: fail(signInDidNotStickError()); return
        case .presentSignIn: break
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

    private static let handoffDeadlineSeconds = 30

    /// What a page that finished loading in the main frame means. Pure, so the
    /// dead-end cases are testable without loading a page.
    enum FinishedPageOutcome: Equatable {
        case ignore, presentSignIn, signInDidNotStick, unexpectedPage
    }

    nonisolated static func finishedPageOutcome(
        host: String?, signInInFlight: Bool, reloadedAfterSignIn: Bool
    ) -> FinishedPageOutcome {
        if signInInFlight { return .ignore }
        guard let host, host == "idmsa.apple.com" || host.hasSuffix(".idmsa.apple.com") else {
            return .unexpectedPage
        }
        return reloadedAfterSignIn ? .signInDidNotStick : .presentSignIn
    }

    /// A non-file response we let the web view render: only a success. An error
    /// page would load, finish, and leave nothing to resume the caller.
    nonisolated static func pageResponseIsLoadable(status: Int) -> Bool {
        (200..<300).contains(status)
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

    private func signInDidNotStickError() -> Error {
        NSError(
            domain: "com.duoupdater.app.XcodeDownload",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: String(
                localized: "You signed in, but Apple's developer site asked for another sign-in right away. Try again from Settings → Xcode.")])
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
