import Foundation

/// Zettlr (`com.zettlr.app`) — one bundle id, two release tracks, chosen with
/// Preferences ▸ Advanced ▸ "Notify me about beta releases".
///
/// Settled from source (Zettlr/Zettlr, `develop`): the checkbox is the top-level
/// `checkForBeta` of `config.json` in the app's Electron `userData` directory
/// (`source/app/service-providers/config/index.ts` joins
/// `app.getPath('userData')` and `config.json`; the shipped default is `false`
/// in `get-config-template.ts`). `productName` is "Zettlr", so the directory is
/// `~/Library/Application Support/Zettlr/` unless the app was started with a
/// custom data directory. The update provider sends the value as `accept-beta`
/// to zettlr.com/api/releases/latest, which then counts prereleases.
///
/// Answers only for the opted-in value, the CotEditor shape: `true` is `.beta`,
/// anything else is nil, so `ReleaseChannel.detect()` keeps speaking for the
/// rest. A beta build reads `4.0.0-beta.5`, which `detect` already calls beta,
/// and a nightly build (`4.8.0+nightly`) is left to `detect` too.
///
/// Safety, in the one direction that matters: a missing, unreadable, oversized
/// or malformed file, or a `checkForBeta` that is not JSON `true`, resolves to
/// nil. Nobody who did not tick the box is moved onto the beta rule.
///
/// Not watched for changes (`ChannelBinding.preferenceWatchCandidates`): the
/// `userData` directory also holds the app's logs, stats and caches, and
/// FSEvents streams are recursive. A flip is picked up on the next scan or on
/// the app's own launch or quit — same trade `CindyChannel` documents.
enum ZettlrChannel {
    static let bundleID = "com.zettlr.app"

    static var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zettlr", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    static func resolve(checkForBeta: Bool) -> ResolvedChannel? {
        checkForBeta ? ResolvedChannel(channel: .beta) : nil
    }

    static func resolveCurrent() -> ResolvedChannel? {
        resolve(checkForBeta: checksForBeta(config: readConfig(at: configFileURL)))
    }

    /// The parsing half. Top level only, like the app's own config.
    static func checksForBeta(config data: Data?) -> Bool {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["checkForBeta"] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return false }
        return number.boolValue
    }

    /// The config is every preference the app has, a few kilobytes; the cap keeps
    /// a path that turns out to be something else from being read wholesale.
    static func readConfig(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count <= 1024 * 1024 else { return nil }
        return data
    }
}
