import Foundation

/// AirBuild (`plus.yellow.AirBuild`) — a channel-tag Sparkle app: one feed
/// (`release.air.build/macos/appcast.xml`), betas tagged `<sparkle:channel>beta`,
/// stable items untagged.
///
/// Settings ▸ General ▸ "Receive Beta Updates" is `UserDefaults`
/// `ReceiveBetaVersions` (Bool). The app is not sandboxed, so the domain is
/// `~/Library/Preferences/plus.yellow.AirBuild.plist`. Confirmed on the real app
/// (1.1.93, 2026-10-19): ticking the box wrote `ReceiveBetaVersions = 1`, and
/// unticking it wrote a boolean `0`; the key stays. A fresh install has no key.
/// The binary names it in `AppUpdater.swift` beside `allowedChannelsForUpdater:`.
///
/// Why a binding: a beta build carries no channel mark. 1.1.120 (beta) and
/// 1.1.121 (stable) are both `CFBundleShortVersionString` 1.1 and both carry
/// `AirBuildReleaseLabel` `v1.1-beta.143`, so `ReleaseChannel.detect` calls every
/// copy stable. The feed keeps every build, so the feed-side inference does find
/// an installed beta; what it cannot see is a stable copy whose owner ticked the
/// box, which the app's own updater would move onto the betas.
///
/// Unticked or absent resolves to `.stable`, authoritatively, as for
/// `RuntimeViewerChannel`: the app's default is off, and its updater then offers
/// the untagged items only, even to a beta build. Measured with the app's own
/// "Check for Updates…" against a local feed holding a beta-tagged 1.1.150 and
/// an untagged 1.1.140 (feed swapped in through the `SUFeedURL` user default):
/// 1.1.93 unticked → 1.1.140; 1.1.93 ticked → 1.1.150; the beta 1.1.120 unticked
/// → 1.1.140. So `nil`, which would let feed inference keep a beta copy on the
/// betas, would disagree with the app.
/// The `beta` tag is derived from `ReleaseChannel.beta`, the spelling the feed uses.
enum AirBuildChannel {
    static let bundleID = "plus.yellow.AirBuild"

    static func resolve(receiveBetaVersions: Bool) -> ResolvedChannel {
        ResolvedChannel(channel: receiveBetaVersions ? .beta : .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(receiveBetaVersions: readReceiveBetaVersions())
    }

    static func readReceiveBetaVersions() -> Bool {
        CFPreferencesAppSynchronize(bundleID as CFString)
        guard let value = CFPreferencesCopyAppValue(
            "ReceiveBetaVersions" as CFString, bundleID as CFString
        ) else { return false }
        return receiveBetaVersions(from: value)
    }

    /// `UserDefaults.bool(forKey:)`, which an `@AppStorage` toggle reads with,
    /// also accepts the strings "YES"/"true"/"1".
    static func receiveBetaVersions(from value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return ["yes", "true", "1"].contains(text.lowercased()) }
        return false
    }
}
