import Foundation

/// Alfred (`com.runningwithcrayons.Alfred`) — the user's channel lives in the
/// app's own preferences: toggling "Pre-releases" in Alfred's Update preferences
/// sets `prereleases` in a machine-specific plist under
/// `Alfred.alfredpreferences/preferences/local/*/update/prefs.plist`.
///
/// We read that same key and report the channel it selects, so our endpoint
/// agrees with the app's own choice. Channel only — see `resolve` for why this
/// resolution deliberately carries no feed override. Unreadable → stable, the
/// conservative default that never pushes a surprise beta.
enum AlfredChannel {
    static let bundleID = "com.runningwithcrayons.Alfred"

    /// Map Alfred's `prereleases` flag to a resolution. Pure and tested.
    ///
    /// Channel only — deliberately NO feed override. Alfred never was a Sparkle app:
    /// its update endpoint serves an Apple *plist* (`version` / `build` / `location`
    /// keys), not an appcast, and the two appcast URLs this binding used to point at
    /// (`alfredapp.com/appcast.xml` and `/prerelease.xml`) now 404 — which is what
    /// left the row permanently "Failed" behind an unreadable `SparkleError error 0`.
    /// The endpoints are read by `VendorProbeRecipe` instead; this resolver's job is
    /// just to say which channel the user is on, so the right one is picked.
    static func resolve(prereleases: Bool) -> ResolvedChannel {
        ResolvedChannel(channel: prereleases ? .beta : .stable, feedOverride: nil)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(prereleases: readPrereleases())
    }

    /// The tree `readPrereleases` walks. Exposed so
    /// `ChannelBinding.preferenceWatchCandidates` watches the same place the reader
    /// reads, rather than a second hand-written copy of this path that can drift
    /// out from under it. The `<hash>` directory below is machine-specific, which
    /// is why the watch is on the subtree and not on one file.
    static var preferencesBaseURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Alfred/Alfred.alfredpreferences/preferences/local")
    }

    /// Read `prereleases` from Alfred's machine-specific plist. Returns false (stable)
    /// when the file is missing or the key is not present.
    static func readPrereleases() -> Bool {
        // Locate the machine-specific plist: Alfred.alfredpreferences/preferences/local/<hash>/update/prefs.plist
        guard let base = preferencesBaseURL else {
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
