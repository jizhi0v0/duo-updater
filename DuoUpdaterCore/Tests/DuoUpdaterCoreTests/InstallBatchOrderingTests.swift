import Testing
import Foundation
@testable import DuoUpdaterCore

/// Shortest-job-first ordering for "Update All": the batch runs in list order
/// (alphabetical by app name), so a 400 MB update can occupy a slot while nine
/// 20 MB ones queue behind it. The batch must run small downloads first —
/// within its phases — with unknown sizes treated neutrally, never starved to
/// either extreme.
struct InstallBatchOrderingTests {

    private func result(named name: String, size: Int64?) -> UpdateResult {
        let app = InstalledApp(
            name: name, bundleID: name,
            shortVersion: "1", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/\(name).app"),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: "2", version: "2",
            downloadURL: URL(string: "https://example.com/\(name).dmg"),
            downloadSize: size,
            sourceName: "Sparkle")
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "2"))
    }

    private func names(_ results: [UpdateResult]) -> [String] {
        results.map(\.app.name)
    }

    /// Known sizes run smallest-first.
    @Test func knownSizesSortSmallestFirst() {
        let input = [
            result(named: "big", size: 400_000_000),
            result(named: "small", size: 20_000_000),
            result(named: "medium", size: 60_000_000),
            result(named: "tiny", size: 2_000_000),
        ]
        #expect(names(InstallBatchOrdering.sortByDownloadSize(input))
            == ["tiny", "small", "medium", "big"])
    }

    /// Unknown sizes are neutral: they sit with the median known size — never
    /// first (where a possibly-enormous download would delay a known-small
    /// one), never last (where a possibly-tiny one starves behind the bigs).
    @Test func unknownSizesSortNeutrally() {
        // Known: 10, 30, 50 → median 30. The unknowns tie at 30 and keep their
        // input order (stable), landing between the 10 and the 50.
        let input = [
            result(named: "ten", size: 10),
            result(named: "unknown1", size: nil),
            result(named: "fifty", size: 50),
            result(named: "thirty", size: 30),
            result(named: "unknown2", size: nil),
        ]
        let sorted = InstallBatchOrdering.sortByDownloadSize(input)
        let ordered = names(sorted)
        #expect(ordered.first == "ten")              // smallest known leads
        #expect(ordered.last == "fifty")             // largest known trails
        #expect(sorted[0].remote?.downloadSize == 10)
        // The unknowns are inside the range, in their original relative order.
        #expect(ordered.firstIndex(of: "unknown1")! < ordered.firstIndex(of: "fifty")!)
        #expect(ordered.firstIndex(of: "unknown2")! < ordered.firstIndex(of: "fifty")!)
        #expect(ordered.firstIndex(of: "unknown1")! > ordered.firstIndex(of: "ten")!)
        #expect(ordered.firstIndex(of: "unknown1")! < ordered.firstIndex(of: "unknown2")!)
    }

    /// With no known sizes at all, nothing can be ordered — the input order
    /// (the app-name sort) must be preserved untouched.
    @Test func allUnknownKeepsOriginalOrder() {
        let input = [
            result(named: "zulu", size: nil),
            result(named: "alpha", size: nil),
            result(named: "mike", size: nil),
        ]
        #expect(names(InstallBatchOrdering.sortByDownloadSize(input)) == ["zulu", "alpha", "mike"])
    }

    /// Equal sizes (and every tie an unknown row makes with the median) keep
    /// the caller's order — the sort is stable, so the alphabetically-first
    /// batch the user sees is unchanged except for the size ordering.
    @Test func tiesKeepOriginalOrder() {
        let input = [
            result(named: "delta", size: 100),
            result(named: "charlie", size: 100),
            result(named: "bravo", size: 100),
            result(named: "alpha", size: 100),
        ]
        #expect(names(InstallBatchOrdering.sortByDownloadSize(input))
            == ["delta", "charlie", "bravo", "alpha"])
    }
}
