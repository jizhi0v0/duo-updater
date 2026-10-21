import Foundation

/// What the menu-bar popover's app list area shows: the rows, or which
/// placeholder stands in for them.
///
/// The case this exists for is a cold launch. The scan publishes every app as an
/// unanswered `.unknown` row long before the check answers, and no such row needs
/// action, so the filtered list was empty and fell through to "Everything is up to
/// date" — under a header saying "Checking 255 apps…", for as long as the check
/// ran (about 10 s, measured 2026-10-21). Then the round ended in three writes a
/// few hundred milliseconds apart — the published verdicts, the restart sweep, the
/// staged self-updates — and each landed as its own render: rows popped in, two
/// more were inserted above them, and the panel grew in steps.
///
/// Until this launch has finished a round there is no verdict to show, so the
/// list says it is checking and shows no rows at all — not the empty claim, and
/// not the rows as they arrive. The whole list appears once, after the round's
/// last write. Later rounds keep the rows they carried from the round before, so
/// they keep showing them.
public enum PopoverListContent: Sendable, Equatable {
    case rows
    /// No rows at all yet, and a round is about to fill them.
    case scanning
    /// No rows, and nothing in flight to bring any.
    case noApps
    /// Rows exist but none has an answer from this launch yet.
    case checking
    case noMatches
    /// Nothing needs action, but some rows could not be checked.
    case noUpdatesFound
    case upToDate

    /// - Parameters:
    ///   - hasRows: the model holds any rows at all (`results`).
    ///   - visibleIsEmpty: the list, as filtered for display, is empty.
    ///   - answeredThisLaunch: a round has finished since launch.
    public static func decide(
        hasRows: Bool,
        visibleIsEmpty: Bool,
        isSearching: Bool,
        isRoundInFlight: Bool,
        answeredThisLaunch: Bool,
        failedCheckCount: Int
    ) -> PopoverListContent {
        guard hasRows else { return isRoundInFlight ? .scanning : .noApps }
        // A search lists every row whatever its status, so the round's writes
        // change what the matches say, not which rows there are.
        if isSearching { return visibleIsEmpty ? .noMatches : .rows }
        if isRoundInFlight, !answeredThisLaunch { return .checking }
        guard visibleIsEmpty else { return .rows }
        return failedCheckCount > 0 ? .noUpdatesFound : .upToDate
    }
}
