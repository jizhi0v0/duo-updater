import Foundation

/// TextMate (`com.macromates.TextMate`) — one bundle id, a release and a beta
/// track, chosen with Settings ▸ Software Update.
///
/// **The bundle cannot answer this.** GitHub prereleases share the stable tag
/// shape (`v2.0.22`), the asset name and a plain marketing version, and every
/// 2.0.x build says `CFBundleVersion` 9800, so `ReleaseChannel.detect()` reads
/// every copy as stable.
///
/// Settled from source (textmate/textmate, `Frameworks/SoftwareUpdate`) and
/// measured on a real 2.0.23 install: the choice is the string preference
/// `SoftwareUpdateChannel` in the app's own domain, `release` or `beta`, and the
/// app's updater asks `api.textmate.org/releases/<that value>`. Picking beta in
/// the settings pane wrote `beta` at once, with the app still running; picking
/// release again removed the key rather than writing `release`. The
/// `nightly` track is only asked for while ⌥ is held on "Check Now", never
/// stored, so it has no resolution here.
///
/// Safety, in the one direction that matters: an absent or unreadable domain,
/// a non-string value, or any string but `beta` resolves to `.stable`, the
/// app's shipped default.
///
/// Watched with every other CFPreferences resolver (`~/Library/Preferences`,
/// the first root of `ChannelBinding.preferenceWatchCandidates`).
enum TextMateChannel {
    static let bundleID = "com.macromates.TextMate"
    static let key = "SoftwareUpdateChannel"

    static func resolve(channelPref: String?) -> ResolvedChannel {
        ResolvedChannel(channel: channelPref == "beta" ? .beta : .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        // A fresh read from cfprefsd, as `IINAChannel` does: this long-running
        // process can otherwise serve a value cached from before the flip.
        CFPreferencesAppSynchronize(bundleID as CFString)
        let value = CFPreferencesCopyAppValue(key as CFString, bundleID as CFString)
        return resolve(channelPref: value as? String)
    }
}
