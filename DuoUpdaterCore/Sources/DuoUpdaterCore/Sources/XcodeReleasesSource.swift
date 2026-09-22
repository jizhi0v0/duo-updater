import Foundation

/// Update source for Xcode (`com.apple.dt.Xcode`), reading the community-maintained
/// release index at `xcodereleases.com/data.json`.
///
/// Xcode has no feed of its own: stable ships through the Mac App Store (handled by
/// `MacAppStoreSource`, which can actually install it — and a store copy never
/// reaches this source, see `UpdateSource.answersAppStoreCopies`) while every
/// beta and RC, and a developer-site copy of each GA, lives behind an Apple ID on
/// `developer.apple.com`.
///
/// ## What it offers to install
///
/// Each index entry names its `.xip` on Apple's CDN (`links.download.url`). The CDN
/// refuses a request that did not come through the account endpoint first
/// (measured 2026-09-22: anonymous CDN → 302 to `/unauthorized/`), so the URL
/// published on the `RemoteVersion` is the AUTHORIZED one,
/// `developer.apple.com/services-account/download?path=/Developer_Tools/<dir>/<file>.xip`
/// (`authorizedDownloadURL`). Only an exact `https://download.developer.apple.com/
/// Developer_Tools/<dir>/<file>.xip` is rewritten; anything else leaves
/// `downloadURL` nil and the row detection-only, as every row used to be.
///
/// Fetching it needs the user's Apple ID session, which only the menu-bar app has
/// (an embedded, signed-in web view). So the bytes come through
/// `XcodeArchiveDownloading`, the install route is `InstallCoordinator.Route.xcode`,
/// and a host without a downloader (the `duo` CLI) refuses it. `XcodeInstaller`
/// checks the archive's Apple signature, expands it and runs the usual bundle
/// gates before replacing the installed copy in place — at its own path.
///
/// Several entries can describe one build packaged for different Macs (26.6:
/// `Xcode_26.6_Apple_silicon.xip` and `Xcode_26.6_Universal.xip`, same build, same
/// `_versionOrder`), each listing `links.download.architectures`. The one offered
/// is chosen for the host (`chooseDownload`); an entry that lists none is never
/// chosen, because "unknown" is not "fits".
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
/// user gets offered a downgrade. The one exception is a bundle that says itself
/// that it is a beta (`BetaVersion.plist`): it is ranked where the index would
/// rank it and offered only what is strictly above (`fallbackOffer`).
///
/// Offers follow a stability floor (the model `ReleaseChannel` uses elsewhere): an
/// install is offered anything at or above its own stability, never below. A beta
/// user is offered a newer beta, an RC, or the GA; a release user is only ever
/// offered another release. `_versionOrder` — the index's own ranking, which
/// already sorts release above rc above beta within a version — decides "newer",
/// so no string comparison has to understand Apple's build spelling. Parallel
/// lines are not special-cased: 27.2 beta 1 outranks the later-published,
/// device-specific 27.1 beta, and that is the intended answer.
///
/// **One exception, by install path** (`followsBetaLine`): a copy whose bundle is
/// named exactly `Xcode-beta.app` follows the beta line for good, and is offered
/// the newest beta, RC or GA whatever it reads as today. The one-click replaces a
/// bundle in place, keeping its path, so once a beta is overwritten by the GA — or
/// sits on the last RC, which is byte-identical to the GA and reads as release —
/// the floor above would stop offering it the next beta, and the copy the user
/// keeps for betas would quietly turn into a second release Xcode. The name is
/// only a convention, which is why it decides what to OFFER and never what a
/// build IS: the installed release is still found by build, as above.
///
/// ## The macOS floor
///
/// Every entry states the macOS it needs (`requires`), and the floor MOVES inside
/// one Xcode version: measured 2026-09-15 on the live index, 27.0 RC 1
/// (`27A266a`) requires macOS 26.6 while all six 27.0 betas require 26.4. This
/// source was ignoring the field, so a Mac on 26.0–26.5 was shown 27.0 RC as
/// available — a version that does not exist for that Mac (#640). The floor now
/// both bounds the candidates and rides along on the `RemoteVersion`; when there
/// is a download, install-time gate 6 reads the bundle's own floor as well.
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
            forBuild: installedBuild, in: try await fetch(), osVersion: HostOS.numericVersion(),
            host: .current, followsBetaLine: Self.followsBetaLine(installedAt: app.path),
            installedBeta: Self.installedBeta(at: app.path, shortVersion: app.shortVersion))
    }

    /// What a beta bundle says about itself: its marketing version and the seed
    /// in `Contents/Resources/BetaVersion.plist` (`{ seedNumber = "5"; }` in the
    /// 27.0 beta 5 bundle; an RC or GA bundle has no such file). Only consulted
    /// when the index does not list the installed build — see `fallbackOffer`.
    struct InstalledBeta: Sendable, Equatable {
        let shortVersion: String
        let seed: Int
    }

    /// Reads the file at check time. Nil when there is none, it does not parse,
    /// or the bundle has no marketing version.
    static func installedBeta(at bundle: URL, shortVersion: String?) -> InstalledBeta? {
        guard let shortVersion,
              let data = try? Data(contentsOf: bundle.appendingPathComponent(
                "Contents/Resources/BetaVersion.plist")),
              let seed = betaSeed(fromBetaVersionPlist: data)
        else { return nil }
        return InstalledBeta(shortVersion: shortVersion, seed: seed)
    }

    /// `seedNumber` from a `BetaVersion.plist`, as a string ("5", as measured) or
    /// a number. Nil outside 1…899: 900 and up is where the index ranks RCs.
    static func betaSeed(fromBetaVersionPlist data: Data) -> Int? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        else { return nil }
        let seed: Int?
        switch plist["seedNumber"] {
        case let text as String: seed = Int(text.trimmingCharacters(in: .whitespaces))
        case let number as Int: seed = number
        default: seed = nil
        }
        guard let seed, (1...899).contains(seed) else { return nil }
        return seed
    }

    /// Where the index would rank "`version` beta `seed`" in `_versionOrder`:
    /// `major·10⁹ + minor·10⁶ + patch·10³ + seed`. Checked 2026-09-22 against the
    /// live index: the same formula (with 900+n for RC n and 999 for a release)
    /// reproduces all 412 beta, RC, release and GM entries exactly; only the old
    /// "GM seed" and "DP" entries follow other rules, and neither is a beta.
    /// Nil for a version that does not parse into at most three numbers with
    /// minor and patch under 1000.
    static func rank(ofBetaSeed seed: Int, version: String) -> Int? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let n = Int(part), n >= 0 else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        guard numbers[1] < 1000, numbers[2] < 1000, (1...899).contains(seed),
              numbers[0] < 1_000_000 else { return nil }
        return numbers[0] * 1_000_000_000 + numbers[1] * 1_000_000 + numbers[2] * 1_000 + seed
    }

    /// The installed release and the offer for a build the index does NOT list,
    /// from what the bundle says about itself — the window between Apple shipping
    /// a seed and xcodereleases.com listing it. Nil when `beta` cannot be ranked.
    ///
    /// Two rules keep this honest, because a guess here is either a downgrade or
    /// a false "up to date":
    ///
    /// - Only a release ranked STRICTLY above the installed seed is offered, with
    ///   the beta floor and the host's macOS floor as usual. Equal is not above.
    /// - When nothing is above it but the index lists a DIFFERENT build at the
    ///   same rank — a respin of that seed (Apple has shipped two "beta 1"s) —
    ///   which of the two is newer cannot be told, so this answers nil, exactly
    ///   as an unknown build always did. Only when nothing ties is the copy its
    ///   own offer: it is ahead of everything the index knows.
    ///
    /// `remote` then places the installed build in the lineage at this rank, so
    /// `UpdateChecker.evaluate` can order the pair instead of failing.
    static func fallbackOffer(
        forBuild installedBuild: String, beta: InstalledBeta,
        in releases: [Release], osVersion: String
    ) -> (installed: Release, offer: Release)? {
        guard let rank = rank(ofBetaSeed: beta.seed, version: beta.shortVersion),
              let installed = Release(json: [
                "name": "Xcode",
                "_versionOrder": rank,
                "version": [
                    "number": beta.shortVersion, "build": installedBuild,
                    "release": ["beta": beta.seed],
                ] as [String: Any],
              ])
        else { return nil }
        let newer = releases.filter {
            $0.order > rank
                && $0.stability >= .beta
                && SignatureVerifier.canRun(minimumSystemVersion: $0.requires, on: osVersion)
        }
        if let latest = newer.max(by: { $0.order < $1.order }) {
            return (installed, latest)
        }
        if releases.contains(where: { $0.order == rank }) { return nil }
        return (installed, installed)
    }

    /// Whether the copy at `path` stays on the beta line whatever it reads as —
    /// see "Channels" above. The bundle's own name, exactly.
    static func followsBetaLine(installedAt path: URL) -> Bool {
        path.lastPathComponent == "Xcode-beta.app"
    }

    /// What `latestVersion` reports for an installed build, given the index. Pure,
    /// so the engine's verdict on it is testable without network.
    ///
    /// `osVersion`, `host` and `followsBetaLine` have no defaults on purpose: the
    /// index states a macOS floor per release (`requires`) and the architectures
    /// of each archive, so this function's answer depends on the host, and a
    /// default would let a test silently measure whichever Mac it runs on.
    static func remote(
        forBuild installedBuild: String, in releases: [Release], osVersion: String,
        host: HostArch, followsBetaLine: Bool, installedBeta: InstalledBeta?
    ) -> RemoteVersion? {
        let installed: Release, offer: Release
        // The releases the lineage is built from: the index, plus the installed
        // build at its derived rank when the index does not list it.
        var ranked = releases
        if let known = Self.offer(
            forBuild: installedBuild, in: releases, osVersion: osVersion,
            followsBetaLine: followsBetaLine) {
            (installed, offer) = known
        } else if let installedBeta, let guessed = Self.fallbackOffer(
            forBuild: installedBuild, beta: installedBeta, in: releases, osVersion: osVersion) {
            (installed, offer) = guessed
            ranked.append(guessed.installed)
        } else {
            return nil
        }
        // Nil when no archive of the offered build fits this Mac, or none has a URL
        // `authorizedDownloadURL` accepts — the row is then detection-only.
        let download = Self.chooseDownload(
            among: releases.filter { $0.build == offer.build && $0.order == offer.order },
            host: host)?.authorizedURL

        return RemoteVersion(
            // Build-to-build is the real comparison (`shortVersion` here is a label
            // for the row: "27.0 beta 6", not something to compare against the
            // installed "27.0" — `UpdateChecker.evaluate` prefers the build whenever
            // both sides have one, which for Xcode is always).
            shortVersion: offer.displayVersion,
            version: offer.build,
            // The authorized endpoint, not the CDN URL — see "What it offers to
            // install" above.
            downloadURL: download,
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
            // can run. Carried anyway because it is a fact about the release.
            // Nothing reads it yet — the row's "requires macOS N" line (#634
            // part 3) would be the first. Gate 6 separately reads the expanded
            // bundle's own floor at install time.
            minimumSystemVersion: offer.requires,
            sourceName: Self.sourceName,
            requiresManualInstaller: download == nil,
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
            buildLineage: Self.lineage(of: ranked)
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
    /// candidate list, then take its head), with the same predicate. It is the
    /// only floor gate at CHECK time (`UpdateChecker.evaluate` asks nothing about
    /// the host); when the offer carries a download, install-time gate 6 also
    /// reads the expanded bundle's `LSMinimumSystemVersion`.
    ///
    /// `followsBetaLine` lowers the stability floor to beta for a copy that
    /// tracks betas by its path (see "Channels" above), so a beta-path copy that
    /// reads as release today is still offered the next beta.
    static func offer(
        forBuild installedBuild: String, in releases: [Release], osVersion: String,
        followsBetaLine: Bool
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
        // A beta-path copy's floor is beta whatever it reads as now — lowered,
        // never raised: a developer preview installed there keeps its own.
        let floor = followsBetaLine ? min(installed.stability, .beta) : installed.stability
        let candidates = releases.filter {
            $0.stability >= floor
                && SignatureVerifier.canRun(minimumSystemVersion: $0.requires, on: osVersion)
        }
        guard let latest = candidates.max(by: { $0.order < $1.order }) else {
            return (installed, installed)
        }
        return (installed, latest.order > installed.order ? latest : installed)
    }

    // MARK: - Download

    /// The archive to offer among `entries` — the entries of ONE build and rank —
    /// for a Mac of architecture `host`, or nil when none fits.
    ///
    /// On Apple silicon an arm64-only archive is preferred (the same build, a
    /// smaller download), then one that also carries arm64 (Universal). On Intel
    /// only an archive that carries x86_64 will do. An entry that lists no
    /// architectures, or whose URL `authorizedDownloadURL` refused, is never
    /// chosen. Ties go to the lexically first URL, so the answer does not depend
    /// on the index's order.
    static func chooseDownload(among entries: [Release], host: HostArch) -> Release? {
        let usable = entries
            .compactMap { entry in entry.authorizedURL.map { (url: $0, entry: entry) } }
            .sorted { $0.url.absoluteString < $1.url.absoluteString }
            .map(\.entry)
        // An entry that lists none reads as the empty set, which no rule below
        // accepts.
        func archs(_ entry: Release) -> Set<String> { Set(entry.architectures ?? []) }
        switch host {
        case .arm64:
            return usable.first { archs($0) == ["arm64"] }
                ?? usable.first { archs($0).contains("arm64") }
        case .x86_64:
            return usable.first { archs($0).contains("x86_64") }
        }
    }

    /// `developer.apple.com/services-account/download?path=…` for a CDN URL the
    /// index publishes, or nil for anything that is not exactly
    /// `https://download.developer.apple.com/Developer_Tools/<dir>/<file>.xip`.
    ///
    /// Strict on purpose: the URL is handed to a web view holding the user's
    /// Apple ID session, and what comes back is expanded and swapped over an
    /// installed app. Each path component is limited to the characters Apple's
    /// own names use (measured 2026-09-22: every `Developer_Tools/…/….xip` in the
    /// live index is made of them), which also keeps `..`, percent-escapes and a
    /// smuggled query out of the rewritten `path=`.
    static func authorizedDownloadURL(fromCDN raw: String) -> URL? {
        guard let components = URLComponents(string: raw),
              components.scheme == "https",
              components.host == "download.developer.apple.com",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil
        else { return nil }
        // ["", "Developer_Tools", dir, file]
        let parts = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].isEmpty, parts[1] == "Developer_Tools" else { return nil }
        for part in parts[2...] {
            guard part != ".", part != "..",
                  !part.isEmpty, part.allSatisfy(Self.pathCharacters.contains)
            else { return nil }
        }
        guard parts[3].hasSuffix(".xip"), parts[3].count > ".xip".count else { return nil }
        var out = URLComponents()
        out.scheme = "https"
        out.host = "developer.apple.com"
        out.path = "/services-account/download"
        out.queryItems = [URLQueryItem(name: "path", value: "/Developer_Tools/\(parts[2])/\(parts[3])")]
        return out.url
    }

    private static let pathCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")

    // MARK: - Feed

    func fetch() async throws -> [Release] {
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
        /// `links.download.url`, already rewritten by `authorizedDownloadURL` —
        /// nil when the entry has none, or it was refused.
        let authorizedURL: URL?
        /// `links.download.architectures` ("arm64", "x86_64"), or nil when the
        /// entry does not say — as most older entries do not.
        let architectures: [String]?
        /// The index's `date` (`{year, month, day}`), for display only.
        let date: DateComponents?

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
            let links = json["links"] as? [String: Any]
            self.notesURL = (links?["notes"] as? [String: Any])
                .flatMap { $0["url"] as? String }
                .flatMap(URL.init(string:))
            let download = links?["download"] as? [String: Any]
            self.authorizedURL = (download?["url"] as? String)
                .flatMap(XcodeReleasesSource.authorizedDownloadURL(fromCDN:))
            self.architectures = download?["architectures"] as? [String]
            let day = json["date"] as? [String: Any]
            if let y = day?["year"] as? Int, let m = day?["month"] as? Int, let d = day?["day"] as? Int {
                self.date = DateComponents(year: y, month: m, day: d)
            } else {
                self.date = nil
            }
        }
    }
}
