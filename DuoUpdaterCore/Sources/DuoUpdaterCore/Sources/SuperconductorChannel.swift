import Foundation

/// super.engineering (`com.zarifpour.superconductor`) — one bundle id, and an
/// "Update channel" picker in the app's own Settings.
///
/// Today the picker has one entry. The vendor retired its stable track (#711 in its
/// own changelog, 2026-04-05, "Disable stable channel and enforce nightly-only
/// updates") and the Settings row says "Nightly is currently the only release track
/// available". The picker survived, though, and so did the setting behind it: a
/// top-level `update_channel` in the app's settings file, read as `"nightly"` off a
/// real install on 2026-09-11 (`~/.superconductor/settings.json`) and again on
/// 2026-10-15, after the rename, from `~/.super.engineering/settings.json` — a fresh
/// install of build `ac45e7aa` created that directory and no `~/.superconductor` at all.
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
/// streams are recursive and the app writes its logs inside its settings directory
/// (`~/.super.engineering/logs` on 2026-10-15), so
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

    /// The files the app has kept its settings in, current name first: builds since
    /// the super.engineering rename write `~/.super.engineering/settings.json`, older
    /// ones `~/.superconductor/settings.json`.
    static func settingsFileURLs(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [".super.engineering/settings.json", ".superconductor/settings.json"].map {
            home.appendingPathComponent($0, isDirectory: false)
        }
    }

    /// `update_channel` from the first settings file that exists, or nil when there
    /// is none, or the key or a non-null value is missing from it. The first file
    /// that exists answers alone, key or no key. On an upgraded copy both names are
    /// the same file: on 2026-10-15, launching `9cd78956` against a home that held
    /// only `~/.superconductor` created `~/.super.engineering` as a symlink to it,
    /// and `settings.json` had one inode through both paths. That matches the
    /// bundled `sc` helper's text ("Startup publishes the new data name as a link
    /// to existing legacy storage"; independent old and new profiles are an
    /// error). That launch also rewrote a staged `"stable"` to `"nightly"` and left
    /// the other 93 keys alone, and so did a second one against a home that already
    /// had a real `~/.super.engineering` directory (no migration, rewritten within
    /// 10 s). So today a non-nightly value does not survive the app starting. The file is ~9 KB; the cap keeps
    /// a path that turns out to be something else from being read into memory
    /// wholesale.
    static func readUpdateChannel(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        for url in settingsFileURLs(home: home) {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard data.count <= 1024 * 1024 else { return nil }
            return updateChannel(inSettings: data)
        }
        return nil
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
