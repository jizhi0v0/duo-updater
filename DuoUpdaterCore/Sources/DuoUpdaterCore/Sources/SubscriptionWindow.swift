import Foundation

/// Which releases a subscription-gated app's licence covers, for the apps that
/// refuse to run a build released after their update window: Surge
/// (`SurgeSubscription`) and TablePlus (`TablePlusSubscription`). Each reads its
/// own licence cache; the rule they share is "published before this moment".
public enum SubscriptionWindow: Sendable, Equatable {
    /// Releases published strictly before `date` are covered. `dayOnly` when the
    /// vendor states a calendar day rather than a moment, so it is shown as one.
    case before(Date, dayOnly: Bool)
    /// The licence cache could not be read; no newer release is covered.
    case unreadable

    /// Whether a release whose feed `<pubDate>` reads `pubDate` is covered. A
    /// date we cannot read is not: the safe direction is to withhold. A pubDate
    /// that names only a day counts as the end of that day, for the same reason.
    func covers(pubDate: String?) -> Bool {
        guard case .before(let cutoff, _) = self,
              let parsed = ReleaseDate.parseWithPrecision(pubDate)
        else { return false }
        let latest = parsed.precision == .day ? parsed.date.addingTimeInterval(86_400) : parsed.date
        return latest < cutoff
    }

    /// The window for `bundleID` on this Mac now, or nil for every app that is
    /// not gated. Read on every check: a renewal changes it and nothing caches it.
    public static func current(forBundleID bundleID: String?) -> SubscriptionWindow? {
        switch bundleID?.lowercased() {
        case SurgeChannel.bundleID.lowercased(): return SurgeSubscription.currentWindow()
        case TablePlusChannel.bundleID.lowercased(): return TablePlusSubscription.currentWindow()
        default: return nil
        }
    }
}

/// A newer release a source left out because the user's subscription does not
/// cover it (`SubscriptionWindow`). Carried on the answer that WAS offered, so a
/// row that reads "up to date" can still say what it is not offering, and why.
public struct SubscriptionHold: Sendable, Hashable {
    /// The newest release left out, as the row displays it.
    public let version: String
    /// The first moment the subscription no longer covers, or nil when the
    /// licence could not be read at all.
    public let coveredBefore: Date?
    /// `coveredBefore` is a calendar day (UTC midnight), not a moment.
    public let dayOnly: Bool

    public init(version: String, coveredBefore: Date?, dayOnly: Bool = false) {
        self.version = version
        self.coveredBefore = coveredBefore
        self.dayOnly = dayOnly
    }

    /// One line for logs and `duo` output; the UI words this itself.
    public var logDescription: String {
        if let coveredBefore {
            let day = coveredBefore.formatted(.iso8601.year().month().day())
            return "\(version) is not covered by the subscription (updates released before \(day)); renew to update"
        }
        return "\(version) withheld: the subscription could not be read; check for updates in the app"
    }
}
