import Testing
import Foundation
@testable import DuoKit

/// `attempts` is what a reader uses to judge how much an endpoint cost, and
/// `gatewayRetries` is the only record that a flap happened at all — an endpoint
/// that 502s and recovers still reports `ok`.
struct GatewayRetryReportingTests {

    private static func finding(attempts: Int, retries: Int?) -> Finding {
        Finding(
            recipeID: "vendor:com.example.app:stable", registry: .vendor,
            bundleID: "com.example.app", channel: "stable", status: .ok,
            endpointHost: "example.com", attempts: attempts, gatewayRetries: retries)
    }

    @Test func aRetryIsRecordedEvenWhenTheFindingIsOtherwiseFine() {
        let f = Self.finding(attempts: 2, retries: 1)
        #expect(f.status == .ok)
        #expect(f.gatewayRetries == 1)
        // The whole point: two requests were spent, and the report says two.
        #expect(f.attempts == 2)
    }

    /// `observing` and `adding` rebuild the whole struct field by field, so a new
    /// field is exactly the kind that gets silently dropped there.
    @Test func annotatingAFindingKeepsItsRequestAccounting() {
        let base = Self.finding(attempts: 3, retries: 1)
        #expect(base.observing("\(Finding.machineNotePrefix)note").gatewayRetries == 1)
        #expect(base.observing("\(Finding.machineNotePrefix)note").attempts == 3)
        #expect(base.adding(warning: "w").gatewayRetries == 1)
        #expect(base.adding(warning: "w").attempts == 3)
    }

    /// …and the same for the changelog entry count, which is the field that was
    /// actually dropped. `adding(warning:)` forwards it and carries a comment
    /// saying why; `observing` did not, so a machine note — the one-click
    /// candidate note the vendor sweep attaches — silently deleted "entries
    /// parsed" from `report.json` for that finding, and it is the number the
    /// collapse check exists to show.
    ///
    /// Mutation: drop `entryCount:` from `observing`'s initializer call. It
    /// compiles, because every argument there has a default.
    @Test func annotatingAFindingKeepsItsEntryCount() {
        let counted = Finding(
            recipeID: "changelog:com.example.app:-", registry: .changelog,
            bundleID: "com.example.app", channel: "-", status: .ok,
            endpointHost: "example.com", entryCount: 17)
        #expect(counted.observing("\(Finding.machineNotePrefix)note").entryCount == 17)
        #expect(counted.adding(warning: "w").entryCount == 17)
    }

    /// `report.json` files written before this field existed are still read by
    /// `Reconcile` and `Triage`. Decoding must not start failing on them, and a
    /// missing key must not be reported as a confident zero.
    @Test func anOlderReportWithoutTheFieldStillDecodes() throws {
        let json = """
        {
          "recipeID": "vendor:com.example.app:stable",
          "registry": "vendor",
          "bundleID": "com.example.app",
          "channel": "stable",
          "status": "ok",
          "warnings": [],
          "endpointHost": "example.com",
          "attempts": 1,
          "elapsedMs": 12
        }
        """
        let decoded = try JSONDecoder().decode(Finding.self, from: Data(json.utf8))
        #expect(decoded.recipeID == "vendor:com.example.app:stable")
        #expect(decoded.gatewayRetries == nil)   // "not recorded", not "zero"
    }

    @Test func aFreshFindingRoundTripsTheField() throws {
        let data = try JSONEncoder().encode(Self.finding(attempts: 2, retries: 1))
        #expect(try JSONDecoder().decode(Finding.self, from: data).gatewayRetries == 1)
    }
}
