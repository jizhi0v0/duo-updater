import AppKit
import WebKit
import DuoUpdaterCore

/// A small `NSWindow` hosting a `WKWebView` on `AppleDeveloperSession`'s store,
/// for the user to sign in to their Apple Developer account (including 2FA).
///
/// Not a SwiftUI `Window` scene: it's opened on demand from a settings-page or
/// row button, and it needs to report completion back to a caller rather than just
/// existing. A plain `NSWindow` plus a completion closure fits that better than
/// wiring a new scene and a deep-link round trip through `AppListModel`.
///
/// Closing the window (the traffic-light or ⌘W) means cancel — the completion
/// handler runs with `false` — so a signed-in host never mistakes an abandoned
/// window for a giveup that also happened to succeed.
@MainActor
final class AppleDeveloperSignInWindow: NSObject {
    private static let signInURL = URL(string: "https://developer.apple.com/account")!

    private var window: NSWindow?
    private var webView: WKWebView?
    private var completion: ((Bool) -> Void)?
    /// So a navigation-finished callback after the window already reported
    /// completion (e.g. a second `didFinish` racing the close) can't call the
    /// handler twice.
    private var finished = false
    /// When the developer site first answered with a page of its own — for the
    /// log line that says how soon after it the window closed.
    private var landedAt: Date?

    /// Show the window and sign the user in. Resumes once with `true` after a
    /// completed sign-in (saved), or `false` if the user closes the window first.
    func present() async -> Bool {
        await withCheckedContinuation { continuation in
            present { signedIn in continuation.resume(returning: signedIn) }
        }
    }

    private func present(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        finished = false

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = AppleDeveloperSession.shared.dataStore
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 720), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = String(localized: "Sign In to Apple Developer")
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        webView.load(URLRequest(url: Self.signInURL))

        // Same activation shape as DuoUpdater's other top-level windows
        // (`AppListModel.windowAppeared`/`surfaceWindow`): as an accessory
        // (menu-bar) app, a freshly created window does not reliably come to the
        // front on its own.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func finish(signedIn: Bool) {
        guard !finished else { return }
        finished = true
        window?.delegate = nil
        window?.close()
        window = nil
        webView?.navigationDelegate = nil
        webView = nil
        let completion = self.completion
        self.completion = nil
        completion?(signedIn)
    }
}

extension AppleDeveloperSignInWindow: WKNavigationDelegate {
    /// The developer site's page has started to arrive — seconds before the
    /// rest of it (scripts, styles, API calls) has loaded, which is what
    /// `didFinish` waits for. Once a sign-in has come back from `idmsa`, the
    /// session cookie is already in the store, so Apple can be asked now. A
    /// commit that comes too early (signed out, or a page that goes on to
    /// `idmsa`) only asks and gets no "signed in"; nothing closes.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        confirmIfLanded(webView, on: "commit")
    }

    /// Kept as the fallback: if the check at commit did not confirm a
    /// session, the one here still can.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        confirmIfLanded(webView, on: "finish")
    }

    private func confirmIfLanded(_ webView: WKWebView, on event: String) {
        guard !finished, let host = webView.url?.host, host.hasSuffix("developer.apple.com") else { return }
        if landedAt == nil { landedAt = Date() }
        Task {
            let session = AppleDeveloperSession.shared
            guard await session.refreshSignedInState() else { return }
            // A `myacinfo` left over from an ended session is still a cookie;
            // ask Apple before calling this a sign-in. `check()` saves and
            // stamps `lastConfirmed` only on a real "signed in".
            guard await session.check(renewing: false) != .expired else { return }
            await session.save()
            guard !self.finished else { return }
            let seconds = self.landedAt.map { Date().timeIntervalSince($0) } ?? 0
            Log.app.notice("apple sign-in: window closed on \(event, privacy: .public), \(seconds, format: .fixed(precision: 1), privacy: .public)s after the developer site answered")
            self.finish(signedIn: true)
        }
    }
}

extension AppleDeveloperSignInWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // A close the user triggered directly (traffic light / ⌘W) rather than
        // `finish(signedIn:)` calling `window.close()` itself — `finished` is
        // already true in the latter case, so this is a no-op there.
        finish(signedIn: false)
    }
}
