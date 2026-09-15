import Foundation

/// Update source for Xcode (`com.apple.dt.Xcode`), reading the community-maintained
/// release index at `xcodereleases.com/data.json`.
///
/// Xcode has no feed of its own: stable ships through the Mac App Store (handled by
/// `MacAppStoreSource`, which can actually install it) and every beta/RC lives
/// behind an Apple ID on `developer.apple.com`. So this source is **detection
/// only** — it reports what exists and links to Apple's page and release notes,
/// and never offers a one-click. That isn't a gap to close later: the download
/// endpoint 302s to `developer.apple.com/unauthorized/` without a session cookie
/// (verified 2026-08-14), so installing would mean driving an Apple ID login,
/// which this app does not do.
///
/// ## The version trap
///
/// Xcode reports three different "builds" and only one is the published one:
///
/// | where | Xcode 27 beta 5 |
/// |---|---|
/// | `CFBundleVersion` | `25183.74.15` |
/// | `DTXcodeBuild` | `27A5237k` |
/// | `Contents/version.plist` → `ProductBuildVersion` | `27A5237l` |
///
/// Only the last matches what Apple publishes (and what `xcodebuild -version`
/// prints). Comparing on either of the others means every Xcode reads as
/// perpetually out of date. `AppScanner.productBuildVersion` reads the right one
/// for this bundle id; this source relies on that.
///
/// ## Channels
///
/// A beta and a stable Xcode share `com.apple.dt.Xcode`, the same `CFBundleName`,
/// and often the same marketing version — the installed copy carries no channel
/// flag, and the bundle filename is no help either (a beta renamed `Xcode-27b1.app`
/// says nothing, and one named `Xcode-beta.app` is only a convention). So the
/// channel is recovered from the feed itself: find the entry whose build equals the
/// installed one and read its release kind. That's authoritative and immune to
/// renaming, and when the build isn't in the index at all we return nil rather than
/// guess — an unknown seed compared against the wrong track is exactly how a beta
/// user gets offered a downgrade.
///
/// Offers follow a stability floor (the model `ReleaseChannel` uses elsewhere): an
/// install is offered anything at or above its own stability, never below. A beta
/// user is offered a newer beta, an RC, or the GA; a release user is only ever
/// offered another release. `_versionOrder` — the index's own ranking, which
/// already sorts release above rc above beta within a version — decides "newer",
/// so no string comparison has to understand Apple's build spelling.
///
/// ## The macOS floor
///
/// Every entry states the macOS it needs (`requires`), and the floor MOVES inside
/// one Xcode version: measured 2026-09-15 on the live index, 27.0 RC 1
/// (`27A266a`) requires macOS 26.6 while all six 27.0 betas require 26.4. This
/// source was ignoring the field, so a Mac on 26.0–26.5 was shown 27.0 RC as
/// available — detection-only, so the cost was a row nobody could act on rather
/// than a failed install, but it was still a version that does not exist for that
/// Mac (#640). The floor now both bounds the candidates and rides along on the
/// `RemoteVersion`.
public struct XcodeReleasesSource: UpdateSource {

    static let sourceName = "Xcode Releases"
    public let name = Self.sourceName

    public static let bundleID = "com.apple.dt.Xcode"

    static let feedURL = URL(string: "https://xcodereleases.com/data.json")!

    /// Where a user actually gets each track. Prereleases live on Apple's downloads
    /// page (login required, hence a page and not a file); the released Xcode is a
    /// Mac App Store product.
    static let downloadsPage = URL(string: "https://developer.apple.com/download/all/")!
    static let appStorePage = URL(string: "https://apps.apple.com/app/xcode/id497799835")!

    private let session: URLSession

    public init(session: URLSession = .updates) {
        self.session = session
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard app.bundleID == Self.bundleID else { return nil }
        // `AppScanner` puts `ProductBuildVersion` here for Xcode — see the table above.
        guard let installedBuild = app.buildVersion, !installedBuild.isEmpty else { return nil }

        return Self.remote(
            forBuild: installedBuild, in: try await fetch(), osVersion: HostOS.numericVersion())
    }

