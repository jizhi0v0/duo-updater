import Foundation

/// The update channel a user actually *chose*, plus (for feed-swap apps) the
/// feed that serves it and (for header-keyed apps) the request headers that
/// unlock it.
public struct ResolvedChannel: Sendable, Equatable {
    public let channel: ReleaseChannel
    /// The feed to use instead of the app's Info.plist `SUFeedURL`. Non-nil only
    /// for "feed-swap" apps (Fork, Surge) where each channel is a different URL.
    /// nil for channel-tag apps (DuoPaste, OrbStack) — the channel narrows which
    /// `<sparkle:channel>` we accept, the feed doesn't change.
    public let feedOverride: URL?
    /// Extra HTTP headers to send when fetching the appcast. Non-empty only for
    /// "header-keyed" apps (TablePlus) where stable and beta share ONE feed URL
    /// and the server decides which builds to return from a request header
    /// (`X-Tiny-Beta-Update: true`) — neither a feed swap nor a `<sparkle:channel>`
    /// tag. Empty for every other app.
    public let feedHTTPHeaders: [String: String]

    public init(
        channel: ReleaseChannel,
        feedOverride: URL? = nil,
        feedHTTPHeaders: [String: String] = [:]
    ) {
        self.channel = channel
        self.feedOverride = feedOverride
        self.feedHTTPHeaders = feedHTTPHeaders
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
///   * TablePlus→ `UserDefaults[ViewSetting][IsReceiveBetaBuild]`     (Bool: true→beta, via header)
///   * CleanShot→ `UserDefaults[activationKey]`                       (String: license key → personalized feed)
///   * Tailscale→ `UserDefaults[UnstableUpdatesEnabled]`             (Bool: true→unstable)
///
/// So there is no generic reader. `ChannelBinding` is the single authority the
/// scanner consults; an app with no resolver returns nil and the generic
/// detection (build-inferred `<sparkle:channel>`, bundle-id/version suffix)
/// stays in charge.
///
/// Safety: a resolver only narrows to the user's opted-in channel and, when a
/// preference is unreadable, falls back to the app's shipped default — never to
/// a higher channel — so we can't push a prerelease at someone who didn't ask.
/// `public` so the `channel-verify` harness resolves a channel exactly the way
/// `AppScanner` does. It used to run `ReleaseChannel.detect()` alone, which for
/// these apps is only half the answer — it reported Alfred as stable while the
/// app had it on beta, so a verification run exercised a recipe the user's
/// machine would never reach.
public enum ChannelBinding {

    /// The user-chosen channel (and feed, for feed-swap apps) for `bundleID`, or
    /// nil when no bespoke resolver exists.
    ///
    /// Matched case-insensitively: a `CFBundleIdentifier` is case-insensitive
    /// (TablePlus ships `com.tinyapp.TablePlus` but its prefs live under the
    /// lower-cased domain), so a case-sensitive `switch` silently failed to bind
    /// — same convention `ChangelogRecipe.recipe(forBundleID:)` already uses.
    public static func resolve(bundleID: String?) -> ResolvedChannel? {
        guard let id = bundleID?.lowercased() else { return nil }
        switch id {
        case DuoPasteChannel.bundleID.lowercased(): return DuoPasteChannel.resolveCurrent()
        case ForkChannel.bundleID.lowercased():     return ForkChannel.resolveCurrent()
        case SurgeChannel.bundleID.lowercased():    return SurgeChannel.resolveCurrent()
        case OrbStackChannel.bundleID.lowercased(): return OrbStackChannel.resolveCurrent()
        case TablePlusChannel.bundleID.lowercased(): return TablePlusChannel.resolveCurrent()
        case CleanShotChannel.bundleID.lowercased(): return CleanShotChannel.resolveCurrent()
        case TailscaleChannel.bundleID.lowercased(): return TailscaleChannel.resolveCurrent()
        case IINAChannel.bundleID.lowercased():    return IINAChannel.resolveCurrent()
        case AlfredChannel.bundleID.lowercased():  return AlfredChannel.resolveCurrent()
        default:                       return nil
        }
    }
}
