import Testing
@testable import DuoUpdaterCore

@Suite("InstallOwnership")
struct InstallOwnershipTests {
    /// The PR #1503 review case: a row clicked on its own is installing when
    /// Update All's closing rescan starts, and has finished — left the install
    /// table — by the time that rescan applies. It is still owned.
    @Test("an install that ends during the scan is owned")
    func endedDuringScanIsOwned() {
        var ownership = InstallOwnership()
        let mark = ownership.mark(installing: ["A"])
        ownership.record(ended: ["A"])
        #expect(ownership.owned(since: mark, installing: []) == ["A"])
    }

    /// The same, for an install clicked after the scan started: the install
    /// table never had it at either end.
    @Test("an install that starts and ends during the scan is owned")
    func startedAndEndedDuringScanIsOwned() {
        var ownership = InstallOwnership()
        let mark = ownership.mark(installing: [])
        ownership.record(ended: ["B"])
        #expect(ownership.owned(since: mark, installing: []) == ["B"])
    }

    @Test("installing at either end is owned")
    func installingAtEitherEnd() {
        let ownership = InstallOwnership()
        let mark = ownership.mark(installing: ["A"])
        #expect(ownership.owned(since: mark, installing: ["C"]) == ["A", "C"])
    }

    /// Update All's own targets finished before its closing rescan started:
    /// the scan is what refreshes them, so they must not be held.
    @Test("an install that ended before the scan is not owned")
    func endedBeforeScanIsNotOwned() {
        var ownership = InstallOwnership()
        ownership.record(ended: ["T1", "T2"])
        let mark = ownership.mark(installing: [])
        #expect(ownership.owned(since: mark, installing: []).isEmpty)
    }

    @Test("a second end after the mark counts, an earlier one does not")
    func onlyEndsAfterTheMark() {
        var ownership = InstallOwnership()
        ownership.record(ended: ["A"])
        let mark = ownership.mark(installing: [])
        ownership.record(ended: ["B"])
        #expect(ownership.owned(since: mark, installing: []) == ["B"])
    }
}

@Suite("InstallOwnership.applying")
struct InstallOwnershipApplyingTests {
    struct Row: Identifiable, Equatable {
        let id: String
        let version: String
    }

    /// The owned row keeps the version its install wrote; the scan's
    /// pre-swap read of it is dropped. Rows nobody owned take the scan's.
    @Test("an owned row keeps its current copy")
    func ownedRowKeepsCurrent() {
        let current = [Row(id: "A", version: "2.0"), Row(id: "B", version: "1.0")]
        let scanned = [Row(id: "A", version: "1.0"), Row(id: "B", version: "1.1")]
        let applied = InstallOwnership.applying(scanned, keeping: ["A"], from: current)
        #expect(Set(applied.map(\.id)) == ["A", "B"])
        #expect(applied.first { $0.id == "A" }?.version == "2.0")
        #expect(applied.first { $0.id == "B" }?.version == "1.1")
    }

    /// Read mid-swap, the bundle can be missing from the scan altogether.
    @Test("an owned row the scan missed is kept")
    func ownedRowMissingFromScanIsKept() {
        let current = [Row(id: "A", version: "2.0"), Row(id: "B", version: "1.0")]
        let scanned = [Row(id: "B", version: "1.0")]
        let applied = InstallOwnership.applying(scanned, keeping: ["A"], from: current)
        #expect(applied.contains(Row(id: "A", version: "2.0")))
        #expect(applied.count == 2)
    }

    @Test("an owned id with no current row adds nothing")
    func ownedWithoutCurrentRowAddsNothing() {
        let scanned = [Row(id: "B", version: "1.0")]
        let applied = InstallOwnership.applying(scanned, keeping: ["A"], from: scanned)
        #expect(applied == scanned)
    }

    @Test("nothing owned is the scan as it is")
    func nothingOwned() {
        let scanned = [Row(id: "B", version: "1.1"), Row(id: "A", version: "1.0")]
        let current = [Row(id: "A", version: "2.0")]
        #expect(InstallOwnership.applying(scanned, keeping: [], from: current) == scanned)
    }
}
