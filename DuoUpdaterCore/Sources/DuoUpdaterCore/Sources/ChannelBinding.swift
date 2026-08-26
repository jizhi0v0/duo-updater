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

    /// The `<sparkle:channel>` names this resolution unlocks, when the feed does
    /// NOT spell the channel the way `ReleaseChannel.rawValue` does.
    ///
    /// `SparkleAppcastSource` normally derives the tag from the channel itself
    /// (`.beta` → "beta"), which works because every feed-tagged app until now
    /// happened to agree with that spelling. BetterDisplay does not: its appcast
    /// tags prereleases `pre` and `internal`, and `ReleaseChannel` has no case
    /// that spells either. Deriving the tag there would build an allowed set of
    /// {default, "beta"} — matching NOTHING in the feed — and silently drop the
    /// user off their track.
    ///
    /// A Set rather than one name because a track can subsume a lower one: a
    /// BetterDisplay user with both toggles on is opted into `internal` AND
    /// `pre`, and must be offered whichever is newer.
    ///
    /// Empty (the default) = derive from `channel`, i.e. every app that existed
    /// before this field. Only consulted when the resolution is authoritative.
    public let sparkleChannelNames: Set<String>

    public init(
        channel: ReleaseChannel,
        feedOverride: URL? = nil,
        feedHTTPHeaders: [String: String] = [:],
        sparkleChannelNames: Set<String> = []
    ) {
        self.channel = channel
        self.feedOverride = feedOverride
        self.feedHTTPHeaders = feedHTTPHeaders
        self.sparkleChannelNames = sparkleChannelNames
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
///   * BetterDisplay → `UserDefaults[preReleaseChannel]` + `[internalReleaseChannel]`
///                                                          (two Bools, three tracks, feed-tagged `pre`/`internal`)
///   * Tailscale→ `UserDefaults[UnstableUpdatesEnabled]` + `[RCUpdatesEnabled]`
///                                                          (two Bools, three tracks)
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

    /// Every bundle id (lower-cased) a resolver above covers — i.e. an app whose
    /// channel choice hides in a private preference rather than in a bundle-id
    /// suffix or a `<sparkle:channel>` tag. Used by the menu-bar app to scope its
    /// "did the user just flip a channel toggle in the vendor app itself" recheck
    /// to only these apps, instead of polling every installed app's prefs.
    ///
    /// Deliberately excludes Ghostty: its binding is a fixed stable-only feed
    /// override with no user-settable preference, so there is nothing to watch.
    public static let boundBundleIDs: Set<String> = [
        DuoPasteChannel.bundleID.lowercased(),
        ForkChannel.bundleID.lowercased(),
        SurgeChannel.bundleID.lowercased(),
        OrbStackChannel.bundleID.lowercased(),
        TablePlusChannel.bundleID.lowercased(),
        CleanShotChannel.bundleID.lowercased(),
        TailscaleChannel.bundleID.lowercased(),
        IINAChannel.bundleID.lowercased(),
        AlfredChannel.bundleID.lowercased(),
        BetterDisplayChannel.bundleID.lowercased(),
    ]

    /// The directories holding every preference a resolver above reads, for a
    /// filesystem watcher to sit on.
    ///
    /// Why watching is needed at all: the two moments we used to notice a channel
    /// flip — the vendor app launching/quitting, and a DuoUpdater *window*
    /// appearing — both miss the ordinary case. The user opens Surge's settings,
    /// turns "Include beta builds" off and leaves Surge running; the only surface
    /// that ever shows them the result is the menu-bar popover, which is not a
    /// window and so never called `windowAppeared`. Worse, Surge writes
    /// `KDDefaults.plist` lazily: on 2026-08-23 it relaunched at 13:03:40 and the
    /// plist did not land until 13:08, so even the launch event read the OLD value
    /// off disk. The row stayed pinned to the beta build (6.9.0) while the app had
    /// been on release (6.8.1) for minutes.
    ///
    /// Cheap despite the breadth: `~/Library/Preferences` is shared with every
    /// unsandboxed app on the machine, but it is quiet — measured on this machine
    /// on 2026-08-23, one write burst in a 60-second window on an otherwise busy
    /// system — and the pass behind an event is a handful of `CFPreferences`/plist
    /// reads that does nothing at all unless a fingerprint actually changed.
    ///
    /// Two sources of self-inflicted events that measurement does NOT cover, both
    /// accepted rather than engineered around. Our own preference domain lives in
    /// that same directory, and `kFSEventStreamCreateFlagIgnoreSelf` does not filter
    /// it — `UserDefaults` writes are performed by `cfprefsd`, not by us — so every
    /// `prefs.lastCheckDate` write at the end of a check, and every ignore/skip
    /// toggle, costs one extra pass. And `AppDirectoryWatcher` re-arms on a 900s
    /// timer and on wake, each of which fires one more. A pass is ten reads and
    /// writes nothing back, so it cannot loop; the wake one is actively wanted,
    /// since a toggle flipped just before sleep arrives with no live event.
    ///
    /// Three roots, not ten files, because a preference file is *replaced* rather
    /// than written in place (cfprefsd writes a temp file and renames), so a
    /// per-file watch would go deaf the first time the file changed.
    ///
    /// Every root, whether or not it exists on this machine — `preferenceWatchPaths`
    /// below narrows to the ones a stream can be built from. Derived from the
    /// resolvers themselves (`SurgeChannel.defaultsFileURL`,
    /// `AlfredChannel.preferencesBaseURL`) rather than restating their paths, so the
    /// watcher cannot end up aimed somewhere the reader does not read.
    public static var preferenceWatchCandidates: [URL] {
        var roots: [URL] = [
            // Every `CFPreferencesCopyAppValue` resolver — DuoPaste, Fork, OrbStack,
            // TablePlus, CleanShot, Tailscale, IINA — reads a domain backed by
            // `~/Library/Preferences/<bundle id>.plist`. None of them is sandboxed,
            // so none lives in a container.
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences", isDirectory: true)
        ]
        // Surge keeps its choice out of UserDefaults entirely, in its own
        // `KDDefaults.plist` under Application Support (see `SurgeChannel`).
        roots.append(SurgeChannel.defaultsFileURL.deletingLastPathComponent())
        // Alfred's is nested deeper still, under a machine-specific `<hash>`
        // directory, so the watch is on the subtree rather than on one file.
        if let alfred = AlfredChannel.preferencesBaseURL { roots.append(alfred) }
        return roots
    }

    /// The subset an FSEvents stream can actually be built from. A stream is
    /// created from a fixed path list and a missing entry is dead weight; a
    /// resolver's app installing later is picked up on the next launch.
    public static var preferenceWatchPaths: [String] {
        var seen = Set<String>()
        return preferenceWatchCandidates
            .map(\.path)
            .filter { FileManager.default.fileExists(atPath: $0) && seen.insert($0).inserted }
    }

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
        case GhosttyChannel.bundleID.lowercased(): return GhosttyChannel.resolveCurrent()
        case BetterDisplayChannel.bundleID.lowercased():
            return BetterDisplayChannel.resolveCurrent()
        default:                       return nil
        }
    }
}
