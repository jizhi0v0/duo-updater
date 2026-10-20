import Foundation

/// Which rows an install owned while a local rescan read the disk.
///
/// A rescan scans off the main actor and applies afterwards. A row whose
/// install swaps its bundle in that time was read before the swap, or in the
/// middle of it, and the install writes its own row (`replaceRow`) once it has
/// re-checked. Applying the scan's copy of that row over the install's put the
/// old version back with a live Update (PR #1503 review, round 1): the user
/// clicks one row, then Update All, and the batch's closing rescan is still
/// reading when that row's install lands.
///
/// Owned between `mark` and `owned(since:installing:)` is any of: installing
/// when the scan started, installing when it applies, or an install that ended
/// in between. The last is what the install table alone cannot say — by the
/// time the scan applies, a finished install has left it.
public struct InstallOwnership: Sendable, Equatable {
    private var clock: UInt64 = 0
    private var endedAt: [String: UInt64] = [:]

    public init() {}

    /// These rows' installs just ended (they left the install table).
    public mutating func record(ended ids: some Sequence<String>) {
        clock &+= 1
        for id in ids { endedAt[id] = clock }
    }

    /// Where a scan starts from.
    public struct Mark: Sendable, Equatable {
        fileprivate let clock: UInt64
        fileprivate let installing: Set<String>
    }

    public func mark(installing: some Sequence<String>) -> Mark {
        Mark(clock: clock, installing: Set(installing))
    }

    /// Every row an install owned at some point since `mark`.
    public func owned(since mark: Mark, installing now: some Sequence<String>) -> Set<String> {
        var owned = mark.installing.union(now)
        for (id, at) in endedAt where at > mark.clock { owned.insert(id) }
        return owned
    }

    /// The scan's rows, except each owned row, which stays as it is now: the
    /// install that owns it writes it. An owned row the list does not have is
    /// left out, and one the scan missed (read mid-swap) is kept. Order is the
    /// caller's to restore.
    public static func applying<Row: Identifiable>(
        _ scanned: [Row], keeping owned: Set<Row.ID>, from current: [Row]
    ) -> [Row] {
        guard !owned.isEmpty else { return scanned }
        return scanned.filter { !owned.contains($0.id) } + current.filter { owned.contains($0.id) }
    }
}
