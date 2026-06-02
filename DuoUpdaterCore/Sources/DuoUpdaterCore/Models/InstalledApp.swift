import Foundation

/// A single application discovered on disk, with the metadata we need to
/// figure out where it came from and how to check it for updates.
public struct InstalledApp: Sendable, Identifiable, Hashable {
    /// Identity is the on-disk path, which is unique per bundle. We deliberately
    /// do NOT key on `bundleID`: two copies of the same app can share one — e.g.
    /// the two JetBrains-Toolbox Android Studio installs (Otter + Koala) both
    /// carry `com.google.android.studio`. Keying on bundleID collapsed them to a
    /// single id, which made SwiftUI's `ForEach` render a blank ghost row for the
    /// collision and silently dropped one copy in `refreshLocal`'s id-keyed dict.
    public var id: String { path.path }

    /// A filesystem-safe token for scratch directories. `id` is a full path (with
    /// slashes), so installers can't use it directly in a path component.
    public var scratchSlug: String {
        (bundleID ?? path.lastPathComponent).replacingOccurrences(of: "/", with: "_")
    }

    /// Display name, e.g. "Visual Studio Code".
    public let name: String

    /// `CFBundleIdentifier`, e.g. "com.microsoft.VSCode". Nil if the bundle
    /// has no identifier (rare, usually a malformed app).
    public let bundleID: String?

    /// `CFBundleShortVersionString` — the user-facing "marketing" version
    /// (e.g. "1.95.3"). This is what we compare against feeds.
    public let shortVersion: String?

    /// `CFBundleVersion` — the build number (e.g. "1.95.3" or "45821").
    public let buildVersion: String?

    /// Location of the `.app` bundle on disk.
    public let path: URL

    /// True when the bundle contains `Contents/_MASReceipt/receipt`, meaning
    /// it was installed from the Mac App Store.
    public let isMASApp: Bool

    /// True when this is an iPhone/iPad app running on Apple Silicon. These are
    /// "wrapped": the real bundle lives at `<App>.app/Wrapper/<Inner>.app` (a
    /// flat iOS layout with no `Contents/`), and they can only be installed from
    /// the Mac App Store. The iTunes lookup's `version` is the correct remote
    /// version for them — there is no separate Mac build to scrape.
    public let isiOSAppOnMac: Bool

    /// True when JetBrains Toolbox installed and manages this app (per Toolbox's
    /// `state.json`). Its update channel is Toolbox, so we neither probe a
    /// vendor endpoint nor offer an install — we just label it as managed.
    public let isToolboxManaged: Bool

    /// `SUFeedURL` from Info.plist — present when the app ships the Sparkle
    /// auto-update framework. This is our highest-signal update source.
    public let sparkleFeedURL: URL?

    /// `SUPublicEDKey` — the app's base64 Ed25519 public key. Used to verify
    /// the EdDSA signature on a downloaded Sparkle update.
    public let sparkleEdPublicKey: String?

    /// True when the bundle ships its own auto-updater (e.g. Squirrel, used by
    /// Electron apps). For these we defer to the app's own update channel — it's
    /// usually fresher than the Homebrew cask, and double-updating conflicts —
    /// rather than installing a cask over it. (Sparkle is handled separately via
    /// `sparkleFeedURL`, which IS the app's own channel.)
    public let hasSelfUpdater: Bool

    /// The release channel this install is on (Stable, Beta, Canary, …),
    /// detected at scan time. A source is only allowed to update this app from a
    /// recipe that targets the SAME channel — so a stable-channel recipe can
    /// never overwrite a Canary/Beta install that happens to share a bundle id.
    /// Defaults to `.stable`, the channel every current recipe targets.
    public let releaseChannel: ReleaseChannel

    public init(
        name: String,
        bundleID: String?,
        shortVersion: String?,
        buildVersion: String?,
        path: URL,
        isMASApp: Bool,
        isiOSAppOnMac: Bool = false,
        isToolboxManaged: Bool = false,
        sparkleFeedURL: URL?,
        sparkleEdPublicKey: String? = nil,
        hasSelfUpdater: Bool = false,
        releaseChannel: ReleaseChannel = .stable
    ) {
        self.name = name
        self.bundleID = bundleID
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.path = path
        self.isMASApp = isMASApp
        self.isiOSAppOnMac = isiOSAppOnMac
        self.isToolboxManaged = isToolboxManaged
        self.sparkleFeedURL = sparkleFeedURL
        self.sparkleEdPublicKey = sparkleEdPublicKey
        self.hasSelfUpdater = hasSelfUpdater
        self.releaseChannel = releaseChannel
    }
}
