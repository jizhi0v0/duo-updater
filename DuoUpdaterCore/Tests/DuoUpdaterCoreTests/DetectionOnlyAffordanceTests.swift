import Foundation
import Testing
@testable import DuoUpdaterCore

struct DetectionOnlyAffordanceTests {

    /// Regression for #197: a detection-only result with no page at all must
    /// resolve to the reveal-in-Finder affordance — not "openPage" with some
    /// placeholder URL, and not silently render nothing the way the workbench
    /// used to.
    @Test func noPageURLRevealsInFinder() {
        let affordance = DetectionOnlyAffordance.resolve(pageURL: nil)

        #expect(affordance == .revealInFinder)
    }

    @Test func pageURLResolvesToThatExactPage() {
        let url = URL(string: "https://example.com/download")!
        let affordance = DetectionOnlyAffordance.resolve(pageURL: url)

        #expect(affordance == .openPage(url))
    }

    /// An app's own deep link (Chrome's `chrome://settings/help`) is handed to the
    /// app, in both windows — the workbench used to give it to a plain open.
    /// Mutation: drop the scheme check in `resolve` → `.openPage`, red.
    @Test func anAppSchemeOpensInTheApp() {
        let url = URL(string: "chrome://settings/help")!

        #expect(DetectionOnlyAffordance.resolve(pageURL: url) == .openInApp(url))
        #expect(DetectionOnlyAffordance.resolve(pageURL: URL(string: "http://example.com")!)
                == .openPage(URL(string: "http://example.com")!))
    }

    /// `.revealInFinder`'s title is the one piece of copy this type does own
    /// (every host renders it identically) — pin it so a future edit can't
    /// silently swap it back to something that claims to "Open" like #197 did.
    @Test func revealInFinderTitleReadsAsReveal() {
        #expect(DetectionOnlyAffordance.revealInFinderTitle == "Reveal in Finder")
    }
}