    /// What `latestVersion` reports for an installed build, given the index. Pure,
    /// so the engine's verdict on it is testable without network.
    ///
    /// `osVersion` has no default on purpose: the index states a macOS floor per
    /// release (`requires`), so this function's answer depends on the host, and a
    /// default would let a test silently measure whichever Mac it runs on.
    static func remote(
        forBuild installedBuild: String, in releases: [Release], osVersion: String
    ) -> RemoteVersion? {
        guard let (installed, offer) = Self.offer(
            forBuild: installedBuild, in: releases, osVersion: osVersion)
        else { return nil }

        return RemoteVersion(
            // Build-to-build is the real comparison (`shortVersion` here is a label
            // for the row: "27.0 beta 6", not something to compare against the
            // installed "27.0" — `UpdateChecker.evaluate` prefers the build whenever
            // both sides have one, which for Xcode is always).
            shortVersion: offer.displayVersion,
            version: offer.build,
            // Detection only: no artifact, deliberately. See the note above.
            downloadURL: nil,
            pageURL: offer.stability >= .release ? Self.appStorePage : Self.downloadsPage,
            // Name the installed side too: on disk it is only "27.0", and which beta
            // that is exists nowhere in the bundle — so "27.0 beta 1 → 27.0 beta 5"
            // instead of an opaque build number on the left.
            installedDisplayVersion: installed.displayVersion,
            // The index's own `requires` — the macOS this build needs. Measured
            // 2026-09-15 on the live `data.json`: all 451 entries carry one, and
            // the 27.0 ladder is not flat — RC 1 (`27A266a`) requires "26.6"
            // while every 27.0 beta requires "26.4", which is why a Mac on
            // 26.0–26.5 was shown the RC (#640).
            //
            // The refusal itself already happened: `offer` above bounded its
            // candidates by this value, so the build named here is one this Mac
            // can run. Carried anyway because it is a fact about the release —
            // the row's "requires macOS N" line (#634 part 3) reads it, and it
            // is what install-time gate 6 will be checked against.
            minimumSystemVersion: offer.requires,
            sourceName: Self.sourceName,
            requiresManualInstaller: true,
            changelogURL: offer.notesURL,
            // Deliberately no `publishedAt`: the index dates releases to the DAY,
            // and the release timeline only plots times it can trust to the minute
            // (see `ReleaseTimelineStore`). A midnight stamp would be a fabrication.
            publishedAt: nil,
            // Apple's build ids have no order a string comparison can read: a beta's
            // is `27A5237l`, the RC after it `27A266a`, and 5237 > 266 made every
            // beta read as AHEAD of its own RC — "up to date", with the RC drawn as a
            // downgrade. The index's `_versionOrder` is the order, so it decides
            // "newer" in the engine exactly as it decided the offer above.
            buildLineage: Self.lineage(of: releases)
        )
    }

    /// Every build in the index, newest first by `_versionOrder`. A build shared
    /// by several entries (an RC and its release) sits at its highest rank.
    static func lineage(of releases: [Release]) -> BuildLineage {
        BuildLineage(newestFirst: releases.sorted { $0.order > $1.order }.map(\.build))
    }

    /// The installed release and the one to offer for it, or nil when the build
    /// isn't in the index at all (an unknown seed: say nothing rather than compare
    /// it against a track it may not belong to).
    ///
    /// The two are the same release when nothing newer qualifies, so the engine's
    /// own comparison concludes "up to date" — this never asserts a verdict itself.
    /// The installed one is returned alongside because it carries the only place its
    /// track is written down ("27.0 beta 1").
    ///
    /// Candidates are also bounded by the host: the index states each release's
    /// macOS floor and they differ WITHIN one version — measured 2026-09-15,
    /// 27.0 RC 1 requires macOS 26.6 while 27.0 beta 6 requires 26.4 — so a Mac
    /// on 26.4 is offered the newest beta rather than an RC it cannot run. This is
    /// the shape `SparkleAppcastSource.usableItems` has always had (filter the
    /// candidate list, then take its head), with the same predicate;
    /// `UpdateChecker.evaluate`'s floor check is the backstop for sources that do
    /// not choose among candidates, not a substitute for choosing well here.
    static func offer(
        forBuild installedBuild: String, in releases: [Release], osVersion: String
    ) -> (installed: Release, offer: Release)? {
        // Several entries can share a build (26.6 RC 2 and 26.6 release are the same
        // binary, `17F113`). Identical bits, so take the most stable reading of it:
        // the copy on disk is as good as the release.
        guard let installed = releases
            .filter({ $0.build == installedBuild })
            .max(by: { $0.order < $1.order })
        else { return nil }

        // Stability floor: offer anything at or above the installed stability, never
        // below. A beta may be superseded by a newer beta, an RC, or the GA; a
        // release is only ever superseded by another release.
        // ...and by what this Mac can run. `installed` is deliberately NOT
        // filtered: it is on disk, so whatever it declares, it runs here.
        let candidates = releases.filter {
            $0.stability >= installed.stability
                && SignatureVerifier.canRun(minimumSystemVersion: $0.requires, on: osVersion)
        }
        guard let latest = candidates.max(by: { $0.order < $1.order }) else {
            return (installed, installed)
        }
        return (installed, latest.order > installed.order ? latest : installed)
    }

