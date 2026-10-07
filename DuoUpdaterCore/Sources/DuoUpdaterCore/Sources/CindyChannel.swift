import Foundation

/// Cindy (`com.xd.cindy`, and the Mainland China edition `com.xd.cindycn`) — one
/// bundle id per edition, two release tracks inside each, chosen with Settings ▸
/// General ▸ Experimental ▸ "Beta channel".
///
/// **The bundle cannot answer this.** A beta build reports the bare version: the
/// real `v0.1.96-beta` dmg's `CFBundleShortVersionString` is `0.1.96`, so
/// `ReleaseChannel.detect()` reads every copy as `.stable`, and without this
/// resolver the `.beta` rules could never apply to anything.
///
/// The signal is `update-channel-settings.json` in the app's Electron `userData`
/// directory, and that directory is NOT the same for the two editions:
/// `~/Library/Application Support/CindyGlobal/` for `com.xd.cindy`,
/// `~/Library/Application Support/Cindy/` for `com.xd.cindycn`. Measured: the
/// global edition's toggle wrote to `CindyGlobal/`, the CN edition's own staged
/// update landed under `Cindy/`. Reading one path for both would leave one
/// edition permanently on stable.
///
/// The file holds only the keys that were ever written (the app's
/// `createOverrideSettingsFile`). Flipping the toggle in the real app wrote
/// `{"enableBeta": true}` and then `{"enableBeta": false}` — off keeps the file
/// and the key. The app's own rule, mirrored here: a present `enableBeta` decides;
/// with no `enableBeta` key, `orgDefaultEnableBeta` (which the app writes for XD
/// organisation members) decides; with neither, stable. A present `enableBeta`
/// that is not `true` resolves to stable, as the app's `normalize` does.
///
/// Canary (`canary-flag.json`) is not read: GitHub publishes no canary builds, so
/// there is no rule for it to select, and a canary copy is only ever offered a
/// newer stable or beta release, never a downgrade.
///
/// Safety, in the one direction that matters: a missing, unreadable, oversized or
/// malformed file resolves to `.stable`. Nobody who did not turn beta on is
/// offered a beta.
///
/// Not watched for changes (`ChannelBinding.preferenceWatchCandidates`): the
/// `userData` directory holds the app's databases, logs and staged updates, and
/// FSEvents streams are recursive, so a root there would fire continuously while
/// the app runs. A flip is picked up on the next scan or on the app's own launch
/// or quit — same trade `CuaDriverChannel` and `SuperconductorChannel` document.
enum CindyChannel {
    static let globalBundleID = "com.xd.cindy"
    static let chinaBundleID = "com.xd.cindycn"

    /// The `userData` directory name each edition uses under Application Support.
    static func userDataDirectoryName(forBundleID bundleID: String) -> String? {
        switch bundleID.lowercased() {
        case globalBundleID: return "CindyGlobal"
        case chinaBundleID: return "Cindy"
        default: return nil
        }
    }

    static func settingsFileURL(forBundleID bundleID: String) -> URL? {
        userDataDirectoryName(forBundleID: bundleID).map {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("update-channel-settings.json", isDirectory: false)
        }
    }

    /// Map the settings file's bytes to a resolution. Pure and tested; nil data
    /// (no file) is the app's shipped default, stable.
    static func resolve(settings data: Data?) -> ResolvedChannel {
        ResolvedChannel(channel: enablesBeta(settings: data) ? .beta : .stable)
    }

    static func resolveCurrent(bundleID: String) -> ResolvedChannel {
        resolve(settings: settingsFileURL(forBundleID: bundleID).flatMap(readSettings))
    }

    /// The parsing half. Top level only, like the app's own store.
    static func enablesBeta(settings data: Data?) -> Bool {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        if let value = object["enableBeta"] { return isJSONTrue(value) }
        return object["orgDefaultEnableBeta"].map(isJSONTrue) ?? false
    }

    /// JSON `true` and nothing else. `as? Bool` would also take the number `1`,
    /// which the app's `normalize` (`typeof … == "boolean"`) does not.
    private static func isJSONTrue(_ value: Any) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    /// The real file is two short keys at most; the cap keeps a path that turns
    /// out to be something else from being read into memory wholesale.
    static func readSettings(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count <= 64 * 1024 else { return nil }
        return data
    }
}
