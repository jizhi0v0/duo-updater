import Foundation

/// A single application discovered on disk, with the metadata we need to
/// figure out where it came from and how to check it for updates.
public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: String { bundleID ?? path.path }

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

    public init(
        name: String,
        bundleID: String?,
        shortVersion: String?,
        buildVersion: String?,
        path: URL,
        isMASApp: Bool,
        sparkleFeedURL: URL?,
        sparkleEdPublicKey: String? = nil,
        hasSelfUpdater: Bool = false
    ) {
        self.name = name
        self.bundleID = bundleID
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.path = path
        self.isMASApp = isMASApp
        self.sparkleFeedURL = sparkleFeedURL
        self.sparkleEdPublicKey = sparkleEdPublicKey
        self.hasSelfUpdater = hasSelfUpdater
    }
}
