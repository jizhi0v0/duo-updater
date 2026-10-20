import Foundation
import Testing
import DuoUpdaterCore

/// The App side of `InstallOwnership` (PR #1503): the install table records
/// each install's end, and a local rescan marks before its read and asks after
/// it. Core tests the bookkeeping; these test that the table and the rescan
/// feed it in that order.
@MainActor
struct InstallTableTests {
    /// What the rescans hold: the table, read live through the closure.
    @MainActor final class Model {
        var table = InstallTable()
    }

    /// The #1503 round-1 case: a row clicked while the rescan reads, whose
    /// install writes its row and leaves the table before the rescan applies.
    /// Fails if the mark is taken after the read, or if the table stops
    /// recording an install's end when the row leaves it.
    @Test func installDuringTheReadIsOwned() async {
        let model = Model()
        let (_, owned) = await InstallTable.scan({ model.table }) {
            await Task.yield()
            model.table.stages["a"] = .queued
            model.table.stages["a"] = .installing
            model.table.stages["a"] = nil
        }
        #expect(owned == ["a"])
    }

    /// The whole sequence as the app runs it: the scan read the bundle before
    /// the swap; the install wrote its row (`replaceRow`) and then left the
    /// table. The rescan's apply keeps the install's row.
    @Test func rescanKeepsTheInstallsRow() async {
        struct Row: Identifiable, Equatable { let id: String; let version: String }
        let model = Model()
        var current = [Row(id: "a", version: "1.0"), Row(id: "b", version: "3.0")]
        let (scanned, owned) = await InstallTable.scan({ model.table }) {
            let read = [Row(id: "a", version: "1.0"), Row(id: "b", version: "3.1")]
            await Task.yield()
            model.table.stages["a"] = .installing
            current[0] = Row(id: "a", version: "2.0")  // the install's `replaceRow`
            model.table.stages["a"] = nil
            return read
        }
        let applied = InstallOwnership.applying(scanned, keeping: owned, from: current)
        #expect(Set(applied.map(\.version)) == ["2.0", "3.1"])
    }

    /// The other side: an install over before the read began owns nothing,
    /// so a rescan still updates its row.
    @Test func installBeforeTheReadIsNotOwned() async {
        let model = Model()
        model.table.stages["a"] = .installing
        model.table.stages["a"] = nil
        let (_, owned) = await InstallTable.scan({ model.table }) { await Task.yield() }
        #expect(owned.isEmpty)
    }

    /// A row installing when the read starts is owned even after it is done.
    @Test func installAtTheMarkIsOwned() async {
        let model = Model()
        model.table.stages["a"] = .downloading(fraction: 0.5)
        let (_, owned) = await InstallTable.scan({ model.table }) {
            await Task.yield()
            model.table.stages["a"] = nil
        }
        #expect(owned == ["a"])
    }
}
