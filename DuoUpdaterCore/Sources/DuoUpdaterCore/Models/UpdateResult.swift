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

/// One past release a source told us about in passing — a version and the date
/// it was published. Sources that hand back a multi-entry feed (a Sparkle appcast,
/// a GitHub releases list) carry these so the release timeline can backfill an
/// app's history in one shot, instead of only ever learning the latest.
public struct ReleaseHistoryEntry: Sendable, Hashable {
    public let version: String
    public let publishedAt: Date
    public init(version: String, publishedAt: Date) {
        self.version = version
        self.publishedAt = publishedAt
    }
}

/// A binary patch that upgrades ONE specific installed build to this release —
/// Sparkle's `<sparkle:deltas><enclosure sparkle:deltaFrom="…">`.
///
/// Not an installer: applying it needs the exact bundle it was cut against, so a
/// patch is only usable when `fromBuild` equals what is on disk right now. The
/// vendor publishes a handful per release (ChatGPT 5, Docker 13, Keka 8), so the
/// match either lands or it doesn't — and when it doesn't, the full archive is
/// the answer, not a smaller patch.
///
/// Worth having because the ratio is not marginal: measured on the real feeds,
/// Keka's 1.6.5→1.6.7 patch is 519 KB against a 32.9 MB archive, and ChatGPT's
/// consecutive-build patch is 713 KB against 605 MB.
public struct DeltaPatch: Sendable, Hashable {
    /// `sparkle:deltaFrom` — the build this patch upgrades FROM. Compared against
    /// the installed `CFBundleVersion`, which is what Sparkle cut the patch
    /// against; a marketing-version match would be wrong on any app whose two
    /// numbers differ.
    public let fromBuild: String
    public let url: URL
    /// `length` — patch size in bytes, when declared.
    public let size: Int64?
    /// `sparkle:edSignature` over the patch file itself. A signed feed signs each
    /// delta separately from the archive, so this is the one to verify when the
    /// patch is what we downloaded.
    public let edSignature: String?

    public init(fromBuild: String, url: URL, size: Int64? = nil, edSignature: String? = nil) {
        self.fromBuild = fromBuild
        self.url = url
        self.size = size
        self.edSignature = edSignature
    }
}

/// What a single update source reports as the newest available release.
public struct RemoteVersion: Sendable, Hashable {
    /// Marketing version, e.g. "1.96.0" (`sparkle:shortVersionString`).
    public let shortVersion: String?
    /// Build version, e.g. "1.96.0" or "45830" (`sparkle:version`). This is
    /// Sparkle's canonical comparison key.
    public let version: String?
    /// Which of the installed bundle's build identifiers ``version`` is expressed
    /// in. `.bundle` — `CFBundleVersion` — for every source but the Mozilla
    /// pre-release probes, which report the `BuildID` Mozilla's update service and
    /// `application.ini` share. Stated rather than inferred because the two
    /// namespaces are both bare numbers: compared against each other they do not
    /// error, they answer the same thing forever.
    public let buildNamespace: InstalledApp.BuildNamespace
    /// Where to download the new build (Sparkle `enclosure url`). This is the
    /// ARTIFACT — a .dmg/.pkg/.zip the installer fetches. Never surface it as a
    /// link for the user to click: opening it in a browser starts a download
    /// instead of showing a page. Use ``pageURL`` for that.
    public let downloadURL: URL?
    /// A human-facing web page for this app: the vendor's official download page,
    /// a GitHub release page, an App Store product page. This — not
    /// ``downloadURL`` — is what an "Open page" affordance opens. Nil for sources
    /// that only ever resolve an artifact (a bare Sparkle appcast has no page), in
    /// which case the UI shows no such link rather than handing the user a file.
    public let pageURL: URL?
    /// What the INSTALLED build should be called, when the source is the only thing
    /// that can name it. Xcode is the case that needs it: on disk a beta says only
    /// "27.0" and its build (`27A5194q`) is opaque — that it is *beta 1* is a fact
    /// that lives in the release index, not in the bundle. Nil for every source
    /// whose apps can name themselves, and the UI falls back to the installed
    /// marketing version as before.
    public let installedDisplayVersion: String?
    /// Declared size of the download in bytes (Sparkle `<enclosure length>`,
    /// GitHub asset `size`), when the source publishes one — lets "Update All"
    /// order the batch smallest-first instead of alphabetically. Nil when the
    /// source doesn't know.
    public let downloadSize: Int64?
    /// EdDSA signature of the enclosure, used to verify the download later.
    public let edSignature: String?
    /// Minimum macOS version the release requires, if declared.
    public let minimumSystemVersion: String?
    /// Human-readable name of the source that produced this ("Sparkle" etc.).
    public let sourceName: String

