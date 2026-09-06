import Foundation

/// CotEditor (`com.coteditor.CotEditor`) — the first binding whose rule includes
/// the INSTALLED BUILD, not just a preference.
///
/// The vendor's own updater says it in one line
/// (`UpdaterManager.swift`, read from the published source 2026-09-06):
///
/// ```swift
/// let checksBeta = (Bundle.main.version!.isPrerelease
///                   || UserDefaults.standard[.checksUpdatesForBeta])
/// return checksBeta ? ["prerelease"] : []
/// ```
///
/// and its Settings pane says the same thing to the user: "Update to prereleases
/// when available — **regardless of this setting, new prereleases are always
/// included while using a prerelease**."
///
/// So the two halves are different KINDS of subscription, and only one of them is
/// this binding's business:
///
///  * `isPrerelease` is temporary — it lapses the moment the copy lands on a
///    release — and it is already answered without any vendor knowledge:
///    `ReleaseChannel.detect()` reads the `-beta.N` suffix off the version string.
///  * The preference is a standing opt-in, invisible from the outside, and the
///    ONLY way to know that a copy running `7.0.9` wants `7.1.0-beta.6`.
///
/// Hence the shape: **answer only when the preference says beta, and answer nil
/// otherwise** so the version string keeps speaking. A binding that returned
/// `.stable` for an unticked box would be authoritative and would therefore
/// SILENCE `detect()` — pinning a `7.1.0-beta.3` copy, whose owner never touched
/// the box, to the stable line. That is the direction #368 was about, arriving
/// through a different door.
///
/// Four states, all four correct with those two halves in place:
///
/// | installed | box | resolution | offered |
/// |---|---|---|---|
/// | `7.1.0-beta.6` | on  | binding → beta | the beta line |
/// | `7.1.0-beta.3` | off | nil → `detect()` → beta | the beta line |
/// | `7.0.9` | on  | binding → beta | `7.1.0-beta.6` |
/// | `7.0.9` | off | nil → `detect()` → stable | the stable line |
///
/// No `feedOverride`, no `sparkleChannelNames`: the channel here selects which
/// `GitHubReleaseRule` answers, and the appcast — whose single prerelease slot is
/// what made #368 possible — is deliberately not read at all. See the audit.
enum CotEditorChannel {
    static let bundleID = "com.coteditor.CotEditor"

    /// The app is sandboxed and keeps this in its CONTAINER, unlike every other
    /// binding here and unlike CapCut, the one other sandboxed app in the table
    /// (whose flag is an INI outside its container).
    /// `~/Library/Preferences/com.coteditor.CotEditor.plist` does not exist; the
    /// container copy does, and a shell WITHOUT Full Disk Access reads it — the
    /// container is the app's own jail, not a wall against other processes of the
    /// same user.
    static var preferencesDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Containers/\(bundleID)/Data/Library/Preferences",
                isDirectory: true)
    }

    /// The file `readChecksUpdatesForBeta` reads. Exposed for the same reason
    /// `SurgeChannel.defaultsFileURL` is: `ChannelBinding.preferenceWatchCandidates`
    /// has to sit on the directory the reader actually reads, and a watcher aimed
    /// anywhere else is a guard with the wrong discriminator.
    static var preferencesFileURL: URL {
        preferencesDirectoryURL.appendingPathComponent("\(bundleID).plist", isDirectory: false)
    }

    /// Map the standing opt-in to a resolution. Pure and tested.
    ///
    /// nil is a real answer — "this preference has nothing to say about this
    /// copy" — and it is what keeps `ReleaseChannel.detect()` in charge of the
    /// half the preference does not cover. Same use of nil as
    /// `CleanShotChannel.resolve(activationKey:)`.
    static func resolve(checksUpdatesForBeta: Bool) -> ResolvedChannel? {
        checksUpdatesForBeta ? ResolvedChannel(channel: .beta) : nil
    }

    static func resolveCurrent() -> ResolvedChannel? {
        resolve(checksUpdatesForBeta: readChecksUpdatesForBeta())
    }

    /// Read `checksUpdatesForBeta` out of the container plist. False when the file
    /// or the key is missing, which is also CotEditor's own reading of it — its
    /// Settings toggle defaults off.
    ///
    /// ⚠️ **`CFPreferencesCopyAppValue` does NOT work for this app**, and the first
    /// version of this binding used it. Measured 2026-09-06 with the box ticked and
    /// the container plist holding `checksUpdatesForBeta = 1`:
    ///
    /// ```
    /// CFPreferencesCopyAppValue("checksUpdatesForBeta", "com.coteditor.CotEditor") → nil
    /// Data(contentsOf: <container>/com.coteditor.CotEditor.plist) → the key, true
    /// ```
    ///
    /// A sandboxed app's domain does not resolve to its container for a process
    /// that is not that app: `CFPreferences` looks in
    /// `~/Library/Preferences/<id>.plist`, which does not exist here. `defaults
    /// read com.coteditor.CotEditor checksUpdatesForBeta` DOES print 1 — `defaults`
    /// searches container paths itself — and that is the trap: the shell command
    /// used to check this is not the API the code calls. Read the file, the way
    /// `SurgeChannel` reads its own plist.
    static func readChecksUpdatesForBeta() -> Bool {
        decodeChecksUpdatesForBeta(at: preferencesFileURL)
    }

    /// Split out so the decoding is testable against a plist written to a temp
    /// directory. The path is the part no unit test can pin — only a live read on
    /// a machine with CotEditor installed says whether it is right, which is how
    /// the `CFPreferences` version was caught.
    static func decodeChecksUpdatesForBeta(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any]
        else { return false }
        return (plist["checksUpdatesForBeta"] as? NSNumber)?.boolValue ?? false
    }
}
