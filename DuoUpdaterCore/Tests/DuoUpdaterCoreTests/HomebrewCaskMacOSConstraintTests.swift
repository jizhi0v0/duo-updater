import Testing
import Foundation
@testable import DuoUpdaterCore

/// A cask's `depends_on.macos`, and what the two catalog indexes do when several
/// casks install the same `.app` (issue #638).
///
/// Both fixtures are the **live response bodies**, fetched 2026-09-15 from
/// `formulae.brew.sh/api/cask/<token>.json` and wrapped in an array (the catalog
/// at `/api/cask.json` is an array of exactly these objects, in exactly this
/// order — measured: `onyx` at catalog position 5636 and `onyx@beta` at 5637;
/// `carbon-copy-cloner` at 643 and `carbon-copy-cloner@6` at 644). Diffed against
/// their catalog entries that day: identical apart from the two keys the
/// per-cask endpoint adds, `analytics` and `generated_date`.
///
/// Why these two pairs and not synthesised ones: the OnyX pair is the shape the
/// issue is about (`== [11…26]` vs `>= 27`, one `.app`, no bundle id in either
/// cask's artifacts), and it is the only realistic host-27 split in the catalog
/// today. The bundle-id index has **no** such pair today — measured over all
/// `uninstall: quit:` groups, no group's first cask is excluded on host 26 or 27
/// while a later one is admitted — so the CCC pair (`>= 13`, then no constraint)
/// is the real shape available for that index, and it only bites below macOS 13.
///
/// Mutation table. Every row below was applied to a working tree and this suite
/// run (2026-09-15): all twelve **compile** — not one is caught by the type
/// checker — and all twelve go red. The "red" column lists the tests that
/// actually failed, not the ones predicted beforehand; mutation 6, for instance,
/// does *not* reach `macOS26IndexesTheOnyXCaskThatAdmits26`, because with the
/// host untruncated neither OnyX cask admits 26.4 and catalog order keeps `onyx`
/// for the wrong reason — the direct constraint test is its only witness.
///
/// | # | Mutation | Measured |
/// |---|---|---|
/// | 1 | `CaskIndex.preferred`: `entries.first` (i.e. plain first-writer-wins, the old behaviour) | red: `macOS27IndexesTheOnyXCaskThatAdmits27`, `onyxBetaAdmitsMacOS27AndNothingOlder`, `bundleIDLookupPrefersTheCaskThatAdmitsTheHost` |
/// | 2 | `CaskIndex.preferred`: `entries.last { admits } ?? entries.first` (last admitted writer wins) | red: `anUnconstrainedCaskDoesNotEvictAnAdmittedIncumbent`, `bundleIDLookupPrefersTheCaskThatAdmitsTheHost` |
/// | 3 | `HomebrewCaskCatalog.index`: build `CaskEntry` with `macOS: nil` | red: `macOS27IndexesTheOnyXCaskThatAdmits27`, `onyxBetaAdmitsMacOS27AndNothingOlder`, `onyxAdmitsMacOS26PointReleasesAndNothingNewer`, `bundleIDLookupPrefersTheCaskThatAdmitsTheHost`, `withBothCasksInstalledTheHostDecides` |
/// | 4 | `CaskMacOSRequirement.admits`: `.exactly` returns `true` | red: `macOS27IndexesTheOnyXCaskThatAdmits27`, `onyxAdmitsMacOS26PointReleasesAndNothingNewer`, `onyxBetaAdmitsMacOS27AndNothingOlder`, `withBothCasksInstalledTheHostDecides` |
/// | 5 | `CaskMacOSRequirement.admits`: `.atLeast` uses `!= .orderedDescending` | red: `onyxBetaAdmitsMacOS27AndNothingOlder`, `anUnconstrainedCaskDoesNotEvictAnAdmittedIncumbent`, `bundleIDLookupPrefersTheCaskThatAdmitsTheHost` |
/// | 6 | `CaskMacOSRequirement.truncated`: return `version` unchanged (no truncation) | red: `onyxAdmitsMacOS26PointReleasesAndNothingNewer` |
/// | 7 | `CaskMacOSRequirement.admits`: empty-declaration guard returns `false` | red: `aDeclarationWithNoParseableVersionAdmitsEveryone` |
/// | 8 | `CaskMacOSRequirement.parse`: an unreadable `macos` object returns an empty requirement instead of `nil` | red: `anEmptyMacOSObjectIsNoConstraint` |
/// | 9 | `CaskEntry.admits`: `macOS?.admits(host) ?? false` | red: `anEmptyMacOSObjectIsNoConstraint`, `bundleIDLookupPrefersTheCaskThatAdmitsTheHost` |
/// | 10 | `HomebrewCaskSource`: gate on the index's preferred cask only (the old single-entry provenance check) | red: `macOS27StillResolvesTheStableCaskForSomeoneWhoInstalledIt` |
/// | 11 | `HomebrewCaskSource`: take `installed.first`, dropping the host preference | red: `withBothCasksInstalledTheHostDecides` |
/// | 12 | `HomebrewCaskSource`: drop the provenance filter, take the preferred cask | red: `macOS27StillResolvesTheStableCaskForSomeoneWhoInstalledIt`, `neitherCaskInstalledStillDeclines` |
struct HomebrewCaskMacOSConstraintTests {

