import AppKit
import Testing

/// Asks the Objective-C runtime which WebKit callbacks the Xcode downloader has
/// really registered.
///
/// WebKit finds a delegate's methods by selector. A Swift method that only
/// "nearly matches" a protocol requirement compiles, is never exposed, and is
/// never called — which is how the first real install failed on 2026-09-22:
/// `decidePolicyFor navigationResponse` sat outside the conformance with a
/// slightly different signature, WebKit cancelled the `.xip` itself, and every
/// download ended at 0% with "Frame load interrupted". No test that calls the
/// method directly can see that; only `responds(to:)` can.
@MainActor
struct DownloadJobDelegateTests {

    nonisolated static let downloadJobSelectors = [
        "webView:decidePolicyForNavigationResponse:decisionHandler:",
        "webView:navigationResponse:didBecomeDownload:",
        "webView:didFinishNavigation:",
        "webView:didFailNavigation:withError:",
        "webView:didFailProvisionalNavigation:withError:",
        "download:decideDestinationUsingResponse:suggestedFilename:completionHandler:",
        "downloadDidFinish:",
        "download:didFailWithError:resumeData:",
    ]

    @Test(arguments: downloadJobSelectors)
    func theDownloaderAnswers(_ selector: String) {
        let job = DownloadJob(
            session: AppleDeveloperSession.shared,
            directory: URL(fileURLWithPath: "/ZZFixture/xcode-download"),
            progress: { _ in })
        #expect(job.responds(to: NSSelectorFromString(selector)))
    }

    @Test(arguments: ["webView:didFinishNavigation:", "windowWillClose:"])
    func theSignInWindowAnswers(_ selector: String) {
        #expect(AppleDeveloperSignInWindow().responds(to: NSSelectorFromString(selector)))
    }
}

/// Every page that finishes loading must lead somewhere: sign-in, or an error.
/// A page left unanswered is an install that never returns and a download
/// permit that is never given back (PR #803 review, round 1).
struct DownloadJobDeadEndTests {

    @Test func aPageOffIdmsaIsAnErrorNotAWait() {
        for host in ["developer.apple.com", "download.developer.apple.com", "www.apple.com", nil] as [String?] {
            #expect(DownloadJob.finishedPageOutcome(
                host: host, signInInFlight: false, reloadedAfterSignIn: false) == .unexpectedPage)
        }
    }

    @Test func idmsaAsksForSignInOnceThenGivesUp() {
        #expect(DownloadJob.finishedPageOutcome(
            host: "idmsa.apple.com", signInInFlight: false, reloadedAfterSignIn: false) == .presentSignIn)
        #expect(DownloadJob.finishedPageOutcome(
            host: "idmsa.apple.com", signInInFlight: false, reloadedAfterSignIn: true) == .signInDidNotStick)
        // Not a lookalike host.
        #expect(DownloadJob.finishedPageOutcome(
            host: "notidmsa.apple.com", signInInFlight: false, reloadedAfterSignIn: false) == .unexpectedPage)
    }

    @Test func nothingIsDecidedWhileTheSignInWindowIsUp() {
        for host in ["idmsa.apple.com", "developer.apple.com"] {
            #expect(DownloadJob.finishedPageOutcome(
                host: host, signInInFlight: true, reloadedAfterSignIn: false) == .ignore)
        }
    }

    @Test func onlyASuccessfulPageIsRendered() {
        #expect(DownloadJob.pageResponseIsLoadable(status: 200))
        for status in [301, 401, 403, 404, 500, 503] {
            #expect(!DownloadJob.pageResponseIsLoadable(status: status))
        }
    }
}
