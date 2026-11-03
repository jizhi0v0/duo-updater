import Foundation

/// What Setapp's client says about this Mac's subscription, read from the
/// preferences it keeps for itself.
///
/// `com.setapp.DesktopClient`'s `known_customers` array carries, per signed-in
/// customer:
///
///     subscriptionState            trial | paid
///     subscriptionStartDate        2019-01-30 09:40:58 +0000
///     subscriptionExpirationDate   2027-01-30 23:59:59 +0000
///     gracePeriodExpirationDate    2027-02-13 23:59:59 +0000
///     subscriptionProlongationCanceled 0
///
/// Measured on two accounts 2026-11-03: a 7-day trial (expiring 2026-11-09
/// 23:59:59 UTC, grace to 2026-11-14) and a paid subscription (expiring
/// 2027-01-30 23:59:59 UTC, grace to 2027-02-13). The client's own "7 days left
/// in trial" is this field, so it is the account's own answer, not ours.
///
/// Why it matters here: once the subscription ends, Setapp stops delivering
/// updates and the apps themselves stop opening (Setapp's cancellation terms),
/// so a "1.40.1 is available" row with an Update button would be a promise
/// nothing can keep. The 14-day grace period is Setapp's own ([Grace
/// period](https://support.setapp.com/hc/en-us/articles/115004305069-Grace-period)),
/// and we treat it the same way: still covered.
public enum SetappSubscription {

    public struct State: Sendable, Equatable {
        /// The raw `subscriptionState` the client wrote (`trial`, `paid`).
        public let rawState: String
        /// The first moment the subscription itself no longer covers.
        public let expiresAt: Date?
        /// The end of Setapp's 14-day grace period, when the client wrote one.
        public let graceEndsAt: Date?
        public let startedAt: Date?

        public init(rawState: String, expiresAt: Date?, graceEndsAt: Date?, startedAt: Date?) {
            self.rawState = rawState
            self.expiresAt = expiresAt
            self.graceEndsAt = graceEndsAt
            self.startedAt = startedAt
        }

        /// Whether Setapp would still act on this account now.
        ///
        /// Grace first: Setapp keeps serving a subscription whose payment failed
        /// for 14 days, and while it does, updates still land. With neither date
        /// readable the answer is "not active" — the conservative direction,
        /// because the alternative is offering an update to an account we cannot
        /// show is valid.
        public func isActive(now: Date) -> Bool {
            guard let until = graceEndsAt ?? expiresAt else { return false }
            return now < until
        }
    }

    /// The preferences domain Setapp's client writes.
    public static let defaultsDomain = "com.setapp.DesktopClient"

    /// This Mac's subscription state, or nil when there is no readable customer
    /// (Setapp not installed, never signed in, or the key changed shape).
    public static func current(defaults: UserDefaults? = UserDefaults(suiteName: defaultsDomain)) -> State? {
        guard let customers = defaults?.array(forKey: "known_customers") as? [[String: Any]] else {
            return nil
        }
        return state(from: customers)
    }

    /// Setapp's "Beta: Get beta versions of Setapp and installed apps" switch.
    /// Client-wide, not per app; the public catalogue we read carries no betas at
    /// all, so when this is on our stable answer cannot claim to be current.
    public static func isBetaUpdatesEnabled(
        defaults: UserDefaults? = UserDefaults(suiteName: defaultsDomain)
    ) -> Bool {
        (defaults?.object(forKey: "AllowBetaInternalUpdates") as? NSNumber)?.boolValue ?? false
    }

    /// Pick the customer that lasts longest — a machine can carry more than one
    /// signed-in customer, and the row should describe the access the apps
    /// actually have.
    static func state(from customers: [[String: Any]]) -> State? {
        customers
            .compactMap { customer -> State? in
                let expires = dateValue(customer["subscriptionExpirationDate"])
                let grace = dateValue(customer["gracePeriodExpirationDate"])
                guard expires != nil || grace != nil else { return nil }
                return State(
                    rawState: customer["subscriptionState"] as? String ?? "unknown",
                    expiresAt: expires,
                    graceEndsAt: grace,
                    startedAt: dateValue(customer["subscriptionStartDate"]))
            }
            .max { lhs, rhs in
                (lhs.graceEndsAt ?? lhs.expiresAt ?? .distantPast)
                    < (rhs.graceEndsAt ?? rhs.expiresAt ?? .distantPast)
            }
    }

    /// One date from a `known_customers` entry.
    ///
    /// The client has written this both ways across versions: as an `NSDate`
    /// (what 3.58.0 does — `plutil -p` shows `2026-11-09 23:59:59 +0000` with no
    /// quotes) and, in older payloads, as a string in the same shape. `defaults
    /// read` shows the Date form quoted, which is what made an earlier version of
    /// this parser read only strings and treat a live trial as expired.
    static func dateValue(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let string = value as? String { return parseDate(string) }
        return nil
    }

    /// `2026-11-09 23:59:59 +0000` — the string form, with the offset in the text.
    /// Parsed as written rather than converted: the value IS UTC midnight-ish, and
    /// re-reading it in the local zone would move the boundary.
    static func parseDate(_ text: String?) -> Date? {
        guard let text, text.isEmpty == false else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)
    }
}