    // MARK: - Feed

    private func fetch() async throws -> [Release] {
        var request = URLRequest(url: Self.feedURL)
        // Same reason every other version feed sets this: a long max-age would
        // otherwise let a stale copy hide a release for days.
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        let (data, response) = try await session.versionFeedData(
            for: request, label: "XcodeReleases")
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return Self.parse(data)
    }

    /// Decode the index. Pure, so the shape rules below are testable without network.
    static func parse(_ data: Data) -> [Release] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(Release.init(json:))
    }

    // MARK: - Model

    /// How finished a build is. Ordered, because the offer rule is "at or above".
    enum Stability: Int, Comparable, Sendable {
        case developerPreview = 0
        case beta = 1
        case releaseCandidate = 2
        case release = 3

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    struct Release: Sendable {
        let build: String
        let number: String
        let stability: Stability
        /// The index's own global ordering (`27000000005` for 27.0 beta 5), which
        /// already ranks release > rc > beta inside a version.
        let order: Int
        let notesURL: URL?
        /// The index's `requires`: the macOS this build needs ("26.6"). Optional
        /// because nothing in the feed's shape guarantees it — every one of the
        /// 451 entries carried one when measured 2026-09-15, but an entry that
        /// stops doing so must fail open (no floor = no refusal), not vanish.
        let requires: String?
        /// What the row shows: "27.0 beta 5 (27A5237l)", "26.6 RC 2 (17F113)", "26.6
    /// (17F113)". The build rides along on BOTH sides of a "from → to" line: it is
    /// the only exact identity Xcode has, and betas of the same number get respun
    /// (27A5194o vs 27A5194q are different bits under one "beta 1").
        let displayVersion: String

        init?(json: [String: Any]) {
            // "Xcode", "Xcode (Apple Silicon)" and "Xcode (Universal)" are the same
            // releases packaged differently; "Xcode Tools" is a different product.
            guard let name = json["name"] as? String, name.hasPrefix("Xcode"),
                  !name.hasPrefix("Xcode Tools"),
                  let version = json["version"] as? [String: Any],
                  let build = version["build"] as? String,
                  let number = version["number"] as? String,
                  let order = json["_versionOrder"] as? Int,
                  let release = version["release"] as? [String: Any]
            else { return nil }

            let (stability, suffix): (Stability, String?) = {
                if release["release"] as? Bool == true { return (.release, nil) }
                if release["gm"] as? Bool == true { return (.release, nil) }
                if let n = release["rc"] as? Int { return (.releaseCandidate, "RC \(n)") }
                if let n = release["gmSeed"] as? Int { return (.releaseCandidate, "GM seed \(n)") }
                if let n = release["beta"] as? Int { return (.beta, "beta \(n)") }
                if let n = release["dp"] as? Int { return (.developerPreview, "DP \(n)") }
                return (.beta, "beta")
            }()

            self.build = build
            self.number = number
            self.stability = stability
            self.order = order
            self.requires = json["requires"] as? String
            let label = suffix.map { "\(number) \($0)" } ?? number
            self.displayVersion = "\(label) (\(build))"
            self.notesURL = ((json["links"] as? [String: Any])?["notes"] as? [String: Any])
                .flatMap { $0["url"] as? String }
                .flatMap(URL.init(string:))
        }
    }
}
