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
/// attribute, a changed shape, a `<pubDate>` that is not a date — withholds the
/// release rather than offering it: the user can still check in Surge.
public enum SurgeSubscription {
    static let attributeName = "com.nssurge.surge-mac.nsa.3"

    /// The directory the attribute sits on.
    static var licenseDirectory: URL { SurgeChannel.defaultsFileURL.deletingLastPathComponent() }

    /// The window on this Mac now. Read on every check: a renewal rewrites the
    /// attribute and nothing watches it.
    public static func currentWindow() -> SubscriptionWindow {
        window(fromAttribute: readAttribute(at: licenseDirectory))
    }

    /// Parse the attribute's value. Pure and tested. Never logs: the policy also
    /// carries the device id and licence details.
    static func window(fromAttribute data: Data?) -> SubscriptionWindow {
        guard let data,
              let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encoded = outer["policy"] as? String,
              let decoded = Data(base64Encoded: encoded),
              let policy = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let fus = (policy["fusDate"] as? NSNumber)?.intValue, fus > 0
        else { return .unreadable }
        return .before(Date(timeIntervalSince1970: TimeInterval(fus)), dayOnly: false)
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
