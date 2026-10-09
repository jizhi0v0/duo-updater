import Foundation
import WebKit
import DuoUpdaterCore

/// Loads the developer site once in a web view that is in no window, on the
/// session's own store, and reports whether the page came back to the developer
/// site (`AppleDeveloperSessionRenewal`). Whether that means signed in is for
/// the caller to ask Apple — this only drives the page.
///
/// Nothing is shown and nothing can be typed: if Apple wants a password, the
/// form sits unseen until `timeout` and the web view is thrown away.
@MainActor
final class AppleDeveloperSessionRenewer: NSObject {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var started = Date()

    /// Every navigation event of the run, in order, for the renewal's log line:
    /// seconds since the load, the event, and host + path — never the query,
    /// which on `idmsa` can carry tokens. A renewal that failed in 30 s on
    /// 2026-10-09 and succeeded in 14 s two minutes later in a fresh process
    /// left only "stayed on sign-in" to go on.
    private(set) var trail: [String] = []

    /// True once a page finished on the developer site, false at the timeout.
    func run(in store: WKWebsiteDataStore) async -> Bool {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 720), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        started = Date()

        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: AppleDeveloperSessionRenewal.timeout)
            guard !Task.isCancelled, let self else { return }
            self.note("timeout", self.webView?.url)
            self.finish(false)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: AppleDeveloperSessionRenewal.startURL))
        }
    }

    private func finish(_ landed: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(returning: landed)
    }

    private func note(_ event: String, _ url: URL?, _ error: Error? = nil) {
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        let place = url.map { "\($0.host ?? "?")\($0.path)" } ?? "-"
        let failure = (error as NSError?).map { " (\($0.domain) \($0.code))" } ?? ""
        trail.append("+\(seconds)s \(event) \(place)\(failure)")
    }
}

extension AppleDeveloperSessionRenewer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        note("redirect", webView.url)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        note("commit", webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        note("finish", webView.url)
        // A finish on the sign-in form is a step, not an end: with `acsso` the
        // form's own script moves on a second later (measured 2026-09-23).
        if AppleDeveloperSessionRenewal.hasLanded(host: webView.url?.host) { finish(true) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        note("fail", webView.url, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        note("provisional fail", webView.url, error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        note("web content process terminated", webView.url)
    }
}