    /// Sparkle `minimumAutoupdateVersion`: the vendor-declared build version
    /// below which this release must not silently auto-install. When set, it is
    /// the authoritative "is this a notable/paid-boundary upgrade?" signal — we
    /// trust it over the version-number heuristic. Expressed in build-version
    /// (`sparkle:version`) terms. Nil for non-Sparkle sources and most feeds.
    public let minimumAutoupdateVersion: String?

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

    /// Path inside the unpacked download of a second archive holding the real
    /// app, for vendors who ship an installer stub. See
    /// `VendorInstallSpec.nestedArchivePath`. Nil for every ordinary download.
    public let nestedArchivePath: String?

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

    /// When the vendor *published* this release, parsed from the feed's own
    /// timestamp (Sparkle `<pubDate>`, GitHub/Alcove `published_at`). This is the
    /// authoritative release moment — to the minute — that the release timeline
    /// records. Nil for sources that publish no trustworthy date (most vendor
    /// probes, MAS, Homebrew); those are never plotted as "when it was released",
    /// only ever as "when we noticed". See `ReleaseTimelineStore`.
    public let publishedAt: Date?

    /// Past releases the source surfaced alongside the latest — every dated entry
    /// in a Sparkle appcast / GitHub releases list, so the timeline can backfill
    /// an app's whole visible history at once (the latest is included too; the
    /// store dedupes by version). Empty for sources that only resolve one release.
    public let releaseHistory: [ReleaseHistoryEntry]

    /// Binary patches this release publishes, one per build it can upgrade from.
    /// Empty for every source that doesn't publish them — which is most: of the
    /// eleven Sparkle feeds readable on this machine only Keka's carried patches
    /// usable by the installed build. See `DeltaPatch`.
    public let deltas: [DeltaPatch]

    public init(
        shortVersion: String?,
        version: String?,
        buildNamespace: InstalledApp.BuildNamespace = .bundle,
        downloadURL: URL?,
        pageURL: URL? = nil,
        installedDisplayVersion: String? = nil,
        downloadSize: Int64? = nil,
        edSignature: String? = nil,
        minimumSystemVersion: String? = nil,
        sourceName: String,
        minimumAutoupdateVersion: String? = nil,
        sourceIdentifier: String? = nil,
        appStore: AppStoreAvailability? = nil,
        requiresManualInstaller: Bool = false,
        vendorInstallerKind: VendorInstallerKind? = nil,
        expectedSHA512: String? = nil,
        nestedArchivePath: String? = nil,
        downloadHeaders: [String: String] = [:],
        releaseNotesHTML: String? = nil,
        structuredChangelog: Changelog? = nil,
        changelogURL: URL? = nil,
        publishedAt: Date? = nil,
        releaseHistory: [ReleaseHistoryEntry] = [],
        deltas: [DeltaPatch] = []
    ) {
        self.shortVersion = shortVersion
        self.version = version
        self.buildNamespace = buildNamespace
        self.downloadURL = downloadURL
        self.pageURL = pageURL
        self.installedDisplayVersion = installedDisplayVersion
        self.downloadSize = downloadSize
        self.edSignature = edSignature
        self.minimumSystemVersion = minimumSystemVersion
        self.sourceName = sourceName
        self.minimumAutoupdateVersion = minimumAutoupdateVersion
        self.sourceIdentifier = sourceIdentifier
        self.appStore = appStore
        self.requiresManualInstaller = requiresManualInstaller
        self.vendorInstallerKind = vendorInstallerKind
        self.expectedSHA512 = expectedSHA512
        self.nestedArchivePath = nestedArchivePath
        self.downloadHeaders = downloadHeaders
        self.releaseNotesHTML = releaseNotesHTML
        self.structuredChangelog = structuredChangelog
        self.changelogURL = changelogURL
        self.publishedAt = publishedAt
        self.releaseHistory = releaseHistory
        self.deltas = deltas
    }

