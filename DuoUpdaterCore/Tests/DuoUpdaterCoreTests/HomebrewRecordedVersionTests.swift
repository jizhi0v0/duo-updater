import Foundation
import Testing
@testable import DuoUpdaterCore

/// A brew copy is compared against the cask version Homebrew records installed
/// where the bundle's own marketing string is older (`comparedWithHomebrewRecord`).
/// The four brew copies on the development machine whose bundle and Caskroom
/// disagree (measured 2026-11-08) are the cases.
@Suite struct HomebrewRecordedVersionTests {
    private static func app(_ name: String, _ short: String, build: String? = nil) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: "example.\(name)", shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/\(name).app"), isMASApp: false, sparkleFeedURL: nil)
    }

    // MARK: - Which side a comparison reads

    /// WezTerm's bundle says 0.1.0 in every build; brew's record names the release.
    @Test func aPlaceholderBundleVersionReadsAsTheRecord() {
        let copy = Self.app("WezTerm", "0.1.0", build: "1").comparedWithHomebrewRecord("20240203-110809")
        #expect(copy.shortVersion == "20240203-110809")
        #expect(copy.buildVersion == "1")
    }

    /// A copy that updated itself past brew's record keeps its own version: IINA
    /// (brew 1.5.0, bundle 1.5.1) and DuoUpdater on a beta (brew 0.5.23).
    @Test(arguments: [("1.5.1", "1.5.0"), ("0.5.24-beta.4", "0.5.23")])
    func aBundleNewerThanTheRecordKeepsItsOwnVersion(bundle: String, recorded: String) {
        #expect(Self.app("App", bundle).comparedWithHomebrewRecord(recorded).shortVersion == bundle)
    }

    /// GitHub Desktop: brew's "3.6.10-ffeefe5d" ranks below the bundle's 3.6.10
    /// (a text run sorts below the implied 0), so the bundle stays the answer.
    @Test func aRecordWithACommitSuffixDoesNotReplaceTheSameRelease() {
        #expect(Self.app("GitHub Desktop", "3.6.10").comparedWithHomebrewRecord("3.6.10-ffeefe5d").shortVersion == "3.6.10")
    }

    /// No record, or one that is not a version (`version :latest` casks).
    @Test(arguments: [nil, "", "latest"] as [String?])
    func aMissingOrNonVersionRecordChangesNothing(recorded: String?) {
        #expect(Self.app("App", "1.0").comparedWithHomebrewRecord(recorded).shortVersion == "1.0")
    }

    /// A packaging revision is not a newer release: brew's `102.0-2` is the
    /// bundle's 102.0, and read as one string it ranks as 102.0.2 — which would
    /// hide a real 102.0.1 (adversarial review, 2026-11-08).
    @Test func aPackagingRevisionDoesNotRaiseTheBundle() {
        let copy = Self.app("MKVToolNix", "102.0", build: "102.0").comparedWithHomebrewRecord("102.0-2")
        #expect(copy.shortVersion == "102.0")
        let next = RemoteVersion(shortVersion: "102.0.1", version: nil, downloadURL: nil, sourceName: "Homebrew")
        var withRecord = next
        withRecord.homebrewRecordedVersion = "102.0-2"
        #expect(UpdateChecker.evaluate(installed: Self.app("MKVToolNix", "102.0"), remote: withRecord)
            == .updateAvailable(latest: "102.0.1"))
    }

    /// A source that compares builds keeps comparing the bundle's own marketing
    /// string beside them. The record would otherwise trip the "marketing says
    /// backwards" second opinion and turn every real build update into "up to
    /// date" (adversarial review, 2026-11-08).
    @Test(arguments: [
        // A frozen placeholder marketing string; the build moves.
        ("0.1.0", "100", "20240203-110809", "0.1.0", "200"),
        // A cask versioned by build number.
        ("2.3", "4500", "4521", "2.4", "4600"),
    ])
    func aBuildUpdateIsNotHiddenByTheRecord(
        short: String, build: String, recorded: String, offeredShort: String, offeredBuild: String
    ) {
        var remote = RemoteVersion(shortVersion: offeredShort, version: offeredBuild, marketingMatchesBundle: true,
                                   downloadURL: nil, sourceName: "Sparkle")
        remote.homebrewRecordedVersion = recorded
        #expect(UpdateChecker.evaluate(installed: Self.app("App", short, build: build), remote: remote)
            == .updateAvailable(latest: offeredShort))
    }

    // MARK: - The Homebrew source

    private static func wezTerm(caskVersion: String, recorded: String?) async throws -> RemoteVersion? {
        let entry = CaskEntry(
            token: "wezterm", version: caskVersion,
            url: URL(string: "https://github.com/wezterm/wezterm/releases/download/x/WezTerm-macos-x.zip"),
            autoUpdates: false, installKind: .brew)
        let source = HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: CaskIndex(
                allByAppFilename: ["wezterm.app": [entry]], allByBundleID: [:])),
            inventory: BrewLocalInventory(
                installedTokens: ["wezterm"],
                installedVersions: recorded.map { ["wezterm": $0] } ?? [:]))
        return try await source.latestVersion(for: app("WezTerm", "0.1.0", build: "1"))
    }

    /// Brew installed the current cask: up to date, as `brew outdated` says.
    @Test func wezTermOnTheCurrentCaskIsUpToDate() async throws {
        let remote = try #require(try await Self.wezTerm(
            caskVersion: "20240203-110809,5046fc22", recorded: "20240203-110809,5046fc22"))
        #expect(remote.homebrewRecordedVersion == "20240203-110809")
        #expect(UpdateChecker.evaluate(installed: Self.app("WezTerm", "0.1.0", build: "1"), remote: remote) == .upToDate)
    }

    /// Without the record the bundle's 0.1.0 is all there is, and the row offers
    /// the release it has — the behaviour this change removes.
    @Test func wezTermWithoutARecordStillReadsItsBundle() async throws {
        let remote = try #require(try await Self.wezTerm(caskVersion: "20240203-110809,5046fc22", recorded: nil))
        #expect(remote.homebrewRecordedVersion == nil)
        #expect(UpdateChecker.evaluate(installed: Self.app("WezTerm", "0.1.0", build: "1"), remote: remote)
            == .updateAvailable(latest: "20240203-110809"))
    }

    /// A newer cask is still an update.
    @Test func wezTermBehindANewerCaskIsOffered() async throws {
        let remote = try #require(try await Self.wezTerm(
            caskVersion: "20260101-000000,0123abcd", recorded: "20240203-110809,5046fc22"))
        #expect(UpdateChecker.evaluate(installed: Self.app("WezTerm", "0.1.0", build: "1"), remote: remote)
            == .updateAvailable(latest: "20260101-000000"))
    }

    // MARK: - Sources asked after Homebrew

    /// Homebrew answers "up to date" for WezTerm against its record. `auto_updates`
    /// so the checker asks the next source, as it does for such casks by default.
    private struct Brew: UpdateSource {
        let name = "Homebrew"
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            var remote = RemoteVersion(shortVersion: "20240203-110809", version: nil, downloadURL: nil,
                                       sourceName: name, sourceIdentifier: "wezterm")
            remote.homebrewSelfUpdating = true
            remote.homebrewRecordedVersion = "20240203-110809"
            return remote
        }
    }

    private struct Downstream: UpdateSource {
        let name = "GitHub"
        let offers: String
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            RemoteVersion(shortVersion: offers, version: nil, downloadURL: nil, sourceName: name)
        }
    }

    private func check(downstreamOffers offer: String) async -> UpdateResult {
        await UpdateChecker(
            sources: [Brew(), Downstream(offers: offer)], brewFallback: BrewFallbackPolicy(),
            installedTeam: { _ in nil }).check(Self.app("WezTerm", "0.1.0", build: "1"))
    }

    /// The next source offering the release brew installed is not an update.
    @Test func aLaterSourceDoesNotReofferTheReleaseBrewRecords() async {
        let result = await check(downstreamOffers: "20240203-110809")
        #expect(result.remote?.sourceName == "GitHub")
        #expect(result.remote?.homebrewRecordedVersion == "20240203-110809")
        #expect(!result.hasUpdate)
        // The kept remote re-evaluates the same way on a rescan.
        if let remote = result.remote {
            #expect(UpdateChecker.evaluate(installed: Self.app("WezTerm", "0.1.0", build: "1"), remote: remote) == .upToDate)
        }
    }

    /// …and a newer release from it still is.
    @Test func aLaterSourceStillOffersANewerRelease() async {
        let result = await check(downstreamOffers: "20260101-000000")
        #expect(result.remote?.sourceName == "GitHub")
        #expect(result.hasUpdate)
    }
}
