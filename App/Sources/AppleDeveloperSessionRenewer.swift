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

    /// True once a page finished on the developer site, false at the timeout.
    func run(in store: WKWebsiteDataStore) async -> Bool {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 720), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: AppleDeveloperSessionRenewal.timeout)
            guard !Task.isCancelled else { return }
            self?.finish(false)
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
}

extension AppleDeveloperSessionRenewer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A finish on the sign-in form is a step, not an end: with `acsso` the
        // form's own script moves on a second later (measured 2026-09-23).
        if AppleDeveloperSessionRenewal.hasLanded(host: webView.url?.host) { finish(true) }
    }
}
