import Foundation

/// Cua Driver (`com.trycua.driver`) — one bundle id, two release trains, and a
/// choice the user makes either by passing `--channel` to the vendor's installer
/// or, later and without installing anything, with `cua-driver channel set`.
///
/// **The bundle cannot answer this question, and that is the whole reason this
/// type exists.** A nightly build reports a plain marketing version with no
/// suffix — the same string a stable release of that base version reports, and
/// the same string EVERY nightly of that base reports. Measured on the real
/// artifacts: three builds whose tags were `…-v0.28.2`, `…-v0.28.2-nightly.
/// 20260914.…` and `…-v0.28.2-nightly.20260915.…` all carry
/// `CFBundleShortVersionString = CFBundleVersion = 0.28.2`. So
/// `ReleaseChannel.detect()` reads every copy as `.stable`, and without this
/// resolver the `.nightly` rule could never apply to anything.
///
/// The only on-disk signal is `~/.cua-driver/release-channel`, a plain-text file
/// holding `stable` or `nightly`. The installer writes it **only when
/// `--channel` was passed explicitly** (`CHANNEL_EXPLICIT=1` guards the write),
/// so a default install leaves no file at all — which is why absent means
/// `.stable` here rather than "unknown".
///
/// ⚠️ **It records INTENT, not what is installed.** The vendor models the same
/// split itself: `cua-driver channel status` prints `Selected channel` (this
/// file) and `Current channel` (which train the running binary came from)
/// separately, and they diverge for real — pinning an exact stable version with
/// `CUA_DRIVER_RS_VERSION=…` installs a stable build without rewriting the file,
/// which was reproduced on a real install. Following intent is the RIGHT
/// behaviour and it is also the vendor's own: in that diverged state its
/// `check-update` offers the newest nightly, i.e. it carries the copy back to the
/// track the user chose. That is what a `.nightly` resolution here makes us do
/// too. The "what is actually installed" half is unavailable to us at any price —
/// it lives inside the executable, reachable only by running it, and a scanner
/// that executes third-party binaries to learn a version is not a trade this
/// project makes.
///
/// Safety, in the one direction that matters: anything other than a recorded
/// `nightly` resolves to `.stable`. A missing file, an unreadable one, an empty
/// one, or a value the vendor itself would reject (its installer exits 1 on
/// anything but the two words) all land on the conservative end. Nobody who did
/// not ask for nightly is offered one.
///
/// Not watched for changes (`ChannelBinding.preferenceWatchCandidates`): FSEvents
/// streams are recursive and the daemon writes its telemetry state and its own
/// `version_check.json` into `~/.cua-driver`, so a watch root there would fire
/// whenever the app runs. Same trade `SuperconductorChannel` documents.
///
/// ⚠️ That trade has a cost, and an earlier version of this comment understated
/// it by saying only the installer ever writes the file. It does not:
/// `cua-driver channel set <track>` rewrites it on its own, with nothing
/// installed and no download — measured, flipping `nightly`→`stable`→`nightly`
/// in consecutive commands. So a user can switch tracks in a second and we will
/// not see it until the next scan (or the app's own launch or quit). That is the
/// Surge-timeline shape the watcher exists for, accepted here because the
/// directory is one the daemon writes to continuously.
enum CuaDriverChannel {
    static let bundleID = "com.trycua.driver"

    /// The only value that moves a copy off stable. Spelled exactly as the
    /// vendor's installer writes it (`printf '%s\n' "$SELECTED_CHANNEL"`).
    static let nightlyValue = "nightly"

    /// Map the recorded channel to a resolution. Pure and tested.
    ///
    /// No feed override, no Sparkle channel tag, no request header: this app has
    /// no appcast, and the channel here only selects which `GitHubReleaseRule`
    /// answers. That is also why it is not in `channelBindingsNeedingProof` —
    /// its cross-channel obligation is discharged by the nightly rule's entry in
    /// `githubChannelProofs`, not by anything about the request.
    static func resolve(releaseChannel: String?) -> ResolvedChannel {
        let value = releaseChannel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ResolvedChannel(channel: value == nightlyValue ? .nightly : .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(releaseChannel: readReleaseChannel())
    }

    /// The file the vendor's installer records the choice in.
    ///
    /// ⚠️ `CUA_DRIVER_RS_HOME` can move this directory, and we deliberately do
    /// not consult it. A GUI process launched by `launchd` does not inherit the
    /// user's shell environment, so reading it here would work from a terminal
    /// and silently do nothing in the menu-bar app — a discriminator that is
    /// present exactly where it is tested and absent where it runs. Someone who
    /// has moved their driver home therefore resolves to `.stable`, which is the
    /// safe direction and the same answer they would get with no binding at all.
    static var channelFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cua-driver/release-channel", isDirectory: false)
    }

    /// The recorded channel, or nil when the file is missing or unreadable.
    ///
    /// The cap is small on purpose: the real file is one word and a newline (8
    /// bytes on a nightly install), so anything large at that path is something
    /// else and is not worth reading into memory to find out.
    static func readReleaseChannel() -> String? {
        guard let data = try? Data(contentsOf: channelFileURL), data.count <= 4096
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