    /// Best version string to show the user.
    ///
    /// Marketing-first, which is right for DISPLAY and wrong for comparison — for
    /// a vendor that freezes its marketing string this is the same value release
    /// after release. Anything deciding "is this newer" wants ``versionSide``.
    public var displayVersion: String? { shortVersion ?? version }

    /// Both halves of what the source reported, for comparison. `version` is the
    /// build (Sparkle's `sparkle:version`, its canonical comparison key); some
    /// sources report the marketing string there too, which is why the pair is
    /// passed on rather than collapsed here.
    public var versionSide: VersionSide {
        VersionSide(marketing: shortVersion, build: version)
    }
}

extension UpdateResult {
    /// What to call the INSTALLED build in any UI — the menu bar, the workbench row,
    /// `duo check`.
    ///
    /// Normally the app's own marketing version. It defers to
    /// ``RemoteVersion/installedDisplayVersion`` when a source can name the installed
    /// build better than the bundle can: Xcode on disk says only "27.0", and which
    /// beta that is exists nowhere in it. Lives here rather than in the app so the
    /// CLI and the menu bar cannot describe the same install differently.
    public var installedDisplay: String? {
        if let named = remote?.installedDisplayVersion { return named }
        // When the source's own label IS a build, the installed side has to be
        // named out of the SAME namespace, or the row draws its arrow between two
        // different version systems and the left half matches nothing the user can
        // see anywhere else.
        //
        // CapCut's beta track is the case that exposed it. That bundle carries
        // `CFBundleShortVersionString` 9.3.4545 and `CFBundleVersion`
        // 9.4.0-beta5 — the vendor versions the beta line in the BUILD field, which
        // is why its recipe is `versionIsBuild` — so the row read
        // "9.3.4545 → 9.4.0-beta6" while the app itself, Finder, and every other
        // updater called the installed copy 9.4.0-beta5. Nothing was miscompared
        // (`evaluate` was on builds throughout, 9.4.0-beta5 → 9.4.0-beta6); only
        // the label was, which is the kind of wrong that gets reported as "it says
        // I have a version I don't have".
        //
        // Keyed on the REMOTE's own shape rather than on `recipe.versionIsBuild`,
        // so it cannot drift from what the other half of the row prints:
        // `RemoteVersion.displayVersion` is `shortVersion ?? version`, so
        // `shortVersion == nil` is exactly "the string beside the arrow is a
        // build". A `versionIsBuild` recipe that supplies a `displayVersionPattern`
        // puts a marketing string in `shortVersion` on purpose (Android Studio's
        // "2025.2.3 → 2026.1.2 RC 1") and is deliberately untouched here.
        if let remote, remote.shortVersion == nil, remote.version != nil,
           let build = app.buildVersion(in: remote.buildNamespace) {
            return build
        }
        return app.shortVersion
    }

    /// Drop a leading product-code run like "IU-"/"AI-" from a build number; plain
    /// builds ("11270", "262.7132.23", "1.2.3-beta") pass through untouched — only a
    /// pure-letter segment before the first hyphen is treated as a prefix. JetBrains
    /// stamps CFBundleVersion as "IU-262.6653.22" while the Toolbox/API build id has
    /// no prefix, so this aligns the two sides into one namespace.
    public static func strippingBuildPrefix(_ build: String) -> String {
        guard let dash = build.firstIndex(of: "-"), dash != build.startIndex,
              build[..<dash].allSatisfy(\.isLetter) else { return build }
        return String(build[build.index(after: dash)...])
    }

    /// When an update keeps the same marketing version but bumps the build — Surge
    /// "6.6.0 (11270)" over "6.6.0 (11260)", or a JetBrains EAP "2026.2 → 2026.2"
    /// that's really 262.6653.22 → 262.7132.23 — return the cleaned (installed,
    /// latest) build pair so the UI can surface what actually changed. nil when the
    /// marketing version itself moved (the normal case) or there's no build to show.
    public func buildBump(latest: String) -> (installed: String, remote: String)? {
        // The installed build has to be the one the source is speaking in. A
        // Firefox nightly is the case that makes this visible: `latest` and
        // `app.shortVersion` are both "157.0a1" so this line always renders, and
        // its remote half is `application.ini`'s BuildID — beside a
        // `CFBundleVersion` it would read "15726.8.29 → 20260829211045", two
        // numbers with nothing to do with each other.
        guard latest == app.shortVersion,
              let remote, let remoteBuild = remote.version,
              let installedBuild = app.buildVersion(in: remote.buildNamespace)
        else { return nil }
        let installed = UpdateResult.strippingBuildPrefix(installedBuild)
        let remoteClean = UpdateResult.strippingBuildPrefix(remoteBuild)
        guard installed != remoteClean else { return nil }
        return (installed, remoteClean)
    }

