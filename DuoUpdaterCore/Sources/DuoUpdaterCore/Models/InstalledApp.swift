import CryptoKit
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

    /// A filesystem-safe token for scratch directories. It includes a path token
    /// because two installed copies can share one bundle id and still update at
    /// the same time. The token is a SHA-256 digest of the resolved path, NOT
    /// `String.hashValue` — that is seeded per process, so a dir named off it
    /// couldn't be reclaimed by name on a later run. `SparkleInstaller` /
    /// `VendorInstaller` name their scratch dir off this and remove a leftover
    /// one (from a hard crash mid-install) by name before reusing it, so the slug
    /// must be stable across launches.
    public var scratchSlug: String {
        let label = Self.safePathComponent(bundleID ?? path.deletingPathExtension().lastPathComponent)
        let resolved = path.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(resolved.utf8))
        let pathToken = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(label)-\(pathToken)"
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

    /// A build identifier the app's OWN updater versions by, kept somewhere in the
    /// bundle other than `CFBundleVersion`. Nil for almost every app.
    ///
    /// This is deliberately a SECOND field rather than a replacement for
    /// `buildVersion` (the shape `AppScanner.buildVersionIsOverridden` describes).
    /// Overriding would have cost a working feature: the restart badge compares the
    /// disk build against the *running* one, and `lsappinfo` can only ever report
    /// `CFBundleVersion` — so every app whose stored build is something else is
    /// skipped there, and Firefox, which self-updates in the background and then
    /// needs a restart, is precisely an app that badge is for. Keeping both means
    /// the badge keeps reading `CFBundleVersion` on both sides while a source that
    /// speaks the vendor's namespace can ask for that one instead.
    ///
    /// Mozilla is the case in hand: `Contents/Resources/application.ini` carries
    /// `BuildID=20260826090609`, which is the string Mozilla's own update service
    /// answers with, byte for byte. See ``BuildNamespace``.
    public let vendorBuildVersion: String?

    /// Which of an installed bundle's two build identifiers a remote version is
    /// expressed in. A source that reports a build states this so the comparison
    /// can never be made across namespaces — the failure mode being a silent
    /// constant answer rather than a visible error.
    public enum BuildNamespace: String, Sendable, Hashable, Codable {
        /// `CFBundleVersion`. Every source but the Mozilla probes.
        case bundle
        /// The vendor's own build identifier, ``InstalledApp/vendorBuildVersion``.
        case vendor
    }

    /// The installed build to compare a remote build against, in the namespace the
    /// remote declared. Nil when this bundle carries no value in that namespace,
    /// which the engine must treat as "cannot tell" rather than falling back to the
    /// other one.
    public func buildVersion(in namespace: BuildNamespace) -> String? {
        switch namespace {
        case .bundle: return buildVersion
        case .vendor: return vendorBuildVersion
        }
    }

    /// Both version strings this bundle carries, for anything deciding "is this
    /// newer" or "has it changed". Nine sites used to open-code
    /// `buildVersion ?? shortVersion` and five more used the marketing-first
    /// order, which cannot discriminate for an app that freezes its marketing
    /// string across builds. See ``VersionSide``.
    public var versionSide: VersionSide {
        VersionSide(marketing: shortVersion, build: buildVersion)
    }

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

    /// True when this build was installed via TestFlight (it appears as a macOS
    /// build in TestFlight's local DB). Updates flow through TestFlight, so — like
    /// MAS/Toolbox — we never probe another source or offer an install; we read
    /// TestFlight's cached "latest build" to show whether a newer beta exists.
    /// A TestFlight app also carries a `_MASReceipt`, so this is decided *before*
    /// the MAS flag to keep it from being mislabeled as an App Store install.
    public let isTestFlightApp: Bool

    /// `SUFeedURL` from Info.plist — present when the app ships the Sparkle
    /// auto-update framework. This is our highest-signal update source.
    public let sparkleFeedURL: URL?

    /// The electron-builder update configuration from
    /// `Contents/Resources/app-update.yml`, when the bundle carries one. The
    /// electron counterpart of ``sparkleFeedURL``: read from a file the build
    /// system generates, so it is a fact about the bundle rather than a guess
    /// about it. See `ElectronUpdateConfig`.
    public let electronUpdate: ElectronUpdateConfig?

    /// Extra HTTP headers to send when fetching `sparkleFeedURL`. Non-empty only
    /// for "header-keyed" apps (TablePlus) where the appcast URL is shared across
    /// channels and a request header selects which builds the server returns. Set
    /// from the app's channel preference at scan time (see `ChannelBinding`).
    public let sparkleFeedHeaders: [String: String]

    /// The `<sparkle:channel>` tags this install is opted into, when the feed
    /// spells them differently from `releaseChannel.rawValue` (BetterDisplay's
    /// `pre` / `internal`). Empty = derive the tag from `releaseChannel`, which
    /// is every other app. Set at scan time from `ChannelBinding`, and only
    /// consulted when `channelIsAuthoritative` is true.
    public let sparkleChannelNames: Set<String>

    /// `SUPublicEDKey` — the app's base64 Ed25519 public key. Used to verify
    /// the EdDSA signature on a downloaded Sparkle update.
    public let sparkleEdPublicKey: String?

    /// True when the bundle ships its own auto-updater (e.g. Squirrel, used by
    /// Electron apps). For these we defer to the app's own update channel — it's
    /// usually fresher than the Homebrew cask, and double-updating conflicts —
    /// rather than installing a cask over it. (Sparkle is handled separately via
    /// `sparkleFeedURL`, which IS the app's own channel.)
    public let hasSelfUpdater: Bool

    /// True when the bundle embeds Sparkle.
    ///
    /// Deliberately NOT folded into `hasSelfUpdater`, even though Sparkle is
    /// self-updating by any plain reading of the words. That flag decides
    /// `defersToSelfUpdater` — whether we hand a running app to its own updater
    /// instead of installing over it — and hundreds of apps here embed Sparkle
    /// while being updated perfectly well by us. Widening the flag to match its
    /// name would change install policy for every one of them.
    ///
    /// What this is for is narrower: Sparkle stages a downloaded build and applies
    /// it on the app's next quit, exactly as Squirrel does, and that state has to
    /// be visible so the row can offer Relaunch instead of re-downloading bytes
    /// already sitting in the cache. See `SelfUpdaterStaging`.
    public let hasSparkleUpdater: Bool

    /// The release channel this install is on (Stable, Beta, Canary, …),
    /// detected at scan time. A source is only allowed to update this app from a
    /// recipe that targets the SAME channel — so a stable-channel recipe can
    /// never overwrite a Canary/Beta install that happens to share a bundle id.
    /// Defaults to `.stable`, the channel every current recipe targets.
    public let releaseChannel: ReleaseChannel

    /// True when `releaseChannel` came from reading the app's own channel
    /// preference (see `ChannelBinding`) rather than being inferred. When set,
    /// `SparkleAppcastSource` trusts it to gate `<sparkle:channel>` items —
    /// catching a user who opted into beta but is still on a stable build, which
    /// build-inference alone can't see. Defaults to false (infer from the build).
    public let channelIsAuthoritative: Bool

    /// The build Toolbox records as installed for this app (`buildNumber` in its
    /// `state.json`, e.g. "262.132.21"), for a Toolbox-managed install. This is
    /// the same 3-part build namespace a Toolbox verdict reports as its latest,
    /// which the on-disk `shortVersion` is NOT (it's marketing for the IDEs, and a
    /// divergent runtime track for Air/Fleet) — so it's the only local value a
    /// network-free rescan can compare a cached Toolbox verdict against. Nil for
    /// everything Toolbox doesn't manage.
    public let toolboxInstalledBuild: String?

    /// The App Store numeric track id (`kMDItemAppStoreAdamID` from Spotlight),
    /// when this is a Mac App Store / TestFlight install Spotlight has indexed.
    /// Lets the UI deep-link straight to the product page without a network
    /// lookup. Nil for non-store apps, or when the metadata is absent/zero
    /// (sideloaded copies report 0).
    public let appStoreAdamID: Int?

    /// A Toolbox-managed install we should route through its `VendorProbeRecipe`
    /// instead of deferring to Toolbox's own verdict.
    ///
    /// Toolbox-managed apps normally skip every other source (see
    /// `UpdateChecker.check`) and report whatever Toolbox's verdict says. But
    /// Android Studio's Canary/Beta previews are handled UNRELIABLY there: Toolbox
    /// tracks all "AI" installs under one product code, and only the newest-build
    /// install follows Google's live feed — every other preview copy falls back to
    /// Toolbox's *local channel cache*, which is frequently empty (Toolbox hasn't
    /// refreshed) and, when populated, can lag or surface the wrong build. The
    /// upshot was a flaky/missing "Canary → RC" update (the symptom the user
    /// reported). Our `VendorProbeRecipe` reads Google's release feed directly and
    /// resolves the newest preview build deterministically — see the one-train note
    /// on the Android Studio recipe — so it's the better source for these.
    ///
    /// Restricted to non-stable channels: Stable is shared by retained older majors
    /// (a kept Koala alongside the current release), and Toolbox's
    /// `isNewestOfProduct` logic is what stops those from nagging a cross-major
    /// jump — a guarantee the preview recipe doesn't make.
    public var prefersVendorProbeOverToolbox: Bool {
        isToolboxManaged
            && bundleID == "com.google.android.studio"
            && (releaseChannel == .canary || releaseChannel == .beta)
    }

    private static func safePathComponent(_ raw: String) -> String {
        let safe = raw.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber || c == "." || c == "-" || c == "_" { return c }
            return "_"
        }
        let joined = String(safe)
        return joined.isEmpty || joined.allSatisfy { $0 == "." } ? "app" : joined
    }

    public init(
        name: String,
        bundleID: String?,
        shortVersion: String?,
        buildVersion: String?,
        vendorBuildVersion: String? = nil,
        path: URL,
        isMASApp: Bool,
        isiOSAppOnMac: Bool = false,
        isToolboxManaged: Bool = false,
        isTestFlightApp: Bool = false,
        sparkleFeedURL: URL?,
        electronUpdate: ElectronUpdateConfig? = nil,
        sparkleFeedHeaders: [String: String] = [:],
        sparkleChannelNames: Set<String> = [],
        sparkleEdPublicKey: String? = nil,
        hasSelfUpdater: Bool = false,
        hasSparkleUpdater: Bool = false,
        releaseChannel: ReleaseChannel = .stable,
        channelIsAuthoritative: Bool = false,
        toolboxInstalledBuild: String? = nil,
        appStoreAdamID: Int? = nil
    ) {
        self.name = name
        self.bundleID = bundleID
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.vendorBuildVersion = vendorBuildVersion
        self.path = path
        self.isMASApp = isMASApp
        self.isiOSAppOnMac = isiOSAppOnMac
        self.isToolboxManaged = isToolboxManaged
        self.isTestFlightApp = isTestFlightApp
        self.sparkleFeedURL = sparkleFeedURL
        self.electronUpdate = electronUpdate
        self.sparkleFeedHeaders = sparkleFeedHeaders
        self.sparkleChannelNames = sparkleChannelNames
        self.sparkleEdPublicKey = sparkleEdPublicKey
        self.hasSelfUpdater = hasSelfUpdater
        self.hasSparkleUpdater = hasSparkleUpdater
        self.releaseChannel = releaseChannel
        self.channelIsAuthoritative = channelIsAuthoritative
        self.toolboxInstalledBuild = toolboxInstalledBuild
        self.appStoreAdamID = appStoreAdamID
    }
}
