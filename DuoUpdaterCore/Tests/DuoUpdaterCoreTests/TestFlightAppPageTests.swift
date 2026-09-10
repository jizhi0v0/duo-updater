import Testing
import Foundation
@testable import DuoUpdaterCore

/// The URL the TestFlight buttons open. Pinned by shape, because the only witness
/// that it works is a measurement against a live TestFlight (see
/// `Frontier.appPageURL`), and nothing else would notice it changing.
struct TestFlightAppPageTests {

    /// Mutation: change the host or the path — the measured form is the only one
    /// known to land on the app's page rather than TestFlight's list.
    @Test func theAppPageIsTheMeasuredForm() throws {
        let url = try #require(TestFlightInventory.Frontier(adamID: 6803740949, maxBuildID: 1).appPageURL)
        #expect(url.absoluteString == "itms-beta://beta.itunes.apple.com/v1/app/6803740949")
    }

    /// Never a join link, whatever the id: joining a beta is an account-level side
    /// effect, and this is reached from a button that says "open". Mutation: build
    /// `/join/<id>` — red.
    @Test(arguments: [Int64(1), 6761822408, 6803740949, Int64.max])
    func theAppPageNeverJoins(adamID: Int64) throws {
        let url = try #require(TestFlightInventory.Frontier(adamID: adamID, maxBuildID: 1).appPageURL)
        #expect(url.scheme == "itms-beta")
        #expect(!url.absoluteString.lowercased().contains("join"))
    }

    /// No id, no page. Zero is what `sqlite3_column_int64` reads for a NULL.
    /// Mutation: drop the guard — then the button opens `…/app/0`.
    @Test(arguments: [Int64(0), -1])
    func noIDMeansNoPage(adamID: Int64) {
        #expect(TestFlightInventory.Frontier(adamID: adamID, maxBuildID: 1).appPageURL == nil)
    }
}
