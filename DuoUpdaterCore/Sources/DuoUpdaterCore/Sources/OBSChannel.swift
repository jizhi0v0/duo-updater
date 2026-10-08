import Foundation

/// OBS Studio (`com.obsproject.obs-studio`) — a channel-tag Sparkle app whose
/// feed tags EVERY current item: `<sparkle:channel>stable</sparkle:channel>` or
/// `<sparkle:channel>beta</sparkle:channel>`. The only untagged item left in the
/// arm64 feed is a 2023 `29.0.2`.
///
/// What OBS itself does (read from `obsproject/obs-studio`):
///   * `OBSUpdateDelegate.allowedChannelsForUpdater` returns exactly ONE name,
///     the branch. Sparkle adds the default (untagged) channel on top, and that is
///     all: an updater on `beta` never sees a `stable`-tagged item, so a release
///     candidate is not offered the final release it precedes — it waits for the
///     next beta. This binding mirrors that rather than improving on it.
///   * The branch is `[General] UpdateBranch` in
///     `~/Library/Application Support/obs-studio/global.ini` (libobs `config_t`,
///     INI). No key means `"stable"`. The Settings → General → Update Channel
///     box writes the branch's name; a prerelease build writes `beta` on its own
///     the first time it runs (`AutoBetaOptIn`), and the key stays when the user
///     later installs a stable build again.
///
/// Why a binding is needed at all: without one, `SparkleAppcastSource` infers the
/// channel from the build that is running, which serves a beta build fine but
/// misses the user who chose beta and is still on a stable build. Measured
/// 2026-10-08: 32.2.2 with `UpdateBranch=beta` was "up to date" while OBS's own
/// updater would offer 33.0.0-beta6.
///
/// Why "no key" answers nil rather than stable: this resolution is
/// AUTHORITATIVE, and a beta build that has never been launched has no
/// `global.ini` yet. Answering stable would pin it to the stable items and offer
/// it nothing (its 33.0.0 is above every stable 32.x), forever. nil hands it back
/// to the build-inferred channel, which already keeps a stable build on `stable`
/// and a beta build on `beta`. A value we do not know answers nil for the same
/// reason; OBS would treat it as a channel name of its own, which `ReleaseChannel`
/// has no case for.
///
/// Why stable names its tag outright: `SparkleAppcastSource` derives the tag from
/// the channel, and for `.stable` that derivation is "the default channel only".
/// OBS's stable items are not on the default channel, so a derived stable would
/// match the 2023 item and nothing else. Beta needs no such declaration — the
/// feed spells it `beta`, which is `ReleaseChannel.beta.rawValue`.
///
/// Not watched by `ChannelBinding.preferenceWatchCandidates`: `global.ini` sits
/// in the same directory as OBS's `logs/`, `basic/` scene files and
/// `profiler_data/`, written continuously while OBS runs, and FSEvents streams
/// are recursive. A flip is picked up on the next scan or on OBS's own launch or
/// quit, the trade super.engineering and Cindy already make — including the
/// first flip out of "no key", which `ChannelSwitchDetector.fingerprint(of:)`
/// fingerprints as a state of its own.
enum OBSChannel {
    static let bundleID = "com.obsproject.obs-studio"

    /// The `<sparkle:channel>` OBS's feed puts its stable releases on.
    static let stableTag = "stable"

    /// Map OBS's `UpdateBranch` value to a resolution, or nil to leave the
    /// decision to the running build. Pure and tested.
    static func resolve(updateBranch: String?) -> ResolvedChannel? {
        switch updateBranch?.lowercased() {
        case "stable": return ResolvedChannel(channel: .stable, sparkleChannelNames: [stableTag])
        case "beta":   return ResolvedChannel(channel: .beta)
        default:       return nil
        }
    }

    static func resolveCurrent() -> ResolvedChannel? {
        resolve(updateBranch: readUpdateBranch())
    }

    static var globalConfigFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obs-studio/global.ini",
                                    isDirectory: false)
    }

    /// `[General] UpdateBranch`, or nil when the file, the section or the key is
    /// missing.
    static func readUpdateBranch() -> String? {
        guard let text = INIText.read(at: globalConfigFileURL) else { return nil }
        return updateBranch(inINI: text)
    }

    /// The parse half, testable without a file on disk.
    static func updateBranch(inINI text: String) -> String? {
        INIText.value(of: "UpdateBranch", inSection: "General", of: text)
    }
}
