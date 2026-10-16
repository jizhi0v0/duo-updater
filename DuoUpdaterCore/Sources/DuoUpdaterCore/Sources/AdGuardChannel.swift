import Foundation

/// AdGuard for Mac (`com.adguard.mac.adguard`) — a Sparkle app whose three
/// tracks are three separately downloaded builds under one bundle id, each
/// naming its own track in its Info.plist: `AGChannel` = `release` / `beta` /
/// `nightly`, written together with the matching `SUFeedURL`
/// (`static.adtidy.org/mac/<track>/adguard-<track>-appcast.xml`). Read from the
/// real 2.20, 2.20 RC 1 and 2.20 Nightly 9 bundles, 2026-10-16.
///
/// No preference anywhere: 2.20 has no channel switch in its settings, and a
/// user changes track by installing the other build (`agrd.io/mac_beta`,
/// `agrd.io/mac_nightly`). So, like SwiftVM, not in `boundBundleIDs`.
///
/// What the binding changes is the label. Without it, `ReleaseChannel.detect()`
/// reads `2.20 RC 1` and `2.20 Nightly 9` as stable. It does not change what
/// is offered: each feed carries one untagged item, and `allowedChannels`
/// always admits untagged items, so every track still gets its own feed's item
/// (`AdGuardChannelTests`).
///
/// A value AdGuard has not shipped resolves nil, leaving `detect()` in charge.
enum AdGuardChannel {
    static let bundleID = "com.adguard.mac.adguard"

    /// The Info.plist key every AdGuard build sets to its own track.
    static let infoPlistKey = "AGChannel"

    /// The values the three builds carry, for `ChannelBinding.allResolutions`,
    /// which enumerates without a bundle.
    static let shippedValues = ["release", "beta", "nightly"]

    /// The track `AGChannel` names, or nil. Pure and tested.
    static func resolve(bundleStrings: [String: String]) -> ResolvedChannel? {
        switch bundleStrings[infoPlistKey] {
        case "release": return ResolvedChannel(channel: .stable)
        case "beta":    return ResolvedChannel(channel: .beta)
        case "nightly": return ResolvedChannel(channel: .nightly)
        default:        return nil
        }
    }
}
