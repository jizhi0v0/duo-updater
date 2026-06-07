import Foundation

/// Alfred (`com.runningwithcrayons.Alfred`) — a feed-swap Sparkle app. Stable and
/// beta share one bundle id and the same Info.plist `SUFeedURL`
/// (`https://www.alfredapp.com/appcast.xml`). The user toggles "Pre-releases" in
/// Alfred's Update preferences, which sets `prereleases` in a machine-specific
/// plist under `Alfred.alfredpreferences/preferences/local/*/update/prefs.plist`.
/// When true, the app's own Sparkle delegate swaps the feed to
/// `https://www.alfredapp.com/prerelease.xml` at runtime.
///
/// We mirror that swap: read the same key and override the feed URL so the
/// SparkleAppcastSource fetches the correct channel. Unreadable → stable, the
/// conservative default that never pushes a surprise beta.
enum AlfredChannel {
    static let bundleID = "com.runningwithcrayons.Alfred"

    static let stableFeed = URL(string: "https://www.alfredapp.com/appcast.xml")!
    static let betaFeed = URL(string: "https://www.alfredapp.com/prerelease.xml")!

    /// Map Alfred's `prereleases` flag to a resolution. Pure and tested.
    static func resolve(prereleases: Bool) -> ResolvedChannel {
        prereleases
            ? ResolvedChannel(channel: .beta, feedOverride: betaFeed)
            : ResolvedChannel(channel: .stable, feedOverride: stableFeed)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(prereleases: readPrereleases())
    }

    /// Read `prereleases` from Alfred's machine-specific plist. Returns false (stable)
    /// when the file is missing or the key is not present.
    static func readPrereleases() -> Bool {
        // Locate the machine-specific plist: Alfred.alfredpreferences/preferences/local/<hash>/update/prefs.plist
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base = appSupport?.appendingPathComponent("Alfred/Alfred.alfredpreferences/preferences/local") else {
            return false
        }
        guard let localDirs = try? FileManager.default.contentsOfDirectory(atPath: base.path) else {
            return false
        }
        // Find the first directory containing an update/prefs.plist
        for dir in localDirs {
            let plistURL = base.appendingPathComponent("\(dir)/update/prefs.plist")
            if let plist = try? PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), options: [], format: nil) as? [String: Any] {
                if let value = plist["prereleases"] as? NSNumber {
                    return value.boolValue
                }
                // If key exists but is not NSNumber, treat as false
                return false
            }
        }
        return false
    }
}
