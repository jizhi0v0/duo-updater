import Foundation

/// The popover's aggregate rate-limit banner: which of GitHub's two budgets is
/// closed — the token's, the anonymous one, or both — and the line under the
/// title.
///
/// **Two budgets, and the banner has to say which.** A request can be answered
/// on the budget it was not sent with: `URLSession` drops `Authorization` while
/// following a redirect, so a row the app asked for with a token can be counted
/// against the shared anonymous 60 an hour (`GitHubRateLimitGate.answered`).
/// Measured 2026-11-04: the banner said "when GitHub takes requests again" while
/// the token had 4,853 of its 5,000 left and the anonymous budget was the spent
/// one — every word pointed at the token card, the one fix that could not help.
///
/// **Where the wording lives.** Here, not in the view, so it can be tested
/// without a window: the app words the banner with these and `duo` has no banner
/// to word. `String(localized:)` with no bundle reads the main bundle's table —
/// the app's `Localizable.xcstrings` — the same arrangement as `CLIToolWording`.
public enum GitHubRateLimitBanner {

    /// Which budgets are closed now. `none` is no closure at all.
    public enum Spent: Equatable, Sendable {
        case none
        case token
        case anonymous
        case both
    }

    /// `token` and `anonymous` are `GitHubRateLimitGate.Store.pause()`'s two
    /// entries: until when each budget is closed, or nil for one that is open.
    public static func spent(token: Date?, anonymous: Date?) -> Spent {
        switch (token != nil, anonymous != nil) {
        case (false, false): return .none
        case (true, false): return .token
        case (false, true): return .anonymous
        case (true, true): return .both
        }
    }

    /// The later of the closed windows: when both budgets answer again. Nil
    /// when neither is closed.
    public static func until(token: Date?, anonymous: Date?) -> Date? {
        [token, anonymous].compactMap { $0 }.max()
    }

    /// The line under "Hitting GitHub’s rate limit".
    ///
    /// `time` formats the moment as the app's short clock time: a locale's clock
    /// is the app's business, so nothing here reads one, and the tests can say
    /// 11:31 without a fixed time zone.
    ///
    /// * No closure (a burst of 403s that closed nothing): the nudge to add a
    ///   token, as before.
    /// * No token: "or add a token" — the anonymous budget is the one in play.
    /// * A token: name the budget that is spent. "both" is said as both rather
    ///   than as the later of the two, because the two fixes differ.
    public static func detail(
        count: Int, spent: Spent, until: Date?, hasToken: Bool, time: (Date) -> String
    ) -> String {
        guard spent != .none, let until else {
            return String(localized: "\(count) items couldn’t be checked — add a token")
        }
        let when = time(until)
        guard hasToken else {
            return String(localized: "\(count) items wait until \(when) — or add a token")
        }
        switch spent {
        case .token:
            return String(localized: "\(count) items wait until \(when) — your token’s budget is spent")
        case .anonymous:
            return String(localized: "\(count) items wait until \(when) — GitHub’s anonymous budget is spent")
        case .both:
            return String(localized: "\(count) items wait until \(when) — both GitHub budgets are spent")
        case .none:
            // Spelled out rather than defaulted, so a fourth case cannot fall
            // into the "add a token" advice without a compiler error.
            return String(localized: "\(count) items couldn’t be checked — add a token")
        }
    }
}
