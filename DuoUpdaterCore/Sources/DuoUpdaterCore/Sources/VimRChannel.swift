import Foundation

/// VimR (`com.qvacua.VimR`) — a Sparkle app whose feed is set in code, not in
/// Info.plist, with a stable and a "snapshot" feed chosen by an in-app
/// preference. Ghostty's shape (the bundle declares no `SUFeedURL`, so without
/// this binding no source answers) plus IINA's feed swap.
///
/// Settled from the open-source repo (`qvacua/vimr`, `master`):
///   * `VimR/VimR/AppDelegate.swift` — `UpdaterDelegate.feedURLString(for:)`
///     returns `…/qvacua/vimr/master/appcast_snapshot.xml` when
///     `useSnapshotChannel` is set, else `…/appcast.xml`. The flag is
///     `AppState.useSnapshotUpdate`, read at launch and on every state change.
///   * `VimR/VimR/States.swift` — that field encodes under the key
///     `use-snapshot-update-channel` (Bool, default false).
///   * `VimR/VimR/PrefMiddleware.swift` — the whole `AppState` is written as ONE
///     dictionary into `UserDefaults.standard` under the key
///     `PrefMiddleware.compatibleVersion`, `"168"`; `AppDelegate.init` reads the
///     same key back. So the toggle lives at
///     `CFPreferences(com.qvacua.VimR)["168"]["use-snapshot-update-channel"]`.
///   * `bin/build_jenkins.sh` — a stable release runs
///     `cp appcast.xml appcast_snapshot.xml`, and a snapshot release
///     (`snapshot/<build>` tag, GitHub prerelease) writes only
///     `appcast_snapshot.xml`. So the snapshot feed is the stable feed plus any
///     snapshot newer than the last stable, never behind it.
///
/// Every VimR build of either track is versioned by the same date-stamped
/// `CFBundleVersion` (`20261010.130648` stable, `20250715.204752` snapshot), which
/// is the feed's `sparkle:version`, so the build comparison is ordered across
/// the two tracks. `sparkle:shortVersionString` carries a `v` the bundle's
/// `CFBundleShortVersionString` lacks (`v0.67.0` vs `0.67.0`), and a snapshot's
/// is `SNAPSHOT-<build>`: neither is the comparison key.
///
/// ⚠️ This preference is the only thing that tells a snapshot user apart. A
/// snapshot bundle has the stable bundle id, name and Team, and
/// `ReleaseChannel.detect` reads its `SNAPSHOT-20250715.204752` version as
/// `.stable` (measured with `channel-verify` on the real package). So a
/// missing or unreadable preference resolves to an authoritative stable, and no
/// `detect()` signal is suppressed by that: there is none.
///
/// ⚠️ `"168"` has been VimR's preference key since at least 2019 (a bump to
/// `"169"` on 2023-10-29 was reverted on 2023-11-05, with no migration and no
/// cleanup). When VimR bumps it, the new build starts from defaults (stable)
/// under the new key and the old `"168"` dictionary stays behind with whatever
/// it held, which the user can no longer change from VimR. A stale `true` there
/// would push a user VimR treats as stable onto snapshots. So a domain that
/// holds any all-digit key above `stateKey` resolves to stable, whatever
/// `"168"` says: a bump can then only keep a snapshot user on stable, never the
/// reverse. Update `stateKey` when `PrefMiddleware.compatibleVersion` changes.
enum VimRChannel {
    static let bundleID = "com.qvacua.VimR"

    static let stableFeed = URL(string: "https://raw.githubusercontent.com/qvacua/vimr/master/appcast.xml")!
    static let snapshotFeed = URL(
        string: "https://raw.githubusercontent.com/qvacua/vimr/master/appcast_snapshot.xml")!

    /// `PrefMiddleware.compatibleVersion`: the UserDefaults key holding VimR's
    /// whole encoded `AppState`.
    static let stateKey = "168"
    /// `AppState.CodingKeys.useSnapshotUpdate`.
    static let snapshotKey = "use-snapshot-update-channel"

    /// Map VimR's snapshot toggle to a resolution. Pure and tested. Snapshot is
    /// `.preview`, the channel `ReleaseChannel` gives the word "snapshot"
    /// everywhere else. Both feeds are named explicitly: the bundle declares none.
    static func resolve(useSnapshot: Bool) -> ResolvedChannel {
        useSnapshot
            ? ResolvedChannel(channel: .preview, feedOverride: snapshotFeed)
            : ResolvedChannel(channel: .stable, feedOverride: stableFeed)
    }

    static func resolveCurrent() -> ResolvedChannel {
        // Force a fresh read from cfprefsd, as `IINAChannel` does: this
        // long-running process can otherwise serve a value cached from before
        // VimR wrote the toggle.
        CFPreferencesAppSynchronize(bundleID as CFString)
        let state = CFPreferencesCopyAppValue(stateKey as CFString, bundleID as CFString)
        let keys = CFPreferencesCopyKeyList(
            bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] ?? []
        return resolve(useSnapshot: useSnapshot(fromState: state as? [String: Any], domainKeys: keys))
    }

    /// The typed half of the read: false (stable) when the state dictionary or
    /// the key is missing or not a Bool, or when the domain holds a newer state
    /// key (VimR moved on and `"168"` is stale).
    static func useSnapshot(fromState state: [String: Any]?, domainKeys: [String] = []) -> Bool {
        if hasNewerStateKey(domainKeys) { return false }
        return (state?[snapshotKey] as? NSNumber)?.boolValue ?? false
    }

    /// True when some key is all ASCII digits and numerically above `stateKey`.
    static func hasNewerStateKey(_ keys: [String]) -> Bool {
        let current = Int(stateKey)!
        return keys.contains { key in
            !key.isEmpty && key.utf8.allSatisfy { (0x30...0x39).contains($0) }
                && (Int(key).map { $0 > current } ?? true)
        }
    }
}
