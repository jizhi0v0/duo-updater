import Foundation
import Testing
@testable import DuoUpdaterCore

struct DetectionOnlyAffordanceTests {

    /// Regression for #197: a detection-only result with no page at all must
    /// resolve to the reveal-in-Finder affordance, not "openPage" with some
    /// placeholder URL and not a title that still says "Open" for an action that
    /// actually reveals the app in Finder.
    @Test func noPageURLRevealsInFinder() {
        let affordance = DetectionOnlyAffordance.resolve(pageURL: nil)

        #expect(affordance == .revealInFinder)
        #expect(affordance.buttonTitle == "Reveal in Finder")
    }

    @Test func pageURLOpensThatPage() {
        let url = URL(string: "https://example.com/download")!
        let affordance = DetectionOnlyAffordance.resolve(pageURL: url)

        #expect(affordance == .openPage(url))
        #expect(affordance.buttonTitle == "Open")
    }

    /// The two cases must never share a title — that's exactly the bug: the
    /// button said "Open" regardless of which action it actually performed.
    @Test func titlesDifferBetweenCases() {
        let withPage = DetectionOnlyAffordance.resolve(pageURL: URL(string: "https://example.com")!)
        let withoutPage = DetectionOnlyAffordance.resolve(pageURL: nil)

        #expect(withPage.buttonTitle != withoutPage.buttonTitle)
    }
}