    /// One end of a **relaunch** line — the running process on the left, the bundle
    /// already on disk on the right — before it is decided whether its build number
    /// is worth the width.
    ///
    /// The two ends are formatted together (see ``UpdateResult/relaunchLine(from:to:)``)
    /// rather than each on its own, which is the whole point: a side cannot tell on
    /// its own whether its build is the interesting part.
    /// Promoted to a top-level type (`Version/VersionSide.swift`) so the decision
    /// sites outside this file can share it. Kept as a nested name because that is
    /// what the display code and its tests already spell.
    public typealias VersionSide = DuoUpdaterCore.VersionSide

    /// The on-disk side of a relaunch line: the version a relaunch will land.
    public var relaunchTargetSide: VersionSide {
        VersionSide(marketing: app.shortVersion,
                    build: app.buildVersion.map(Self.strippingBuildPrefix))
    }

    /// Format both ends of a relaunch line, keeping the build numbers only when they
    /// are what tells the two versions apart.
    ///
    /// This is ``buildBump(latest:)``'s rule, which the *update* line has always
    /// applied, finally reaching the relaunch line. Each side used to format itself,
    /// so both kept their build whatever the other looked like, and Chrome — whose
    /// marketing version already ends in its build — rendered as
    /// `151.0.7922.174 (7922.17… → 152.0.7977.65 (7977.65)`: the side the user is
    /// leaving got truncated in order to repeat digits the marketing version had
    /// already spelled out.
    ///
    /// Kept when the marketing versions match, because then the build is the only
    /// thing that moved: Surge shipped four separate releases as "6.9.0", and
    /// "6.9.0 → 6.9.0" says nothing at all.
    ///
    /// **Both** marketing versions have to be present before a build is dropped.
    /// `lsappinfo` exposes only the running *build*, and when nothing recovered a
    /// marketing version to pair with it that side is a bare number — dropping the
    /// target's build there would leave "3965 → 1.7.3", two values from different
    /// namespaces with no way to read one against the other.
    public static func relaunchLine(
        from: VersionSide, to: VersionSide
    ) -> (from: String, to: String) {
        let bothNamed = from.marketing != nil && to.marketing != nil
        let withBuild = !(bothNamed && from.marketing != to.marketing)
        return (from.text(withBuild: withBuild), to.text(withBuild: withBuild))
    }

    /// Both ends of the *staged* relaunch line: the bundle installed now on the
    /// left, the build a relaunch would install on the right.
    ///
    /// The sibling of `relaunchLine(from:to:)`'s other caller, and it exists
    /// because that rule reached only one of the two relaunch lines. The staged
    /// line formatted each side as a bare `CFBundleShortVersionString`, so an app
    /// whose marketing version does not move rendered as "1.0 → 1.0" — a line
    /// that names no difference at all. Amp is the extreme case: it stayed on
    /// "1.0" through ten builds in the six hours after it shipped, and every one
    /// of them offered a relaunch that said nothing.
    ///
    /// Both sides come from a bundle's own `Info.plist` — `staged.buildVersion`
    /// is read from the staged bundle by `SelfUpdaterStaging`, which already
    /// compares it against the installed build to decide the row is offerable at
    /// all — so the number was on hand the whole time; only this line did not ask
    /// for it. `strippingBuildPrefix` on both, matching `relaunchTargetSide`, so a
    /// vendor that prefixes its build (`v1234`) is compared and shown in one
    /// namespace.
    public func stagedRelaunchLine(_ staged: StagedSelfUpdate) -> (from: String, to: String) {
        Self.relaunchLine(
            from: VersionSide(marketing: app.shortVersion,
                              build: app.buildVersion.map(Self.strippingBuildPrefix)),
            to: VersionSide(marketing: staged.version,
                            build: staged.buildVersion.map(Self.strippingBuildPrefix)))
    }

}