    private static func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    private static func onyxIndex(host: String) throws -> CaskIndex {
        try HomebrewCaskCatalog.index(
            fromCatalogJSON: fixture("homebrew-cask-onyx-pair"), hostOSVersion: host)
    }

    private static func cccIndex(host: String) throws -> CaskIndex {
        try HomebrewCaskCatalog.index(
            fromCatalogJSON: fixture("homebrew-cask-ccc-pair"), hostOSVersion: host)
    }

    // MARK: - The app-filename index

    /// The bug in the issue: on macOS 27 the index used to answer `onyx` 5.0.4 —
    /// a build brew itself refuses to install there — because it sorts first.
    @Test func macOS27IndexesTheOnyXCaskThatAdmits27() throws {
        let entry = try #require(Self.onyxIndex(host: "27.0.0").byAppFilename["onyx.app"])
        #expect(entry.token == "onyx@beta")
        #expect(entry.version == "5.1.0,260910")
    }

    /// The other side of the same rule: on macOS 26 the answer must stay `onyx`.
    /// Note the point release — 26.4.0 is macOS 26, and `== [… "26"]` admits it.
    @Test func macOS26IndexesTheOnyXCaskThatAdmits26() throws {
        let entry = try #require(Self.onyxIndex(host: "26.4.0").byAppFilename["onyx.app"])
        #expect(entry.token == "onyx")
        #expect(entry.version == "5.0.4")
    }

    /// Catalog order still decides among casks the host can run: an unconstrained
    /// later cask (CCC 6) must not evict an admitted earlier one (CCC 7).
    @Test func anUnconstrainedCaskDoesNotEvictAnAdmittedIncumbent() throws {
        let index = try Self.cccIndex(host: "14.6.0")
        let entry = try #require(index.byAppFilename["carbon copy cloner.app"])
        #expect(entry.token == "carbon-copy-cloner")
        #expect(entry.version == "7.2,8399")
    }

    // MARK: - The bundle-id index

