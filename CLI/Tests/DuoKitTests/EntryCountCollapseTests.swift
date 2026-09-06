import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// The changelog sweep's second history check (#324, #393).
///
/// An entry pattern is a start plus a lookahead for the next start. When a
/// vendor's restyle breaks only the LOOKAHEAD, the first entry's body runs to
/// the end of the document and every later start is swallowed inside it: the
/// page collapses to one entry, the version still parses correctly off the
/// first heading, and every other check in `Baseline` stays green.
///
/// ⚠️ Worth knowing what this does NOT catch, because the issue that asked for
/// it named the wrong example. The bug fixed in `bf5db16` was an ITEM pattern
/// running past the end of the last entry — that commit measured "the same 17
/// entries parse with the same item counts", so the entry count never moved.
/// It was also wrong from the recipe's first sweep, which no history check can
/// see: there was never a healthier count to fall from. This check covers the
/// entry-level regression, and only that.
///
/// Every case names the mutation it catches.
@Suite struct EntryCountCollapseTests {

    private func changelog(
        _ id: String = "changelog:com.example.app:-",
        version: String? = "4.8.0", entries: Int?
    ) -> Finding {
        Finding(
            recipeID: id, registry: .changelog, bundleID: "com.example.app", channel: "-",
            status: .ok, version: version, endpointHost: "example.invalid",
            entryCount: entries)
    }

    /// Mutation: drop the whole `entryCount` block from `reconcile`. Nothing
    /// else in the file can see this — the version is still correct, the fetch
    /// still succeeded, the status is still `.ok`.
    @Test func aPageCollapsingToOneEntryIsFlagged() throws {
        var baseline = Baseline()
        #expect(baseline.reconcile(changelog(entries: 20)).isEmpty)

        let complaints = baseline.reconcile(changelog(entries: 1))
        #expect(complaints.count == 1)
        let complaint = try #require(complaints.first)
        #expect(complaint.contains("COLLAPSED"))
        // The transition, not just the endpoint: "20 → 1" is what tells a
        // reader this is the merge and not a page that has always had one.
        #expect(complaint.contains("20 → 1"))
    }

    /// Six of the 80 changelog recipes that answered on 2026-09-07 sit at
    /// exactly one entry as their normal state — VS Code, Ghostty, Blender,
    /// VLC, QQ Music and Doubao IME each publish one release per page. One
    /// entry is not suspicious; BECOMING one is.
    ///
    /// Mutation: drop the `previous > 1` condition. Every one of those six
    /// recipes then warns on every sweep, forever.
    @Test func aRecipeThatAlwaysReadsOneEntryIsNeverFlagged() {
        var baseline = Baseline()
        #expect(baseline.reconcile(changelog(entries: 1)).isEmpty)
        #expect(baseline.reconcile(changelog(entries: 1)).isEmpty)
        #expect(baseline.reconcile(changelog(entries: 1)).isEmpty)
    }

    /// A drop that is not a collapse is deliberately silent. 22 of those 80
    /// recipes sit exactly at their `maxEntries` cap of 20 and 12 more at 40,
    /// where the count is insensitive to a vendor ADDING releases and moves
    /// only when they prune — which they are entitled to do. There is nothing
    /// to calibrate a fractional rule against, so this covers the shape it can
    /// name rather than guessing at a threshold.
    ///
    /// Mutation: widen `count == 1` to `count < previous`. Ordinary vendor
    /// housekeeping then files issues.
    @Test func anOrdinaryDropIsNotFlagged() {
        var baseline = Baseline()
        _ = baseline.reconcile(changelog(entries: 20))
        #expect(baseline.reconcile(changelog(entries: 12)).isEmpty)
        #expect(baseline.reconcile(changelog(entries: 2)).isEmpty)
    }

    /// The reason `reconcile` returns every complaint rather than the first.
    /// These two fire together for ONE cause: when the entries merge, the
    /// version that survives is whichever heading the merged entry kept, and
    /// for a `newestLast` recipe that is the oldest one on the page.
    ///
    /// Mutation: return `complaints.first` — the report then carries a version
    /// regression with no explanation, sending whoever picks it up to look at a
    /// version pattern that never changed.
    @Test func aCollapseAndAVersionRegressionAreBothReported() {
        var baseline = Baseline()
        _ = baseline.reconcile(changelog(version: "4.8.0", entries: 20))

        let complaints = baseline.reconcile(changelog(version: "1.0.0", entries: 1))
        #expect(complaints.count == 2)
        #expect(complaints.contains { $0.contains("BACKWARDS") })
        #expect(complaints.contains { $0.contains("COLLAPSED") })
    }