public enum UpdateStatus: Sendable, Equatable {
    /// Installed version is current.
    case upToDate
    /// A newer version exists. `latest` is the display string.
    case updateAvailable(latest: String)
    /// No source *covers* this app — no feed, not on MAS, no cask, no recipe.
    /// Nothing was tried and failed here: a source that applied and then couldn't
    /// answer is `.error(_)`, which is retryable and says so. Keeping the two
    /// apart is the whole point of the distinction — the row renders this one as
    /// a dead "—", and a transient timeout wearing that badge reads as a
    /// permanent verdict the user has no way to act on.
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
    /// TestFlight installed this beta and owns its updates. We read TestFlight's
    /// local cache for the latest build but never install it ourselves — the
    /// action is "open TestFlight". Used when no newer build is known (or the
    /// cache is empty); a known newer build surfaces as `.updateAvailable`.
    case testFlightManaged
    /// A source was tried but failed (network, parse, etc.).
    case error(String)

    /// True when an `.error` looks like GitHub's unauthenticated 60/hour rate
    /// limit — the common transient when checking GitHub-sourced apps without a
    /// token. Drives the inline "Rate-limited" row badge and the aggregate
    /// "add a token" banner. Matches the message produced by
    /// `GitHubReleasesSource.GitHubError` (kept in sync with that string).
    public var isRateLimitError: Bool {
        if case .error(let message) = self {
            return message.localizedCaseInsensitiveContains("rate limit")
        }
        return false
    }
}

/// The outcome of checking one installed app for updates.
public struct UpdateResult: Sendable, Identifiable, Equatable {
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

    /// Source channels whose updates carry no "expired paid license" risk, so a
    /// major-number bump arriving through them is just a release, not a boundary:
    ///  - "Vendor": our hand-curated probe registry — vetted free GA builds we
    ///    already one-click install (Postman, Chrome, VLC, …).
    ///  - "GitHub": open-source release feeds.
    ///  - "App Store": the store enforces entitlements itself; we never warn.
    /// Deliberately excludes "Homebrew" (some casks wrap paid apps) and a Sparkle
    /// feed that merely set no `minimumAutoupdateVersion` (a paid app may simply
    /// omit it), both of which keep the warning — the conservative direction.
    ///
    /// Also deliberately excludes "Electron" (#192): an electron-builder manifest
    /// can belong to a commercial app we've done no license review of, unlike
    /// Vendor (our own hand-curated, vetted registry) or GitHub (open-source
    /// feeds) — so a major-version jump arriving through this source still
    /// raises the "may need a new license" warning. Same conservative treatment
    /// as Homebrew, not an oversight. `UpdatePolicy.canAutoInstall`'s
    /// `"Vendor", "GitHub", "Electron"` case (Engine/UpdatePolicy.swift) points
    /// back here rather than repeating this.
    private static let licenseNeutralSources: Set<String> = ["Vendor", "GitHub", "App Store"]

    /// True when the available update is a notable/major upgrade — the signal we
    /// surface to warn that a commercial app may require a new license (the same
    /// heuristic MacUpdater surfaces).
    ///
    /// Three tiers, authoritative-first:
    ///  1. If the feed declares `minimumAutoupdateVersion`, trust it in BOTH
    ///     directions: the vendor has explicitly drawn the line, so a fast-cadence
    ///     app that bumps its major number but sets no floor (Postman-style) is
    ///     correctly NOT flagged, and one whose floor we sit below IS — regardless
    ///     of how the marketing numbers move. Compared in build-version terms,
    ///     which is what Sparkle's own `majorUpgrade` uses.
    ///  2. Otherwise fall back to the marketing-major-bump guess, but suppress the
    ///     two shapes where that guess is reliably wrong: updates from a
    ///     license-neutral source, and CalVer (year-led) version schemes.
    ///  3. We do NOT suppress on a high major number alone — Parallels (v26) and
    ///     Office 2024 are high-major yet paid per major, so magnitude is unsafe.
    public var isMajorUpgrade: Bool {
        guard case .updateAvailable = status else { return false }

        if let floor = remote?.minimumAutoupdateVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines), !floor.isEmpty,
           let installed = app.buildVersion ?? app.shortVersion {
            return VersionComparator.compare(installed, floor) == .orderedAscending
        }

        guard let from = app.shortVersion, let to = remote?.displayVersion,
              VersionComparator.isMajorUpgrade(from: from, to: to) else { return false }

        if let source = remote?.sourceName, Self.licenseNeutralSources.contains(source) {
            return false
        }
        if VersionComparator.isCalendarVersion(to) { return false }

        return true
    }
}
