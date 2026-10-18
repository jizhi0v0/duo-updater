import Foundation
import Testing
import DuoUpdaterCore
@testable import DuoKit

/// `duo install` stopped by a signal before an item's commit point: the item
/// is cancelled, not failed, and says at which stage — in the `--json` row,
/// the text line and the summary (plans/update-cancellation.md §5.8, §7).
@Suite struct InstallCancelledTests {

    /// The row carries `outcome: "cancelled"` — the field every install row
    /// already classifies itself by — and the stage's bare name.
    /// Mutation: `"stage": stage.name` → `String(describing: stage)` → the
    /// fraction leaks into the value, red.
    @Test func theJSONRowSaysCancelledAndTheStage() throws {
        let payload = Install.cancelledPayload(
            name: "ZZFixture", route: .sparkle, stage: .downloading(fraction: 0.4))
        #expect(payload["outcome"] as? String == "cancelled")
        #expect(payload["stage"] as? String == "downloading")
        #expect(payload["applied"] as? Bool == false)
        #expect(payload["route"] as? String == "sparkle")
        #expect(payload["app"] as? String == "ZZFixture")
        // As the stream writes it.
        var lines: [String] = []
        NDJSON.emit(payload) { lines.append($0) }
        let row = try #require(lines.first)
        #expect(row.contains(#""outcome":"cancelled""#))
        #expect(row.contains(#""stage":"downloading""#))
    }

    /// Mutation: drop the `cancelled` clause from `summaryLine` → red.
    @Test func theSummaryCountsCancelledApartFromFailed() {
        var tally = Install.Tally()
        tally.record(.installed)
        tally.record(.cancelled)
        tally.record(.cancelled)
        #expect(tally.cancelled == 2)
        #expect(tally.failed == 0)
        #expect(Install.summaryLine(tally) == "1 installed, 0 failed, 2 cancelled.")
    }

    /// Unchanged when nothing was cancelled.
    @Test func theSummaryOmitsZeroCancelled() {
        var tally = Install.Tally()
        tally.record(.installed)
        #expect(Install.summaryLine(tally) == "1 installed, 0 failed.")
    }

    @Test func theTextLineNamesTheStage() {
        #expect(Install.cancelledLine(.queued) == "cancelled before it started — not updated")
        #expect(Install.cancelledLine(.downloading(fraction: 0.4)) == "cancelled while downloading — not updated")
        #expect(Install.cancelledLine(.backingUp)
            == "cancelled while backing up — not updated, and no partial backup was kept")
        #expect(Install.cancelledLine(.extracting) == "cancelled at extracting — not updated")
    }
}
