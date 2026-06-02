import Foundation

/// Mac App Store availability for an app, used to explain region locking.
public struct AppStoreAvailability: Sendable, Hashable {
    /// The App Store numeric track id, used to build a direct product link.
    public let trackID: Int
    /// Region whose storefront actually lists the app, e.g. "cn".
    public let availableRegion: String
    /// Region of the signed-in App Store account, e.g. "us" (nil if unknown).
    public let homeRegion: String?

    /// For an iPhone/iPad app run on Apple Silicon: whether the *latest* App Store
    /// build still runs on Macs (Apple's `isIOSBinaryMacOSCompatible` flag).
    /// Vendors can drop Mac support in a newer release, so the newest version may
    /// be real but uninstallable here — the App Store shows "Not compatible with
    /// this device". nil = native Mac app / not checked (assume compatible).
    public let latestMacCompatible: Bool?

    public init(trackID: Int, availableRegion: String, homeRegion: String?, latestMacCompatible: Bool? = nil) {
        self.trackID = trackID
        self.availableRegion = availableRegion
        self.homeRegion = homeRegion
        self.latestMacCompatible = latestMacCompatible
    }

    /// True when we know the newest build no longer supports this Mac, so even
    /// though a newer version exists the user can't install it here.
    public var isLatestMacIncompatible: Bool { latestMacCompatible == false }

    /// True when the app isn't listed in the signed-in account's storefront, so
    /// the App Store will refuse to open/update it ("App Not Available").
    public var isRegionMismatch: Bool {
        guard let homeRegion else { return false }
        return availableRegion.lowercased() != homeRegion.lowercased()
    }

    /// Deep link straight to the product page in the App Store app. Lands on the
    /// page directly when the account's region matches; otherwise the store
    /// still shows "App Not Available".
    public var deepLink: URL? {
        URL(string: "macappstore://apps.apple.com/app/id\(trackID)")
    }
}

/// What a single update source reports as the newest available release.
public struct RemoteVersion: Sendable, Hashable {
    /// Marketing version, e.g. "1.96.0" (`sparkle:shortVersionString`).
    public let shortVersion: String?
    /// Build version, e.g. "1.96.0" or "45830" (`sparkle:version`). This is
    /// Sparkle's canonical comparison key.
    public let version: String?
    /// Where to download the new build (Sparkle `enclosure url`).
    public let downloadURL: URL?
    /// EdDSA signature of the enclosure, used to verify the download later.
    public let edSignature: String?
    /// Minimum macOS version the release requires, if declared.
    public let minimumSystemVersion: String?
    /// Human-readable name of the source that produced this ("Sparkle" etc.).
    public let sourceName: String

    /// Source-specific identifier needed to act on this update — currently the
    /// Homebrew cask token, used by `brew install --cask`.
    public let sourceIdentifier: String?

    /// Mac App Store availability/region info, when this came from the App Store.
    public let appStore: AppStoreAvailability?

    /// True when installing means running a downloaded installer package (a
    /// `pkg` cask) rather than an in-place swap — needs admin via the system
    /// installer, so we download the official package and open it.
    public let requiresManualInstaller: Bool

    /// For a `Vendor` update we can install in place: the archive format of
    /// `downloadURL`, so `VendorInstaller` unpacks it correctly. Nil for sources
    /// that don't drive a vendor in-place install.
    public let vendorInstallerKind: VendorInstallerKind?

    /// Optional expected SHA-512 (base64) of the vendor download, verified before
    /// unpacking. Nil when the feed doesn't publish one.
    public let expectedSHA512: String?

    /// Extra HTTP headers to send when downloading `downloadURL`. Empty for most
    /// sources; set by vendor recipes whose CDN sits behind a WAF that only
    /// serves the binary to browser-like requests (e.g. Oray's `dw.oray.com`
    /// needs a `Referer`, else it returns an anti-bot challenge page).
    public let downloadHeaders: [String: String]

