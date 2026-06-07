import Foundation

/// IINA (`com.colliderli.iina`) — a feed-swap Sparkle app. Stable and beta share
/// one bundle id and the same Info.plist `SUFeedURL` (`https://www.iina.io/appcast.xml`).
/// The user toggles "Receive beta updates" in Preferences → General, which sets
/// `receiveBetaUpdate` in IINA's UserDefaults. When true, the app's own Sparkle
/// delegate swaps the feed to `https://www.iina.io/appcast-beta.xml` at runtime.
///
/// We mirror that swap: read the same key and override the feed URL so the
/// SparkleAppcastSource fetches the correct channel. Unreadable → stable, the
/// conservative default that never pushes a surprise beta.
enum IINAChannel {
    static let bundleID = "com.colliderli.iina"

    static let stableFeed = URL(string: "https://www.iina.io/appcast.xml")!
    static let betaFeed = URL(string: "https://www.iina.io/appcast-beta.xml")!

    /// Map IINA's `receiveBetaUpdate` flag to a resolution. Pure and tested.
    static func resolve(receiveBeta: Bool) -> ResolvedChannel {
        receiveBeta
            ? ResolvedChannel(channel: .beta, feedOverride: betaFeed)
            : ResolvedChannel(channel: .stable, feedOverride: stableFeed)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(receiveBeta: readReceiveBeta())
    }

    /// Read `receiveBetaUpdate` from IINA's UserDefaults. Returns false (stable)
    /// when the key is missing.
    static func readReceiveBeta() -> Bool {
        // Force a fresh read from cfprefsd: this long-running menu-bar process can
        // otherwise serve a value cached from before IINA wrote the toggle.
        CFPreferencesAppSynchronize(bundleID as CFString)
        guard let value = CFPreferencesCopyAppValue(
            "receiveBetaUpdate" as CFString, bundleID as CFString
        ) else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
