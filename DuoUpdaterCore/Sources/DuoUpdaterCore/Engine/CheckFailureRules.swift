import Foundation

/// How many consecutive check failures make a row "chronic" — worth suppressing
/// from `AppListModel`'s *aggregate* opinions about the whole list, never from a
/// row's own account of itself.
///
/// `AppListModel.failedCheckResults` uses this to drop a row from the failed-check
/// banner, the header's "N of M apps not checked" line, and the bulk-retry target
/// list: a vendor that retired its feed fails identically forever (Alfred's
/// appcast 404'd for weeks), and left counted there it pins a banner permanently
/// with a Retry that just re-runs the same 404.
///
/// `RowActionState`/`RowAction.state(for:)` deliberately does NOT read this. A
/// chronic streak does not make "this check failed" stop being true of the row,
/// and the row's own Failed badge — with its own per-row Retry that re-checks
/// only this app, unlike the banner's Retry which re-runs every failed check —
/// stays exactly as informative whether the streak is one round old or thirty.
/// Suppressing it would make a chronically failing app in the workbench (which
/// shows every row unconditionally, with no "Show all" gate) render as nothing,
/// which reads as "up to date" in a window that otherwise reserves blank for
/// exactly that — see issue #264.
public enum CheckFailureRules {
    /// Three rounds of a check interval (six hours by default) is long past the
    /// point where "retry" is the useful advice — for the banner. See the type
    /// doc for why a row's own state does not use this at all.
    public static let chronicThreshold = 3

    /// Whether a row this many consecutive rounds deep should stop driving the
    /// aggregate surfaces built from `AppListModel.failedCheckResults`.
    public static func isChronic(consecutiveFailures: Int) -> Bool {
        consecutiveFailures >= chronicThreshold
    }

    /// What produced a set of check results, for the one question the streak
    /// asks of it: does this count as a round?
    public enum CheckPass: Sendable, Equatable {
        /// A completed full refresh (`AppListModel.performRefresh`), of any intent.
        case round
        /// A re-check of rows that failed — the banner's Retry, or the automatic
        /// retry a scheduled round can earn (`automaticRetryTargets`).
        case retry
    }

    /// The streaks after `pass` produced `checked`.
    ///
    /// A round replaces the streaks outright: a row that failed gains one, and a
    /// row that did not fail — or is gone — drops out. A retry changes nothing.
    /// If a retry counted, a user clicking Retry a few times during an outage
    /// would mark the whole outage chronic and hide the very banner they were
    /// responding to — and the automatic retry would make every transient
    /// failure two rounds deep, so a single bad round plus one bad retry would
    /// reach the threshold a round early.
    public static func streaks(
        _ previous: [String: Int], after pass: CheckPass, checked: [UpdateResult]
    ) -> [String: Int] {
        guard pass == .round else { return previous }
        var next: [String: Int] = [:]
        for result in checked {
            if case .error = result.status {
                next[result.id] = (previous[result.id] ?? 0) + 1
            }
        }
        return next
    }

    // MARK: - Automatic retry

    /// How long after a scheduled round ends its one automatic retry fires.
    ///
    /// Measured 2026-09-27 on one Mac checking every 5 minutes through a local
    /// proxy (issue #899). In 24 hours of the request ledger, ten rounds had five
    /// or more failed version-check requests (all but six of them timeouts). In
    /// nine the failures stopped 8–63 s before the round ended and every request
    /// after the last one succeeded; the tenth ended on a failure. The app's log,
    /// which reached back about five of those hours, shows 101 rows ending
    /// `.error` there, and 97 of them not failing again the next round. Nothing
    /// was measured between
    /// the end of a round and the next one, five minutes later, so this is not
    /// the shortest delay that works, only one past everything that was seen to
    /// work. It is also under half the shortest check interval (5 minutes), so
    /// the retry lands before the next round at every frequency.
    public static let automaticRetryDelay: Duration = .seconds(120)

    /// The rows a completed round's single automatic retry should re-check. Empty
    /// means no retry.
    ///
    /// - Only after a `.scheduled` round: nobody asked for it, so nobody is there
    ///   to press the banner's Retry, and at the default six-hour interval the
    ///   banner would otherwise stay up until the next one.
    /// - Only `.error` rows whose failure `UpdateResult.failureIsTransient` says a
    ///   moment later can fix. A 404, a parse failure or a login wall fails the
    ///   same way a minute later, and a retry of it is a request for nothing.
    /// - Never a chronic row, judged on `streaks` AFTER this round was counted —
    ///   the same rows the banner stopped offering to retry (see the type doc).
    ///
    /// Whether an app is ignored is not asked here: the retry itself applies the
    /// same `deservesCheck` filter the banner's Retry does.
    public static func automaticRetryTargets(
        afterRound checked: [UpdateResult], intent: RefreshIntent, streaks: [String: Int]
    ) -> Set<String> {
        guard intent == .scheduled else { return [] }
        return Set(checked.lazy.filter { result in
            guard case .error = result.status, result.failureIsTransient else { return false }
            return !isChronic(consecutiveFailures: streaks[result.id] ?? 0)
        }.map(\.id))
    }

    /// Whether a source's thrown error is one a retry a moment later routinely
    /// clears: the transport gave up (timeout, dropped or refused connection, no
    /// network) without the server saying anything about the request.
    ///
    /// Deliberately narrow. Everything else counts as not transient, including
    /// errors a source wrapped in its own type: a missed retry costs the row
    /// nothing it does not already have, while a wrong "transient" spends a
    /// request on an answer that will not change. Left out on purpose:
    /// `cannotFindHost` (also what a retired feed's domain answers forever), TLS
    /// failures (a certificate problem does not fix itself in two minutes), and
    /// `cancelled` (we cancelled it).
    public static func isTransientNetworkError(_ error: any Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }
}
