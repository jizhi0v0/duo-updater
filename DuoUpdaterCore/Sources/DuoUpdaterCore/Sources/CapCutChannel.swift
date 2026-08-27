import Foundation

/// CapCut (`com.lemon.lvoverseas`, ByteDance) — a two-track app whose channel
/// choice is a checkbox inside the app's own "Version update" window ("Get early
/// access to beta features"), not a separate download.
///
/// The two tracks are real and visible in the vendor's own package names:
///   * stable → `CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg`
///   * beta   → `CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg`
/// and the installed bundle states which one it is in
/// `Contents/Resources/PackageConfig.plist` → `Channel Name` (`capcutpc_0` on a
/// stable install, read off this machine 2026-08-27).
///
/// The checkbox itself is NOT in UserDefaults, and looking for it there is the
/// trap this file exists to record. CapCut is sandboxed, so its preference domain
/// lives at `~/Library/Containers/com.lemon.lvoverseas/Data/Library/Preferences/`
/// — but neither plist in there carries the flag. Qt writes it to CapCut's own
/// user-data tree instead, in an INI file:
///
///     ~/Movies/CapCut/User Data/Config/updateInfo
///     [General]
///     joinBeta=true
///     need_show_automatic_updates_popup=false
///
/// That path is outside the sandbox container, so reading it does not go through
/// the App-Data gate that `~/Library/Containers/<other app>/Data` does; `~/Movies`
/// is also not one of the three user folders TCC challenges on
/// (Desktop/Documents/Downloads). Both reads here were exercised from a terminal
/// process, which is the weaker of the two contexts — if a future macOS extends
/// the gate to `~/Movies`, this resolver goes quiet and every CapCut install reads
/// as stable.
///
/// The sibling `globalSetting` file in the same directory holds
/// `enableAutoUpdate`, which is the OTHER radio pair in CapCut's settings
/// ("Automatic updates" vs "Get notified about updates") — that one decides
/// whether CapCut installs on its own, not which track it installs FROM, so it is
/// deliberately not read here.
///
/// Safety: `joinBeta=false` — the user opting OUT — resolves to `.stable`, and so
/// does anything unparseable. But "no record at all" is deliberately NOT treated
/// as stable, and that distinction is the whole reason a second file is read.
/// `ChannelBinding` is AUTHORITATIVE — whatever it answers REPLACES
/// `ReleaseChannel.detect()` — and `updateInfo` is written by the update window,
/// so a beta install that has never opened that window has no record at all.
/// Calling that "stable" labels the row Stable and pins it to a stable recipe
/// that reports an older version than the build it is running, forever.
///
/// Nothing else on disk would catch that. Measured on the real beta artifact
/// (`CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg`, downloaded and
/// mounted 2026-08-27), a beta bundle reports:
///
///     CFBundleShortVersionString  9.3.4531      ← no channel word at all
///     CFBundleVersion             9.4.0-beta4
///
/// and `ReleaseChannel.detect()` is handed the SHORT version, so its `-betaN`
/// rule never fires: detect() calls a beta install stable. Bundle id, app name
/// and app filename are identical across the two tracks as well. So this resolver
/// is not merely the best signal for CapCut, it is the only one — which is why
/// "no recorded preference" falls back to the build's own channel token rather
/// than to a constant. The token comes from the file CapCut writes next to the
/// preference:
///
///     ~/Movies/CapCut/User Data/Config/channel
///     [General]
///     tea_channel=capcutpc_0
///
/// which is CapCut's own copy of `Contents/Resources/PackageConfig.plist` →
/// `Channel Name`. Both values are read off real bundles, not inferred from the
/// filenames: `capcutpc_0` in this machine's stable install and `capcutpc_beta`
/// in the mounted beta dmg (2026-08-27). Absent or anything other than the beta
/// token → `.stable`, so this can never escalate a stable install.
///
/// The corner this fallback does not cover: a beta bundle that has never been
/// launched has neither file, so it reads as stable until first run. Closing that
/// would mean reading `PackageConfig.plist` out of the bundle, which needs the
/// app's path — something `ChannelBinding.resolve(bundleID:)` is not given.
///
/// Known divergence, stated rather than hidden: `joinBeta` is the user's opt-IN,
/// while the build CapCut itself offers is additionally gray-scaled per device by
/// the vendor. On this machine (2026-08-27) `joinBeta=true` and CapCut still said
/// "You are using the latest version" on 9.3.0, because the settings blob it was
/// served had picked stable for that device (`update_url` = the 9.3.0 dmg) even
/// though the beta track's newest build was 9.4.0-beta4. Our beta recipe reads
/// the track's newest build (`lastest_url`), not the per-device pick, so a user
/// who ticked the box can be shown a beta before CapCut's own rollout reaches
/// them. That is the honest reading of "the beta channel", and it is the only one
/// available without sending this machine's ByteDance device id to the vendor.
enum CapCutChannel {
    static let bundleID = "com.lemon.lvoverseas"