    /// Inline release notes when the source ships them as text/HTML — Sparkle's
    /// `<description>`, a GitHub release `body`. Rendered directly in the detail
    /// window. Nil for sources that publish no notes (most vendor probes).
    public let releaseNotesHTML: String?

    /// Structured changelog parsed from a GitHub release body. When present,
    /// rendered natively via `ChangelogEntryView` instead of the flat markdown blob.
    public let structuredChangelog: Changelog?

    /// A web page with the app's changelog/release notes, for sources that don't
    /// give us inline text (vendor sites, GitHub release page). Embedded in a web
    /// view as the fallback when `releaseNotesHTML` is nil. May be set alongside
    /// `releaseNotesHTML` as an "see full changelog" link.
    public let changelogURL: URL?

    public init(
        shortVersion: String?,
        version: String?,
        downloadURL: URL?,
        edSignature: String? = nil,
        minimumSystemVersion: String? = nil,
        sourceName: String,
        sourceIdentifier: String? = nil,
        appStore: AppStoreAvailability? = nil,
        requiresManualInstaller: Bool = false,
        vendorInstallerKind: VendorInstallerKind? = nil,
        expectedSHA512: String? = nil,
        downloadHeaders: [String: String] = [:],
        releaseNotesHTML: String? = nil,
        structuredChangelog: Changelog? = nil,
        changelogURL: URL? = nil
    ) {
        self.shortVersion = shortVersion
        self.version = version
        self.downloadURL = downloadURL
        self.edSignature = edSignature
        self.minimumSystemVersion = minimumSystemVersion
        self.sourceName = sourceName
        self.sourceIdentifier = sourceIdentifier
        self.appStore = appStore
        self.requiresManualInstaller = requiresManualInstaller
        self.vendorInstallerKind = vendorInstallerKind
        self.expectedSHA512 = expectedSHA512
        self.downloadHeaders = downloadHeaders
        self.releaseNotesHTML = releaseNotesHTML
        self.structuredChangelog = structuredChangelog
        self.changelogURL = changelogURL
    }

    /// Best version string to show the user.
    public var displayVersion: String? { shortVersion ?? version }
}

public enum UpdateStatus: Sendable, Equatable {
    /// Installed version is current.
    case upToDate
    /// A newer version exists. `latest` is the display string.
    case updateAvailable(latest: String)
    /// No source could answer for this app (no feed, not on MAS, no cask).
    case unknown
    /// The app came from the Mac App Store, which manages its updates. We can't
    /// read a trustworthy Mac version (the public lookup reports the iOS track
    /// for these), so rather than show it as "unknown" we mark it as handled by
    /// the App Store — informational, not actionable here.
    case appStoreManaged
    /// JetBrains Toolbox installed and updates this app. Probing a vendor
    /// endpoint would risk a cross-channel install, so we defer to Toolbox and
    /// label it as managed — informational, not actionable here.
    case toolboxManaged
    /// A source was tried but failed (network, parse, etc.).
    case error(String)
}

/// The outcome of checking one installed app for updates.
public struct UpdateResult: Sendable, Identifiable {
    public let app: InstalledApp
    public let remote: RemoteVersion?
    public let status: UpdateStatus

    public var id: String { app.id }

    public init(app: InstalledApp, remote: RemoteVersion?, status: UpdateStatus) {
        self.app = app
        self.remote = remote
        self.status = status
    }

    public var hasUpdate: Bool {
        if case .updateAvailable = status { return true }
        return false
    }

    /// True when the available update is a major version bump (e.g. 6.x → 7.x).
    /// Used to warn that a commercial app may require a new license — the same
    /// heuristic MacUpdater surfaces.
    public var isMajorUpgrade: Bool {
        guard case .updateAvailable = status,
              let from = app.shortVersion,
              let to = remote?.displayVersion else { return false }
        return VersionComparator.isMajorUpgrade(from: from, to: to)
    }
}
