import Foundation

/// Maestro (`com.maestro.app`) — one bundle id, a stable and an RC track, chosen
/// with Settings ▸ "Include beta and release candidate updates".
///
/// **The bundle cannot answer this.** An RC build says `1.1.0-RC`, which
/// `ReleaseChannel.detect()` reads as stable (the `-RC` suffix is not one of its
/// words), and nothing else in it differs: same id, name and Team. Without this
/// resolver the beta rule could never apply to anything.
///
/// Settled from source (RunMaestro/Maestro) and measured on a real install:
///   * the toggle is `enableBetaUpdates` (Bool, default false) at the top level
///     of `maestro-settings.json`, an electron-store file. Turned on in 1.0.2,
///     it read `true`; turned off, `false`, the key kept.
///   * the file lives in the app's Electron `userData` directory,
///     `~/Library/Application Support/maestro/` — lowercase, as the real 1.0.2
///     install created it and as its own crash reporter names it, though the
///     repo's `userDataDir.ts` expects `Maestro` once packaged (one directory
///     on a case-insensitive volume either way) — unless `maestro-bootstrap.json` in that
///     directory names a `customSyncPath`, which then holds the settings file
///     instead (`src/main/stores/instances.ts`, `getCustomSyncPath`).
///   * with the toggle on, the app's update checker takes every non-draft
///     release, RCs included, sorts them by version and offers the highest
///     (`update-checker.ts`); off, it drops prereleases and `-rc`/`-beta` tags.
///     The RC rule does the same (`.highestVersion`).
///
/// Safety, in the one direction that matters: a missing, unreadable, oversized
/// or malformed file, a `customSyncPath` that does not lead to a readable file,
/// or a value that is not JSON `true` resolves to `.stable`. Nobody who did not
/// turn RCs on is offered one.
///
/// Not watched for changes (`ChannelBinding.preferenceWatchCandidates`): the
/// `userData` directory holds the app's databases, sessions and caches, and
/// FSEvents streams are recursive. A flip is picked up on the next scan or on
/// the app's own launch or quit — the same trade `CindyChannel` documents.
enum MaestroChannel {
    static let bundleID = "com.maestro.app"

    static var userDataDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/maestro", isDirectory: true)
    }

    static func resolve(settings data: Data?) -> ResolvedChannel {
        ResolvedChannel(channel: enablesBetaUpdates(settings: data) ? .beta : .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(settings: settingsFileURL(
            userData: userDataDirectoryURL,
            bootstrap: readJSON(at: userDataDirectoryURL.appendingPathComponent("maestro-bootstrap.json")))
            .flatMap(readJSON))
    }

    /// Where `maestro-settings.json` is: the custom sync directory when the
    /// bootstrap file names an absolute one, else `userData`. A bootstrap file
    /// that cannot be read is no redirect, as in the app.
    static func settingsFileURL(userData: URL, bootstrap: Data?) -> URL? {
        let name = "maestro-settings.json"
        guard let bootstrap,
              let object = try? JSONSerialization.jsonObject(with: bootstrap) as? [String: Any],
              let custom = object["customSyncPath"] as? String, !custom.isEmpty
        else { return userData.appendingPathComponent(name, isDirectory: false) }
        // The app refuses a relative path; a relative one here would resolve
        // against our own working directory, so it is no answer at all.
        guard custom.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: custom, isDirectory: true).appendingPathComponent(name, isDirectory: false)
    }

    /// The parsing half: top-level `enableBetaUpdates`, JSON `true` and nothing
    /// else.
    static func enablesBetaUpdates(settings data: Data?) -> Bool {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["enableBetaUpdates"] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return false }
        return number.boolValue
    }

    /// The real settings file is a few kilobytes; the cap keeps a path that
    /// turns out to be something else from being read wholesale.
    static func readJSON(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count <= 4 * 1024 * 1024 else { return nil }
        return data
    }
}
