import Foundation
import Testing
@testable import DuoUpdaterCore

/// Blender's alpha / beta / release-candidate tracks, read from
/// builder.blender.org's daily listing and ordered by `BuildLineage.head`.
///
/// Every entry below is the vendor's, verbatim, fetched 2026-09-25:
/// - `dailyListing`: four of the 131 objects in
///   `https://builder.blender.org/download/daily/?format=json&v=1` — the stale
///   2024 Windows alpha the listing still carries (first in the document), the
///   5.3.0 alpha dmg and its `.sha256` companion, and the 5.2.2 stable dmg. It had
///   no beta and no candidate entry that day.
/// - `candidateListing` / `betaListing`: objects from the ~100-day archive
///   (`/download/daily/archive/?format=json&v=1`), the only place a beta or a
///   candidate could be read that day. The one change is the `archive/` path
///   segment dropped from `url`, which is where the daily listing puts a build
///   while it is current.
///
/// The builds the evaluation tests use are real: 425ab43ad645 is the 5.3.0 alpha
/// the audit mounted (built 2026-09-25 01:35:56 UTC), 3bcf2d172c1f the alpha the
/// builder published the day before.
struct BlenderBuilderTrackTests {

    static let dailyListing = #"""
        [
            {
                "url": "https://cdn.builder.blender.org/download/daily/blender-4.2.0-alpha+main.1c92d26bfc8d-windows.arm64-release.zip.sha256",
                "app": "Blender",
                "version": "4.2.0",
                "risk_id": "alpha",
                "branch": "main",
                "patch": null,
                "hash": "1c92d26bfc8d",
                "platform": "windows",
                "architecture": "arm64",
                "bitness": 64,
                "file_mtime": 1717570478,
                "file_name": "blender-4.2.0-alpha+main.1c92d26bfc8d-windows.arm64-release.zip.sha256",
                "file_size": 64,
                "file_extension": "sha256",
                "release_cycle": "alpha"
            },
            {
                "url": "https://cdn.builder.blender.org/download/daily/blender-5.3.0-alpha+main.425ab43ad645-darwin.arm64-release.dmg",
                "app": "Blender",
                "version": "5.3.0",
                "risk_id": "alpha",
                "branch": "main",
                "patch": null,
                "hash": "425ab43ad645",
                "platform": "darwin",
                "architecture": "arm64",
                "bitness": 64,
                "file_mtime": 1790305104,
                "file_name": "blender-5.3.0-alpha+main.425ab43ad645-darwin.arm64-release.dmg",
                "file_size": 352762236,
                "file_extension": "dmg",
                "release_cycle": "alpha"
            },
            {
                "url": "https://cdn.builder.blender.org/download/daily/blender-5.3.0-alpha+main.425ab43ad645-darwin.arm64-release.dmg.sha256",
                "app": "Blender",
                "version": "5.3.0",
                "risk_id": "alpha",
                "branch": "main",
                "patch": null,
                "hash": "425ab43ad645",
                "platform": "darwin",
                "architecture": "arm64",
                "bitness": 64,
                "file_mtime": 1790305104,
                "file_name": "blender-5.3.0-alpha+main.425ab43ad645-darwin.arm64-release.dmg.sha256",
                "file_size": 64,
                "file_extension": "sha256",
                "release_cycle": "alpha"
            },
            {
                "url": "https://cdn.builder.blender.org/download/daily/blender-5.2.2-stable+v52.d13f752e3b9c-darwin.arm64-release.dmg",
                "app": "Blender",
                "version": "5.2.2",
                "risk_id": "stable",
                "branch": "v52",
                "patch": null,
                "hash": "d13f752e3b9c",
                "platform": "darwin",
                "architecture": "arm64",
                "bitness": 64,
                "file_mtime": 1790303740,
                "file_name": "blender-5.2.2-stable+v52.d13f752e3b9c-darwin.arm64-release.dmg",
                "file_size": 346286267,
                "file_extension": "dmg",
                "release_cycle": "stable"
            }
        ]
        """#

    /// Two lines' candidates at once, the newer LINE listed first and uploaded
    /// EARLIER (5.2.1 on 2026-08-18, 4.5.13 on 2026-08-24).
    static let candidateListing = #"""
        [
        {
                "url": "https://cdn.builder.blender.org/download/daily/blender-5.2.1-candidate+v52.42e35690b2d0-darwin.arm64-release.dmg",
                "app": "Blender",
                "version": "5.2.1",
                "risk_id": "candidate",
                "branch": "v52",
                "patch": null,
                "hash": "42e35690b2d0",
                "platform": "darwin",
                "architecture": "arm64",
                "bitness": 64,
                "file_mtime": 1787021181,
                "file_name": "blender-5.2.1-candidate+v52.42e35690b2d0-darwin.arm64-release.dmg",
                "file_size": 346149829,
                "file_extension": "dmg",
                "release_cycle": "candidate"
            },
        {
                "url": "https://cdn.builder.blender.org/download/daily/blender-4.5.13-candidate+v45.bf319e10923f-darwin.arm64-release.dmg",
                "app": "Blender",
                "version": "4.5.13",
                "risk_id": "candidate",
                "branch": "v45",
                "patch": null,
                "hash": "bf319e10923f",
                "platform": "darwin",
                "architecture": "arm64",
                "bitness": 64,
                "file_mtime": 1787535992,
                "file_name": "blender-4.5.13-candidate+v45.bf319e10923f-darwin.arm64-release.dmg",
                "file_size": 311909870,
                "file_extension": "dmg",
                "release_cycle": "candidate"
            }
        ]
        """#

    static let betaListing = #"""
        [
        {
                "url": "https://cdn.builder.blender.org/download/daily/blender-5.2.0-beta+v52.0f747cfcddcc-darwin.arm64-release.dmg",
                "app": "Blender",
                "version": "5.2.0",
                "risk_id": "beta",
                "branch": "v52",
                "patch": null,
                "hash": "0f747cfcddcc",
                "platform": "darwin",
                "architecture": "arm64",
                "bitness": 64,
                "file_mtime": 1782268932,
                "file_name": "blender-5.2.0-beta+v52.0f747cfcddcc-darwin.arm64-release.dmg",
                "file_size": 346006611,
                "file_extension": "dmg",
                "release_cycle": "beta"
            },
        {
                "url": "https://cdn.builder.blender.org/download/daily/blender-5.3.0-alpha+main.425ab43ad645-darwin.arm64-release.dmg",
                "app": "Blender",
                "version": "5.3.0",
                "risk_id": "alpha",
                "branch": "main",
                "patch": null,
                "hash": "425ab43ad645",
                "platform": "darwin",
                "architecture": "arm64",
                "bitness": 64,
                "file_mtime": 1790305104,
                "file_name": "blender-5.3.0-alpha+main.425ab43ad645-darwin.arm64-release.dmg",
                "file_size": 352762236,
                "file_extension": "dmg",
                "release_cycle": "alpha"
            }
        ]
        """#

    static func recipe(_ channel: ReleaseChannel) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == BlenderBuildInfo.bundleID && $0.channel == channel
        })
    }

    /// What the probe reads from `body`, by the production slicing and extractors.
    struct Reading: Equatable {
        var version: String?
        var head: String?
        var publishedAt: String?
        var installURL: String?
    }

    static func read(_ body: String, as channel: ReleaseChannel) throws -> Reading {
        let recipe = try recipe(channel)
        let entryStart = try #require(recipe.entryStartPattern)
        let headPattern = try #require(recipe.headBuildPattern)
        let publishedPattern = try #require(recipe.publishedAtPattern)
        let install = try #require(recipe.install)
        let entry = try #require(VendorProbeRecipe.highestVersionEntry(
            in: body, entryStartPattern: entryStart,
            versionPattern: recipe.versionPattern, selectHighest: recipe.selectHighest))
        guard case .bodyPattern(let urlPattern) = install.urlSource else {
            Issue.record("expected a bodyPattern install source")
            return Reading()
        }
        return Reading(
            version: VendorProbeRecipe.extractVersion(from: entry, pattern: recipe.versionPattern),
            head: VendorProbeRecipe.extractVersion(from: entry, pattern: headPattern),
            publishedAt: VendorProbeRecipe.extractVersion(from: entry, pattern: publishedPattern),
            installURL: VendorProbeRecipe.extractVersion(from: entry, pattern: urlPattern))
    }

    static func isClosed(_ body: String, as channel: ReleaseChannel) throws -> Bool {
        let recipe = try recipe(channel)
        let pattern = try #require(recipe.trackClosedPattern)
        return body.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - What each track reads

    /// The stale Windows alpha comes first in the document and the dmg's
    /// `.sha256` companion carries the same version and commit; neither is the
    /// entry read.
    @Test func theAlphaTrackReadsTheMacDmgEntry() throws {
        #expect(try Self.read(Self.dailyListing, as: .alpha) == Reading(
            version: "5.3.0", head: "425ab43ad645", publishedAt: "1790305104",
            installURL: "https://cdn.builder.blender.org/download/daily/blender-5.3.0-alpha+main.425ab43ad645-darwin.arm64-release.dmg"))
    }

    /// The newer line wins by version, not by position or upload time.
    @Test func theCandidateTrackReadsTheNewestLine() throws {
        #expect(try Self.read(Self.candidateListing, as: .rc) == Reading(
            version: "5.2.1", head: "42e35690b2d0", publishedAt: "1787021181",
            installURL: "https://cdn.builder.blender.org/download/daily/blender-5.2.1-candidate+v52.42e35690b2d0-darwin.arm64-release.dmg"))
    }

    @Test func theBetaTrackReadsOnlyTheBetaEntry() throws {
        #expect(try Self.read(Self.betaListing, as: .beta) == Reading(
            version: "5.2.0", head: "0f747cfcddcc", publishedAt: "1782268932",
            installURL: "https://cdn.builder.blender.org/download/daily/blender-5.2.0-beta+v52.0f747cfcddcc-darwin.arm64-release.dmg"))
    }

    /// Between cycles the listing has no beta and no candidate: that is "closed",
    /// not a broken recipe — and only while the listing still has its usual shape.
    @Test func aTrackWithNoEntryIsClosedOnlyInAListingThatStillReads() throws {
        #expect(try Self.isClosed(Self.dailyListing, as: .beta))
        #expect(try Self.isClosed(Self.dailyListing, as: .rc))
        // A track that is publishing is never closed.
        #expect(try !Self.isClosed(Self.betaListing, as: .beta))
        // A listing whose shape changed is a broken recipe, not a closed track.
        let renamed = Self.dailyListing.replacingOccurrences(of: "\"risk_id\"", with: "\"risk\"")
        #expect(try !Self.isClosed(renamed, as: .beta))
        #expect(try !Self.isClosed(renamed, as: .rc))
        #expect(try Self.recipe(.alpha).trackClosedPattern == nil)
    }

    @Test func eachTrackInstallsOnlyItsOwnBuilds() throws {
        func complaint(_ channel: ReleaseChannel, _ url: String) throws -> String? {
            RecipeSanity.crossChannelArtifact(recipe: try Self.recipe(channel), remote: RemoteVersion(
                shortVersion: "5.3.0", version: "425ab43ad645",
                downloadURL: URL(string: url)!, sourceName: "Blender", vendorInstallerKind: .dmg))
        }
        let base = "https://cdn.builder.blender.org/download/daily/"
        let alpha = base + "blender-5.3.0-alpha+main.425ab43ad645-darwin.arm64-release.dmg"
        let beta = base + "blender-5.2.0-beta+v52.0f747cfcddcc-darwin.arm64-release.dmg"
        let candidate = base + "blender-5.2.1-candidate+v52.42e35690b2d0-darwin.arm64-release.dmg"
        let stable = base + "blender-5.2.2-stable+v52.d13f752e3b9c-darwin.arm64-release.dmg"
        #expect(try complaint(.alpha, alpha) == nil)
        #expect(try complaint(.beta, beta) == nil)
        #expect(try complaint(.rc, candidate) == nil)
        for (channel, foreign) in [(ReleaseChannel.alpha, stable), (.beta, stable), (.rc, stable),
                                   (.alpha, beta), (.beta, candidate), (.rc, alpha)] {
            #expect(try complaint(channel, foreign) != nil, "\(channel) accepted \(foreign)")
        }
    }

    // MARK: - Ordering by the head

    static func app(
        _ version: String, commit: String?, builtAt: TimeInterval
    ) -> InstalledApp {
        let path = "/Applications/ZZFixture-Blender.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        return InstalledApp(
            name: "Blender", bundleID: BlenderBuildInfo.bundleID,
            shortVersion: version, buildVersion: version,
            vendorBuildVersion: commit, vendorBuildDate: Date(timeIntervalSince1970: builtAt),
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    /// Built the way the probe builds it, so a remote here carries exactly what a
    /// production one would.
    static func remote(
        _ channel: ReleaseChannel, _ version: String, head: String, publishedAt: TimeInterval
    ) throws -> RemoteVersion {
        VendorProbeSource.makeRemoteVersion(
            recipe: try recipe(channel), version: version, install: nil, plan: nil,
            resolvedDownload: nil, publishedAt: Date(timeIntervalSince1970: publishedAt),
            lineage: .head(head))
    }

    /// 2026-09-25 01:35:56 UTC, the mounted alpha's build stamp.
    static let alphaBuilt: TimeInterval = 1_790_300_156
    static let alphaPublished: TimeInterval = 1_790_305_104

    @Test func theHeadItselfIsUpToDate() throws {
        #expect(UpdateChecker.evaluate(
            installed: Self.app("5.3.0", commit: "425ab43ad645", builtAt: Self.alphaBuilt),
            remote: try Self.remote(.alpha, "5.3.0", head: "425ab43ad645", publishedAt: Self.alphaPublished))
            == .upToDate)
    }

    /// Yesterday's alpha. Every 5.3 alpha says "5.3.0", so the marketing version
    /// alone reads it as current.
    @Test func anOlderAlphaIsOfferedTheHead() throws {
        #expect(!VersionComparator.isNewer("5.3.0", than: "5.3.0"))
        let status = UpdateChecker.evaluate(
            installed: Self.app("5.3.0", commit: "3bcf2d172c1f", builtAt: Self.alphaBuilt - 86_400),
            remote: try Self.remote(.alpha, "5.3.0", head: "425ab43ad645", publishedAt: Self.alphaPublished))
        #expect(status == .updateAvailable(latest: "5.3.0"))
    }

    /// A copy built AFTER the head was published is not behind it, whatever its
    /// commit — the listing lagging a build already on the builder's page.
    @Test func aCopyBuiltAfterTheHeadWasPublishedIsNotOfferedIt() throws {
        #expect(UpdateChecker.evaluate(
            installed: Self.app("5.3.0", commit: "99999999abcd", builtAt: Self.alphaPublished + 3_600),
            remote: try Self.remote(.alpha, "5.3.0", head: "425ab43ad645", publishedAt: Self.alphaPublished))
            == .upToDate)
    }

    /// The RC track headed by the 4.5 LTS candidate while the copy is the 5.2.1 RC
    /// the audit mounted (built 2026-08-24 01:31:02 UTC). That head was uploaded
    /// fifteen minutes AFTER the copy was built, so the time guard alone would let
    /// it through; the marketing version is what stops it.
    @Test func aCandidateOfAnOlderLineIsNeverOffered() throws {
        let installed = Self.app("5.2.1", commit: "5adcd79a574f", builtAt: 1_787_535_062)
        #expect(1_787_535_992 > 1_787_535_062)
        #expect(UpdateChecker.evaluate(
            installed: installed,
            remote: try Self.remote(.rc, "4.5.13", head: "bf319e10923f", publishedAt: 1_787_535_992))
            == .upToDate)
    }

    /// An earlier 5.2.1 candidate (uploaded 2026-08-18) against the next one on
    /// its own line (5adcd79a574f, uploaded 2026-08-24 02:37:35 UTC).
    @Test func aCandidateIsOfferedItsOwnLinesNextCandidate() throws {
        #expect(UpdateChecker.evaluate(
            installed: Self.app("5.2.1", commit: "42e35690b2d0", builtAt: 1_787_011_200),
            remote: try Self.remote(.rc, "5.2.1", head: "5adcd79a574f", publishedAt: 1_787_539_055))
            == .updateAvailable(latest: "5.2.1"))
    }

    /// A build of the cycle but not of the track (an experimental branch) has no
    /// track commit: "cannot tell", not an offer to replace it with `main`.
    @Test func aCopyOffTheTrackIsUnknown() throws {
        #expect(UpdateChecker.evaluate(
            installed: Self.app("5.3.0", commit: nil, builtAt: Self.alphaBuilt),
            remote: try Self.remote(.alpha, "5.3.0", head: "425ab43ad645", publishedAt: Self.alphaPublished))
            == .unknown)
    }

    /// The row names both commits under the shared marketing version, and a skip
    /// records the build — so skipping one alpha does not silence the next.
    @Test func theRowAndTheSkipKeyCarryTheCommit() throws {
        let remote = try Self.remote(.alpha, "5.3.0", head: "425ab43ad645", publishedAt: Self.alphaPublished)
        let result = UpdateResult(
            app: Self.app("5.3.0", commit: "3bcf2d172c1f", builtAt: Self.alphaBuilt - 86_400),
            remote: remote, status: .updateAvailable(latest: "5.3.0"))
        #expect(result.buildBump(latest: "5.3.0")?.installed == "3bcf2d172c1f")
        #expect(result.buildBump(latest: "5.3.0")?.remote == "425ab43ad645")
        #expect(VisibilityRules.skipKey(remote.versionSide) == "5.3.0 (425ab43ad645)")
    }

    /// The pre-install re-check: a copy the user updated by hand to the head
    /// between the click and the re-check is already current, not a regression.
    @Test func aCopyThatReachedTheHeadIsAlreadyCurrent() throws {
        let offered = try Self.remote(.alpha, "5.3.0", head: "3bcf2d172c1f", publishedAt: Self.alphaPublished - 86_400)
        let confirmed = try Self.remote(.alpha, "5.3.0", head: "425ab43ad645", publishedAt: Self.alphaPublished)
        let decision = PreInstallGate.decision(
            offered: UpdateResult(
                app: Self.app("5.3.0", commit: "1a6eeebb9a2d", builtAt: Self.alphaBuilt - 20 * 86_400),
                remote: offered, status: .updateAvailable(latest: "5.3.0")),
            confirmed: UpdateResult(
                app: Self.app("5.3.0", commit: "425ab43ad645", builtAt: Self.alphaBuilt),
                remote: confirmed, status: .upToDate))
        #expect(decision == .alreadyCurrent)
    }

    // MARK: - The head lineage itself

    @Test func aHeadLineagePlacesEveryOtherBuildBehindIt() {
        let head = BuildLineage.head("425ab43ad645")
        #expect(head.isNewer("425ab43ad645", than: "3bcf2d172c1f") == true)
        #expect(head.isNewer("3bcf2d172c1f", than: "425ab43ad645") == false)
        #expect(head.isNewer("425ab43ad645", than: "425ab43ad645") == false)
        #expect(head.isNewer("3bcf2d172c1f", than: "93d2971f53c9") == nil)
        // An ordinary lineage still refuses to place a build it does not list.
        let listed = BuildLineage(newestFirst: ["425ab43ad645"])
        #expect(listed.isNewer("425ab43ad645", than: "3bcf2d172c1f") == nil)
    }
}