    @Test func bundleIDLookupPrefersTheCaskThatAdmitsTheHost() throws {
        // macOS 12: CCC 7's `>= 13` excludes this host, so the single-answer
        // lookup must fall to CCC 6 rather than to catalog order.
        let old = try Self.cccIndex(host: "12.7.6")
        #expect(old.byBundleID["com.bombich.ccc"]?.token == "carbon-copy-cloner@6")
        // macOS 14: both run, so catalog order decides again.
        let current = try Self.cccIndex(host: "14.6.0")
        #expect(current.byBundleID["com.bombich.ccc"]?.token == "carbon-copy-cloner")
        // Either way the multi-answer lookup keeps both, in catalog order.
        #expect(
            old.allByBundleID["com.bombich.ccc"]?.map(\.token)
                == ["carbon-copy-cloner", "carbon-copy-cloner@6"])
    }

    // MARK: - The constraint itself

    @Test func onyxBetaAdmitsMacOS27AndNothingOlder() throws {
        let entry = try #require(Self.onyxIndex(host: "27.0.0").byAppFilename["onyx.app"])
        let requirement = try #require(entry.macOS)
        #expect(requirement == CaskMacOSRequirement(comparison: .atLeast, versions: ["27"]))
        #expect(requirement.admits("27.0.0"))
        #expect(requirement.admits("27.1.3"))
        #expect(!requirement.admits("26.4.0"))
    }

    @Test func onyxAdmitsMacOS26PointReleasesAndNothingNewer() throws {
        let entry = try #require(Self.onyxIndex(host: "26.4.0").byAppFilename["onyx.app"])
        let requirement = try #require(entry.macOS)
        #expect(
            requirement
                == CaskMacOSRequirement(
                    comparison: .exactly, versions: ["11", "12", "13", "14", "15", "26"]))
        #expect(requirement.admits("26.4.0"))
        #expect(requirement.admits("14.0.0"))
        #expect(!requirement.admits("27.0.0"))
        // 16 is in the numeric gap the list skips, not merely below its top.
        #expect(!requirement.admits("16.0.0"))
    }

    /// `{"macos": {}}` is what 3445 of the catalog's 5003 `macos` keys render as
    /// (measured 2026-09-15). It means "no constraint", so it must parse to `nil`
    /// and not to an empty requirement that then decides anything.
    @Test func anEmptyMacOSObjectIsNoConstraint() throws {
        let index = try Self.cccIndex(host: "14.6.0")
        let six = try #require(index.allByBundleID["com.bombich.ccc"]?.last)
        #expect(six.token == "carbon-copy-cloner@6")
        #expect(six.macOS == nil)
        #expect(six.admits("12.7.6"))
    }

    // MARK: - What the source does with the pair

    /// Deliberately a path that does not exist: `UpdatePolicy.runtimeBundlePath`
    /// and friends resolve symlinks, so a real `/Applications` path would put the
    /// test's answer in the hands of whatever this Mac has installed.
    private static func onyxApp() -> InstalledApp {
        let path = "/Applications/ZZFixture-638/OnyX.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        return InstalledApp(
            name: "OnyX", bundleID: "com.titanium.OnyX", shortVersion: "5.0.4",
            buildVersion: nil, path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil)
    }

    private static func source(host: String, installed: Set<String>) throws -> HomebrewCaskSource {
        let catalog = HomebrewCaskCatalog(testIndex: try onyxIndex(host: host))
        return HomebrewCaskSource(
            catalog: catalog,
            inventory: BrewLocalInventory(installedTokens: installed),
            hostOSVersion: host)
    }

    /// The issue's first consequence: a user who installed 5.1.0 through
    /// `onyx@beta` used to get `.unknown`, because the index only ever offered the
    /// `onyx` token and it isn't in their Caskroom.
    @Test func macOS27ResolvesTheBetaCaskWhenThatIsTheInstalledOne() async throws {
        let remote = try await Self.source(host: "27.0.0", installed: ["onyx@beta"])
            .latestVersion(for: Self.onyxApp())
        #expect(remote?.sourceIdentifier == "onyx@beta")
        #expect(remote?.shortVersion == "5.1.0")
    }

    /// And the other direction, which a host-only pick would have broken: someone
    /// who installed `onyx` and then upgraded to macOS 27 still has a Homebrew row
    /// rather than an empty one, even though brew won't install that cask there.
    @Test func macOS27StillResolvesTheStableCaskForSomeoneWhoInstalledIt() async throws {
        let remote = try await Self.source(host: "27.0.0", installed: ["onyx"])
            .latestVersion(for: Self.onyxApp())
        #expect(remote?.sourceIdentifier == "onyx")
        #expect(remote?.shortVersion == "5.0.4")
    }

    /// With both installed — not a shape brew produces for one `.app`, but the
    /// index cannot know that — the host decides.
    @Test func withBothCasksInstalledTheHostDecides() async throws {
        let on27 = try await Self.source(host: "27.0.0", installed: ["onyx", "onyx@beta"])
            .latestVersion(for: Self.onyxApp())
        #expect(on27?.sourceIdentifier == "onyx@beta")
        let on26 = try await Self.source(host: "26.4.0", installed: ["onyx", "onyx@beta"])
            .latestVersion(for: Self.onyxApp())
        #expect(on26?.sourceIdentifier == "onyx")
    }

    /// The provenance gate still holds: neither cask installed → not our app.
    /// The Caskroom holds an unrelated token on purpose — with it empty the
    /// source declines one guard earlier (`inventory.isEmpty`), so the test would
    /// pass without reaching the gate it is named after. Measured: with the
    /// provenance filter deleted and an empty Caskroom it still passed.
    @Test func neitherCaskInstalledStillDeclines() async throws {
        let remote = try await Self.source(host: "27.0.0", installed: ["tableplus"])
            .latestVersion(for: Self.onyxApp())
        #expect(remote == nil)
    }

    /// Fail-open, deliberately: a declaration we cannot read must not hide a cask
    /// from the index — that is the failure this whole change exists to remove.
    /// Hand-built rather than fixture-derived because the live catalog renders
    /// every value as a bare numeric major, so there is no real body to take this
    /// from (measured over all 1558 constraint-bearing casks).
    @Test func aDeclarationWithNoParseableVersionAdmitsEveryone() {
        #expect(CaskMacOSRequirement(comparison: .atLeast, versions: ["big_sur"]).admits("26.0.0"))
        #expect(CaskMacOSRequirement(comparison: .exactly, versions: []).admits("26.0.0"))
    }
}
