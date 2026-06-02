import Foundation

/// Surge (`com.nssurge.surge-mac`) — a feed-swap app, and then some. It ships
/// release and beta Sparkle feeds and chooses at runtime; the channel is hidden:
///   * the feeds carry no `<sparkle:channel>` elements,
///   * the signed Info.plist `SUFeedURL` is the release feed, and
///   * at runtime Surge builds an internal `surge-data-pipe:///appcast.xml?beta=<0|1>`
///     request rather than fetching that URL.
///
/// The choice lives in `IncludeBetaBuilds` inside Surge's own
/// `…/Application Support/com.nssurge.surge-mac/KDDefaults.plist` — NOT in
/// UserDefaults. We read that plist directly and pick the matching public feed.
enum SurgeChannel {
    static let bundleID = "com.nssurge.surge-mac"

    static let releaseFeed = URL(string: "https://nssurge.com/mac/latest/appcast-signed.xml")!
    static let betaFeed = URL(string: "https://nssurge.com/mac/latest/appcast-signed-beta.xml")!

    /// Map Surge's `IncludeBetaBuilds` flag to a resolution. Pure and tested.
    static func resolve(includeBeta: Bool) -> ResolvedChannel {
        includeBeta
            ? ResolvedChannel(channel: .beta, feedOverride: betaFeed)
            : ResolvedChannel(channel: .stable, feedOverride: releaseFeed)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(includeBeta: readIncludeBeta())
    }

    /// Read `IncludeBetaBuilds` from Surge's Application Support plist. Returns
    /// false (release) if the file or key is missing — the conservative default.
    static func readIncludeBeta() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("KDDefaults.plist", isDirectory: false)
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any]
        else { return false }
        return (plist["IncludeBetaBuilds"] as? NSNumber)?.boolValue ?? false
    }
}
