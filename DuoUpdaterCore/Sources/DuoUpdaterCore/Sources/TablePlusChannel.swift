import Foundation

/// TablePlus (`com.tinyapp.tableplus`) — a header-keyed Sparkle app, a third
/// shape neither feed-swap (Fork/Surge) nor channel-tag (DuoPaste/OrbStack)
/// covers. Stable and beta share ONE appcast (the Info.plist `SUFeedURL`,
/// `https://tableplus.com/osx/version.xml`); the server decides which builds to
/// return from a request header. With no header it serves the stable build (e.g.
/// 710); with `X-Tiny-Beta-Update: true` it serves the latest beta (e.g. 711).
/// The beta items carry no `<sparkle:channel>` tag — they're just the default
/// channel of a different response — so flipping the header is the whole job.
///
/// The header value is load-bearing: the app sends the literal string `true`,
/// and the server treats anything else (`1`, `yes`) as stable. The user's opt-in
/// lives in `IsReceiveBetaBuild` nested inside the `ViewSetting` dict of
/// TablePlus's own UserDefaults (true → beta). Unreadable → stable, the
/// conservative default that never pushes a surprise prerelease.
enum TablePlusChannel {
    static let bundleID = "com.tinyapp.tableplus"

    /// The header (and exact value) the app sends to unlock the beta feed.
    static let betaHeaderField = "X-Tiny-Beta-Update"
    static let betaHeaderValue = "true"

    /// Map TablePlus's `IsReceiveBetaBuild` flag to a resolution. Pure and tested.
    static func resolve(receiveBeta: Bool) -> ResolvedChannel {
        receiveBeta
            ? ResolvedChannel(
                channel: .beta,
                feedHTTPHeaders: [betaHeaderField: betaHeaderValue])
            : ResolvedChannel(channel: .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(receiveBeta: readReceiveBeta())
    }

    /// Read `ViewSetting.IsReceiveBetaBuild` from TablePlus's UserDefaults.
    /// Returns false (stable) when the dict or key is missing.
    static func readReceiveBeta() -> Bool {
        // Force a fresh read from cfprefsd: this long-running menu-bar process can
        // otherwise serve a value cached from before TablePlus wrote the toggle.
        CFPreferencesAppSynchronize(bundleID as CFString)
        guard let viewSetting = CFPreferencesCopyAppValue(
            "ViewSetting" as CFString, bundleID as CFString
        ) as? [String: Any] else { return false }
        return (viewSetting["IsReceiveBetaBuild"] as? NSNumber)?.boolValue ?? false
    }
}