    /// The package channel token CapCut stamps into a beta build. Stable builds
    /// carry `capcutpc_0`, and so does the vendor's own fallback when the token is
    /// missing entirely, which is why only the beta token is named here.
    static let betaPackageToken = "capcutpc_beta"

    /// Map CapCut's two on-disk signals to a resolution. Pure and tested.
    ///
    /// `joinBeta` nil means "CapCut has never recorded a preference" — see the
    /// type's doc for why that must not collapse into `false`.
    ///
    /// No feed override and no Sparkle channel tag: CapCut embeds Sparkle only to
    /// run the install, and builds the update decision itself from a ByteDance
    /// settings blob (see the recipes in `VendorProbeRegistry`). The channel here
    /// exists purely to pick which of those two recipes applies.
    static func resolve(joinBeta: Bool?, packageChannel: String?) -> ResolvedChannel {
        if let joinBeta { return ResolvedChannel(channel: joinBeta ? .beta : .stable) }
        let onBetaBuild = packageChannel?
            .caseInsensitiveCompare(betaPackageToken) == .orderedSame
        return ResolvedChannel(channel: onBetaBuild ? .beta : .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(joinBeta: readJoinBeta(), packageChannel: readPackageChannel())
    }

    /// The directory holding both files this resolver reads. Exposed for the same
    /// reason `SurgeChannel.defaultsFileURL` is:
    /// `ChannelBinding.preferenceWatchCandidates` has to sit on it, and a watcher
    /// aimed anywhere else would look perfectly healthy while never firing. CapCut
    /// is the first bound app whose choice is neither in `~/Library/Preferences`
    /// nor in its sandbox container, so deriving the watch root from here rather
    /// than restating the path is what keeps the two from drifting apart.
    static var configDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/CapCut/User Data/Config", isDirectory: true)
    }

    /// The INI holding the user's `joinBeta` choice.
    static var updateInfoFileURL: URL {
        configDirectoryURL.appendingPathComponent("updateInfo", isDirectory: false)
    }

    /// The INI holding the running build's own package channel (`tea_channel`).
    static var packageChannelFileURL: URL {
        configDirectoryURL.appendingPathComponent("channel", isDirectory: false)
    }

    /// Read `joinBeta` out of the `[General]` section of CapCut's `updateInfo`
    /// INI. Nil when the file, the section or the key is missing.
    static func readJoinBeta() -> Bool? {
        guard let text = readINI(at: updateInfoFileURL) else { return nil }
        return joinBeta(inINI: text)
    }

    /// Read `tea_channel` out of the `[General]` section of CapCut's `channel`
    /// INI. Nil when the file, the section or the key is missing.
    static func readPackageChannel() -> String? {
        guard let text = readINI(at: packageChannelFileURL) else { return nil }
        return packageChannel(inINI: text)
    }

    /// Both files are a handful of lines; the cap is there so a path that turns
    /// out to be something else entirely is not read into memory wholesale.
    private static func readINI(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count <= 64 * 1024
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The `joinBeta` half, split out so it is testable without a file on disk.
    /// Nil when the key is not present under `[General]`.
    static func joinBeta(inINI text: String) -> Bool? {
        guard let value = value(of: "joinBeta", inINI: text) else { return nil }
        // Qt's QSettings writes `true`/`false`; `1`/`0` are accepted because the
        // same kind of setting is stored as an integer in some of CapCut's other
        // INIs and costs nothing to tolerate. Anything else — including an empty
        // value — is a spelling we do not understand, and an unreadable preference
        // must not be reported as a choice, so it reads as "no record" and hands
        // the decision to the installed build.
        switch value.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    /// The `tea_channel` half. Nil when the key is not present under `[General]`.
    static func packageChannel(inINI text: String) -> String? {
        value(of: "tea_channel", inINI: text)
    }

    /// First value of `key` in the `[General]` section of an INI, or nil.
    ///
    /// Section-aware on purpose. Both files CapCut writes today have exactly one
    /// section, but a bare "does the text contain joinBeta=true" scan would keep
    /// answering true if the vendor moved the key under some other heading —
    /// silently escalating a stable user to the beta track, which is the one
    /// direction this resolver is not allowed to get wrong.
    private static func value(of key: String, inINI text: String) -> String? {
        var inGeneral = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inGeneral = line.caseInsensitiveCompare("[General]") == .orderedSame
                continue
            }
            guard inGeneral, let separator = line.firstIndex(of: "=") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard name.caseInsensitiveCompare(key) == .orderedSame else { continue }
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            // QSettings quotes values it considers to need it, and CapCut's own
            // `looki_settings` in this same directory is full of them
            // (`LookiDomainKey="https://…"`). Neither key read here is quoted
            // today — but a quoted `"capcutpc_beta"` would silently stop matching
            // the token and read as a stable build.
            guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"")
            else { return value }
            return String(value.dropFirst().dropLast())
        }
        return nil
    }
}
