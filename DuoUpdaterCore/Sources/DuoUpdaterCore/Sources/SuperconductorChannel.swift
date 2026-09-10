import Foundation

/// super.engineering (`com.zarifpour.superconductor`) — one bundle id, and an
/// "Update channel" picker in the app's own Settings.
///
/// Today the picker has one entry. The vendor retired its stable track (#711 in its
/// own changelog, 2026-04-05, "Disable stable channel and enforce nightly-only
/// updates") and the Settings row says "Nightly is currently the only release track
/// available". The picker survived, though, and so did the setting behind it: a
/// top-level `update_channel` in `~/.superconductor/settings.json`, read as
/// `"nightly"` off a real install on 2026-09-11.
///
/// That key is the only on-disk channel signal there is. The bundle carries none —
/// its version is a bare commit hash, its name and bundle id are the same for every
/// build — so `ReleaseChannel.detect()` reads every copy as `.stable`, and without
/// this resolver the `.nightly` recipe would never apply to anything. `ChannelBinding`
/// is authoritative, so what this answers replaces `detect()` outright.
///
/// Safety, in the one direction that matters: a copy whose recorded choice is
/// anything but nightly resolves to a channel with no recipe, and is not offered the
/// nightly build. A recognised channel word maps to that channel; anything else maps
/// to `.stable`, the conservative end, which has no recipe either. No record at all
/// — file, key, or a readable value missing — resolves to `.nightly`: that is the
/// app's own default, and the only track the vendor publishes, not an escalation.
/// The file serialises the whole settings struct, defaults included (4 `null`s and
/// 15 `false`s among its 92 top-level keys on that install), so a copy that has run
/// once almost certainly carries the key; that it always does is inferred, not
/// measured.
///
/// Not watched for changes (`ChannelBinding.preferenceWatchCandidates`): FSEvents
/// streams are recursive and the app writes its logs inside `~/.superconductor`, so
/// a watch root there would fire continuously while it runs, for a choice that
/// currently has one possible value. The key is re-read on every scan, and on the
/// app's own launch and quit.
enum SuperconductorChannel {
    static let bundleID = "com.zarifpour.superconductor"

    /// The value the app writes for its nightly track, and the only one it offers.
    static let nightlyValue = "nightly"

    /// Map the recorded `update_channel` to a resolution. Pure and tested.
    ///
    /// nil — and an empty value — mean "no recorded choice", which is the app's own
    /// default. No feed override and no Sparkle channel tag: the app has no appcast,
    /// and the channel here only selects which `VendorProbeRecipe` answers.
    static func resolve(updateChannel: String?) -> ResolvedChannel {
        let value = updateChannel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let value, !value.isEmpty, value != nightlyValue else {
            return ResolvedChannel(channel: .nightly)
        }
        return ResolvedChannel(channel: ReleaseChannel(rawValue: value) ?? .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(updateChannel: readUpdateChannel())
    }

    /// The file the app keeps its settings in.
    static var settingsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".superconductor/settings.json", isDirectory: false)
    }

    /// `update_channel` from the settings file, or nil when the file, the key, or a
    /// non-null value is missing. The file is ~9 KB; the cap keeps a path that turns
    /// out to be something else from being read into memory wholesale.
    static func readUpdateChannel() -> String? {
        guard let data = try? Data(contentsOf: settingsFileURL), data.count <= 1024 * 1024
        else { return nil }
        return updateChannel(inSettings: data)
    }

    /// The parsing half, split out so it is testable without a file on disk.
    ///
    /// Top level only: a nested object that happens to carry a key of the same name
    /// is some other setting. A present value that is not a string is still a
    /// choice, and it is reported as its text rather than dropped — dropping it
    /// would read as "no record", which resolves to nightly.
    static func updateChannel(inSettings data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["update_channel"], !(value is NSNull)
        else { return nil }
        return (value as? String) ?? String(describing: value)
    }
}
