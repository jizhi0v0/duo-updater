import Foundation

/// Osaurus (`com.dinoki.osaurus`) — a Sparkle app whose one feed tags EVERY item
/// `<sparkle:channel>release</sparkle:channel>`, with no untagged item.
///
/// The contract: the vendor's appcast script defaults `SPARKLE_CHANNEL` to
/// `release` and `scripts/setup_env.sh` switches it to `beta` only for a tag
/// containing `-beta`; the app's `SPUUpdaterDelegate.allowedChannels` returns
/// `["release"]`, plus `"beta"` when its `betaUpdatesEnabled` default is on. So
/// `release` is the stable line's tag, not a prerelease track. Without a binding,
/// `SparkleAppcastSource.allowedChannels` infers the channel from the installed
/// build's own feed item, which fails for an install absent from the feed: the
/// fallback is the default channel, the feed has no untagged item, and the row
/// reads unknown instead of offering the update.
///
/// Beta is deliberately NOT resolved. No `-beta` tag and no `beta`-tagged item
/// exists (checked 2026-09-29), so there is no artifact a `bindingProofs`
/// `.recipeAnchor` could be anchored on, and a non-stable binding naming `beta` by
/// hand would need one. Every install resolves `.stable`, whatever
/// `betaUpdatesEnabled` says — today that is also what the app itself is offered.
///
/// ⚠️ Reopen on the first `-beta` tag or `<sparkle:channel>beta</sparkle:channel>`
/// item: read `betaUpdatesEnabled`, add the beta resolution, and anchor a
/// `bindingProofs` entry on that real artifact.
///
/// Not in `boundBundleIDs`, same as CodeEdit: nothing a user sets changes the answer.
enum OsaurusChannel {
    static let bundleID = "com.dinoki.osaurus"

    /// The `<sparkle:channel>` value every stable Osaurus appcast item carries.
    static let releaseTag = "release"

    static func resolveCurrent() -> ResolvedChannel {
        ResolvedChannel(channel: .stable, sparkleChannelNames: [releaseTag])
    }
}
