import Foundation
import DuoUpdaterCore

/// `AppListModel.installing`, and the ownership its ends feed
/// (`InstallOwnership`).
///
/// An install leaves the table once it is done with its row — after it has
/// written that row (`replaceRow`) — and that is when its end is recorded: in
/// the table's own setter, so no write that empties a row can skip it.
struct InstallTable {
    var stages: [String: InstallStage] = [:] {
        didSet {
            let ended = oldValue.keys.filter { stages[$0] == nil }
            if !ended.isEmpty { ownership.record(ended: ended) }
        }
    }
    private(set) var ownership = InstallOwnership()

    /// Run `read`, a scan of the disk that suspends, and say which rows an
    /// install owned at some point while it ran. The mark is taken before the
    /// read and the answer after it: a mark taken late misses an install that
    /// started and finished during the read, whose bundle the read saw before
    /// the swap.
    @MainActor
    static func scan<Scanned>(
        _ table: () -> InstallTable, _ read: () async -> Scanned
    ) async -> (scanned: Scanned, owned: Set<String>) {
        let before = table()
        let mark = before.ownership.mark(installing: before.stages.keys)
        let scanned = await read()
        let after = table()
        return (scanned, after.ownership.owned(since: mark, installing: after.stages.keys))
    }
}