    /// Every other registry reports nil here, and a nil must not be read as a
    /// count. The `feed` and `appstore` sweeps share `reconcile` with this one.
    ///
    /// Mutation: `finding.entryCount ?? 0`. The first non-changelog finding for
    /// a recipe id then records zero, and the real collapse that follows it is
    /// judged against that zero — `previous > 1` fails and the check goes
    /// permanently silent.
    @Test func aRegistryThatCountsNothingDoesNotOverwriteTheCount() {
        var baseline = Baseline()
        let id = "changelog:com.example.app:-"
        _ = baseline.reconcile(changelog(id, entries: 20))
        _ = baseline.reconcile(Finding(
            recipeID: id, registry: .vendor, bundleID: "com.example.app", channel: "-",
            // Same version as the changelog finding on purpose: this case is
            // about the COUNT, and a version that moved would put a second,
            // unrelated complaint in the array being counted below.
            status: .ok, version: "4.8.0", endpointHost: "example.invalid"))
        #expect(baseline.entries[id]?.lastGoodEntryCount == 20)
        #expect(baseline.reconcile(changelog(id, entries: 1)).count == 1)
    }

    /// The same pair, this time through the fold `Verify.run` actually uses.
    ///
    /// The case above pins what `reconcile` RETURNS; this one pins that all of
    /// it reaches the finding. Without it the array return is decorative — the
    /// fold is one `.first` or `.prefix(1)` away from throwing half of it away,
    /// and no test would have noticed.
    ///
    /// Mutation: `.prefix(1)` in `foldingBaselineComplaints`.
    @Test func everyComplaintReachesTheFinding() throws {
        var baseline = Baseline()
        _ = Verify.foldingBaselineComplaints(
            [changelog(version: "4.8.0", entries: 20)], into: &baseline)

        let folded = try #require(Verify.foldingBaselineComplaints(
            [changelog(version: "1.0.0", entries: 1)], into: &baseline).first)
        #expect(folded.status == .warn)
        #expect(folded.warnings.count == 2)
        #expect(folded.warnings.contains { $0.contains("BACKWARDS") })
        #expect(folded.warnings.contains { $0.contains("COLLAPSED") })
    }

    /// And it has to survive the DISK, which is where this check actually
    /// lives: the two sweeps it compares are two separate processes.
    ///
    /// `Baseline.Entry` encodes with the synthesized encoder and decodes with a
    /// hand-written one, so a field declared but not listed in `init(from:)` is
    /// written every sweep and read back as nil every sweep. That is what
    /// happened here — the file on disk said `"lastGoodEntryCount": 1` while
    /// the running check had never once seen a previous value, and every unit
    /// test above passed throughout because none of them touch a file. Only a
    /// two-sweep run against a real page showed it.
    ///
    /// Mutation: remove the `lastGoodEntryCount` line from that decoder.
    @Test func theCountSurvivesTheFileBetweenSweeps() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-entry-count-\(UUID().uuidString)/baseline.json")
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }

        var first = Baseline()
        _ = first.reconcile(changelog(entries: 20))
        try first.save(to: path)

        // A second process, reading what the first wrote.
        var second = Baseline.load(from: path)
        #expect(second.entries["changelog:com.example.app:-"]?.lastGoodEntryCount == 20)
        #expect(second.reconcile(changelog(entries: 1)).count == 1)
    }

    /// The count has to survive the rebuild `adding(warning:)` performs, or it
    /// is dropped from `report.json` for exactly the findings that carry a
    /// complaint — the ones most worth reading, and the ones whose issue body
    /// prints it.
    ///
    /// Mutation: leave `entryCount` off that initializer call. It compiles
    /// (every argument there has a default) and the field silently becomes nil.
    @Test func attachingAWarningKeepsTheCount() {
        let flagged = changelog(entries: 17).adding(warning: "something to say")
        #expect(flagged.entryCount == 17)
        #expect(flagged.status == .warn)
    }
}
