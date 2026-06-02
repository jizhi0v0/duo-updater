import Foundation

/// The update channel a user actually *chose*, plus (for feed-swap apps) the
/// feed that serves it.
public struct ResolvedChannel: Sendable, Equatable {
    public let channel: ReleaseChannel
    /// The feed to use instead of the app's Info.plist `SUFeedURL`. Non-nil only
    /// for "feed-swap" apps (Fork, Surge) where each channel is a different URL.
    /// nil for channel-tag apps (DuoPaste, OrbStack) — the channel narrows which
    /// `<sparkle:channel>` we accept, the feed doesn't change.
    public let feedOverride: URL?

    public init(channel: ReleaseChannel, feedOverride: URL? = nil) {
        self.channel = channel
        self.feedOverride = feedOverride
    }
}

/// Resolves the channel a user chose for apps that hide that choice in a private
/// preference.
///
/// Why this is per-app: Sparkle never persists the user's channel. `allowedChannels`
/// is a delegate the host app computes at runtime; vendors keep the choice
/// wherever they like. Four apps, four encodings, none alike:
///   * DuoPaste → `UserDefaults[sparkleIncludePrereleases]`           (Bool: true→beta)
///   * Fork     → `UserDefaults[applicationUpdateChannel]`            (Int: 2→stable)
///   * Surge    → `…/Application Support/<id>/KDDefaults.plist`        (`IncludeBetaBuilds` Bool)
///   * OrbStack → `UserDefaults[updates_optinChannel]`               (String: the channel name)
///
/// So there is no generic reader. `ChannelBinding` is the single authority the
/// scanner consults; an app with no resolver returns nil and the generic
/// detection (build-inferred `<sparkle:channel>`, bundle-id/version suffix)
/// stays in charge.
///
/// Safety: a resolver only narrows to the user's opted-in channel and, when a
/// preference is unreadable, falls back to the app's shipped default — never to
/// a higher channel — so we can't push a prerelease at someone who didn't ask.
enum ChannelBinding {

    /// The user-chosen channel (and feed, for feed-swap apps) for `bundleID`, or
    /// nil when no bespoke resolver exists.
    static func resolve(bundleID: String?) -> ResolvedChannel? {
        switch bundleID {
        case DuoPasteChannel.bundleID: return DuoPasteChannel.resolveCurrent()
        case ForkChannel.bundleID:     return ForkChannel.resolveCurrent()
        case SurgeChannel.bundleID:    return SurgeChannel.resolveCurrent()
        case OrbStackChannel.bundleID: return OrbStackChannel.resolveCurrent()
        default:                       return nil
        }
    }
}
