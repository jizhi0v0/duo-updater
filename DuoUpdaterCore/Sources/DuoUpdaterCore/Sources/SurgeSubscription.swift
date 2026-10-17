import Foundation

/// Which Surge releases the user's subscription covers — Surge's own rule, so we
/// offer exactly what Surge's updater would. A build released after the
/// subscription's update window does not run on that licence (Surge's button
/// turns into "Renew Subscription…"), so offering it is offering an app that
/// will not open.
///
/// Read from Surge 6.10.0 (12500), 2026-10-17:
///  - the licence cache is the extended attribute `com.nssurge.surge-mac.nsa.3`
///    on `~/Library/Application Support/com.nssurge.surge-mac`: JSON whose
///    `policy` is base64 of more JSON, which carries `fusDate` in epoch seconds;
///  - `bestValidUpdateInAppcast:forUpdater:` keeps a candidate only when its
///    `dateString.integerValue < fusDate` (Surge's feeds date items with a bare
///    epoch `<pubDate>`).
/// The same policy has an `expiresOnDate`, a different instant on this Mac, and
/// it is NOT what decides updates.
///
/// This is an internal cache, not an interface. Anything we cannot read — no
/// attribute, a changed shape, a `<pubDate>` that is not a number — withholds the
/// release rather than offering it: the user can still check in Surge.
public enum SurgeSubscription {
    public enum Window: Sendable, Equatable {
        /// Releases dated strictly before this epoch second are covered (`fusDate`).
        case before(Int)
        /// The licence cache could not be read; no newer release is covered.
        case unreadable
    }

    static let attributeName = "com.nssurge.surge-mac.nsa.3"

    /// The directory the attribute sits on.
    static var licenseDirectory: URL { SurgeChannel.defaultsFileURL.deletingLastPathComponent() }

    /// The window on this Mac now. Read on every check: a renewal rewrites the
    /// attribute and nothing watches it.
    public static func currentWindow() -> Window {
        window(fromAttribute: readAttribute(at: licenseDirectory))
    }

    /// Parse the attribute's value. Pure and tested. Never logs: the policy also
    /// carries the device id and licence details.
    static func window(fromAttribute data: Data?) -> Window {
        guard let data,
              let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encoded = outer["policy"] as? String,
              let decoded = Data(base64Encoded: encoded),
              let policy = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let fus = (policy["fusDate"] as? NSNumber)?.intValue, fus > 0
        else { return .unreadable }
        return .before(fus)
    }

    /// Whether a release dated `pubDate` (the feed's raw `<pubDate>`) is covered.
    /// Only an all-digit date compares: Surge's `integerValue` would read any
    /// other spelling as 0 and admit it, and the safe direction here is the other.
    static func covers(pubDate: String?, under window: Window) -> Bool {
        guard case .before(let fus) = window,
              let raw = pubDate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw.allSatisfy(\.isASCIIDigit), let date = Int(raw)
        else { return false }
        return date < fus
    }

    static func readAttribute(at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, attributeName, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes {
                getxattr(path, attributeName, $0.baseAddress, size, 0, 0)
            }
            guard read == size else { return nil }
            return data
        }
    }
}

/// A newer release a source left out because the user's subscription does not
/// cover it (`SurgeSubscription`). Carried on the answer that WAS offered, so a
/// row that reads "up to date" can still say what it is not offering, and why.
public struct SubscriptionHold: Sendable, Hashable {
    /// The newest release left out, as the row displays it.
    public let version: String
    /// The first moment the subscription no longer covers, or nil when the
    /// licence could not be read at all.
    public let coveredBefore: Date?

    public init(version: String, coveredBefore: Date?) {
        self.version = version
        self.coveredBefore = coveredBefore
    }

    /// One line for logs and `duo` output; the UI words this itself.
    public var logDescription: String {
        if let coveredBefore {
            let day = coveredBefore.formatted(.iso8601.year().month().day())
            return "\(version) is not covered by the Surge subscription (updates released before \(day)); renew in Surge"
        }
        return "\(version) withheld: Surge's subscription could not be read; check for updates in Surge"
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
