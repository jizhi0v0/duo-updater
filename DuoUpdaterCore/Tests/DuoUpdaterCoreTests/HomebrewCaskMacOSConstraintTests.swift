import Testing
import Foundation
@testable import DuoUpdaterCore

/// A cask's `depends_on.macos`, and which cask wins when several of them claim the
/// same `.app` filename or bundle id (issue #638). The catalog keeps them all;
/// `CaskEntry.preferred(among:hostOSVersion:)` and `HomebrewCaskSource` choose.
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
/// today. The bundle-id key has **no** such pair today — measured over all
/// `uninstall: quit:` groups, no group's first cask is excluded on host 26 or 27
/// while a later one is admitted — so the CCC pair (`>= 13`, then no constraint)
/// is the real shape available for that key, and it only bites below macOS 13.
///
/// Mutation table. Every row below was applied to a working tree and this suite
/// run (2026-09-15): all fourteen **compile** — not one is caught by the type
/// checker — and all fourteen go red. The "red" column lists the tests that
/// actually failed, not the ones predicted beforehand.
///
/// Two things this table learned the hard way, both worth keeping:
/// mutation 3 (drop the `?? entries.first` fallback) was **green** on the first
/// run, because the test meant to witness it used macOS 12 — which OnyX's `==`
/// list contains, so it never reached the fallback at all; and an earlier shape
/// of this change carried the same pick a second time inside `CaskIndex`, where
/// nothing in production read it, so its mutations were evidence about dead code.
/// A mutation that stays green is the useful one.
///
/// | # | Mutation | Measured |
/// |---|---|---|
/// | 1 | `CaskEntry.preferred`: `entries.first` (plain catalog order, the old behaviour) | red: `macOS27PrefersTheOnyXCaskThatAdmits27`, `aHostBelowTheFirstCasksFloorPicksTheLaterOne`, `withBothCasksInstalledTheHostDecides` |
/// | 2 | `CaskEntry.preferred`: `entries.last { admits } ?? entries.first` | red: `anUnconstrainedCaskDoesNotDisplaceAnAdmittedIncumbent` |
/// | 3 | `CaskEntry.preferred`: drop the `?? entries.first` fallback | red: `aHostNoCaskAdmitsFallsBackToTheFirst` |
/// | 4 | `HomebrewCaskCatalog.index`: build `CaskEntry` with `macOS: nil` | red: 6 tests |
/// | 5 | `admits`: `.exactly` returns `true` | red: `macOS27PrefersTheOnyXCaskThatAdmits27`, `onyxAdmitsMacOS26PointReleasesAndNothingNewer`, `aHostNoCaskAdmitsFallsBackToTheFirst`, `withBothCasksInstalledTheHostDecides` |
/// | 6 | `admits`: `.atLeast` uses `!= .orderedDescending` | red: `onyxBetaAdmitsMacOS27AndNothingOlder`, `anUnconstrainedCaskDoesNotDisplaceAnAdmittedIncumbent`, `aHostBelowTheFirstCasksFloorPicksTheLaterOne`, `aHostNoCaskAdmitsFallsBackToTheFirst` |
/// | 7 | `admits`: `.atMost` uses `!= .orderedAscending` (the sign reversed) | red: `atMostAdmitsOlderHostsAndRefusesNewerOnes` |
/// | 8 | `truncated`: return `version` unchanged (no truncation) | red: `atMostAdmitsOlderHostsAndRefusesNewerOnes`, `onyxAdmitsMacOS26PointReleasesAndNothingNewer` |
/// | 9 | `admits`: empty-declaration guard fails closed | red: `aDeclarationWithNoParseableVersionAdmitsEveryone` |
/// | 10 | `parse`: an unreadable `macos` object returns an empty requirement instead of `nil` | red: `anEmptyMacOSObjectIsNoConstraint` |
/// | 11 | `CaskEntry.admits`: `macOS?.admits(host) ?? false` | red: `anEmptyMacOSObjectIsNoConstraint`, `aHostBelowTheFirstCasksFloorPicksTheLaterOne` |
/// | 12 | `HomebrewCaskSource`: gate on the runnable cask only (the old single-entry provenance check) | red: `macOS27StillResolvesTheStableCaskForSomeoneWhoInstalledIt` |
/// | 13 | `HomebrewCaskSource`: take `installed.first`, dropping the host tie-break | red: `withBothCasksInstalledTheHostDecides` |
/// | 14 | `HomebrewCaskSource`: drop the provenance filter, take the runnable cask | red: `macOS27StillResolvesTheStableCaskForSomeoneWhoInstalledIt`, `neitherCaskInstalledStillDeclines` |
struct HomebrewCaskMacOSConstraintTests {

    private static func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    private static func onyxIndex() throws -> CaskIndex {
        try HomebrewCaskCatalog.index(fromCatalogJSON: fixture("homebrew-cask-onyx-pair"))
    }

    private static func cccIndex() throws -> CaskIndex {
        try HomebrewCaskCatalog.index(fromCatalogJSON: fixture("homebrew-cask-ccc-pair"))
    }

    /// The candidates for one key, in catalog order — indexing is host-independent,
    /// so there is one list per key and the host only enters when picking.
    private static func onyxCasks() throws -> [CaskEntry] {
        try #require(onyxIndex().allByAppFilename["onyx.app"])
    }

    private static func cccCasks() throws -> [CaskEntry] {
        try #require(cccIndex().allByBundleID["com.bombich.ccc"])
    }

    // MARK: - Picking among the casks that claim one key

    /// The bug in the issue: on macOS 27 the answer used to be `onyx` 5.0.4 — a
    /// build brew itself refuses to install there — because it sorts first.
    @Test func macOS27PrefersTheOnyXCaskThatAdmits27() throws {
        let entry = try #require(
            CaskEntry.preferred(among: Self.onyxCasks(), hostOSVersion: "27.0.0"))
        #expect(entry.token == "onyx@beta")
        #expect(entry.version == "5.1.0,260910")
    }

    /// The other side of the same rule: on macOS 26 the answer must stay `onyx`.
    /// Note the point release — 26.4.0 is macOS 26, and `== [… "26"]` admits it.
    @Test func macOS26PrefersTheOnyXCaskThatAdmits26() throws {
        let entry = try #require(
            CaskEntry.preferred(among: Self.onyxCasks(), hostOSVersion: "26.4.0"))
        #expect(entry.token == "onyx")
        #expect(entry.version == "5.0.4")
    }

    /// Catalog order still decides among casks the host can run: an unconstrained
    /// later cask (CCC 6) must not displace an admitted earlier one (CCC 7).
    @Test func anUnconstrainedCaskDoesNotDisplaceAnAdmittedIncumbent() throws {
        let entry = try #require(
            CaskEntry.preferred(among: Self.cccCasks(), hostOSVersion: "14.6.0"))
        #expect(entry.token == "carbon-copy-cloner")
        #expect(entry.version == "7.2,8399")
    }

    /// And when the first cask excludes the host, the pick moves on rather than
    /// answering with a cask brew would refuse. macOS 12 is below CCC 7's `>= 13`.
    @Test func aHostBelowTheFirstCasksFloorPicksTheLaterOne() throws {
        let entry = try #require(
            CaskEntry.preferred(among: Self.cccCasks(), hostOSVersion: "12.7.6"))
        #expect(entry.token == "carbon-copy-cloner@6")
        // The index itself keeps both, in catalog order, on every host.
        #expect(try Self.cccCasks().map(\.token)
            == ["carbon-copy-cloner", "carbon-copy-cloner@6"])
    }

    /// A host outside every candidate's window still gets an answer — the first —
    /// rather than a hole.
    ///
    /// The host is 16, which is in the gap OnyX's `==` list skips (11–15, then 26)
    /// and below `onyx@beta`'s floor, so **neither** cask admits it. The first
    /// version of this test used macOS 12 and passed for the wrong reason: 12 is
    /// *in* that list, so it was exercising the ordinary admitted-first path, and
    /// deleting the `?? entries.first` fallback left the whole suite green.
    @Test func aHostNoCaskAdmitsFallsBackToTheFirst() throws {
        let casks = try Self.onyxCasks()
        #expect(!casks.contains { $0.admits("16.0.0") })
        let entry = try #require(CaskEntry.preferred(among: casks, hostOSVersion: "16.0.0"))
        #expect(entry.token == "onyx")
    }

    // MARK: - The constraint itself

    @Test func onyxBetaAdmitsMacOS27AndNothingOlder() throws {
        let entry = try #require(Self.onyxCasks().last)
        let requirement = try #require(entry.macOS)
        #expect(requirement == CaskMacOSRequirement(comparison: .atLeast, versions: ["27"]))
        #expect(requirement.admits("27.0.0"))
        #expect(requirement.admits("27.1.3"))
        #expect(!requirement.admits("26.4.0"))
    }

    @Test func onyxAdmitsMacOS26PointReleasesAndNothingNewer() throws {
        let entry = try #require(Self.onyxCasks().first)
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

    /// `<=` has **zero** occurrences in the catalog (measured 2026-09-15), which is
    /// exactly why it needs a witness: with no real body exercising it, a reversed
    /// sign would sit here silently until the day a vendor ships one, and then hide
    /// that cask instead of failing loudly. Hand-built for the same reason.
    @Test func atMostAdmitsOlderHostsAndRefusesNewerOnes() {
        let ceiling = CaskMacOSRequirement(comparison: .atMost, versions: ["15"])
        #expect(ceiling.admits("14.0.0"))
        #expect(ceiling.admits("15.6.1"))   // a point release of the ceiling itself
        #expect(!ceiling.admits("26.0.0"))
    }

    /// `{"macos": {}}` is what 3445 of the catalog's 5003 `macos` keys render as
    /// (measured 2026-09-15). It means "no constraint", so it must parse to `nil`
    /// and not to an empty requirement that then decides anything.
    @Test func anEmptyMacOSObjectIsNoConstraint() throws {
        let six = try #require(Self.cccCasks().last)
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
        let catalog = HomebrewCaskCatalog(testIndex: try onyxIndex())
        return HomebrewCaskSource(
            catalog: catalog,
            inventory: BrewLocalInventory(installedTokens: installed),
            hostOSVersion: host)
    }

    /// The issue's first consequence: a user who installed 5.1.0 through
    /// `onyx@beta` used to get `.unknown`, because the index only ever offered the
    /// `onyx` token and it isn't in their Caskroom.
    ///
    /// ⚠️ **No corresponding mutation, deliberately** — it guards the composition,
    /// not a branch. On this input the three candidate rules (host preference,
    /// `installed.first`, and ignoring provenance altogether) all answer
    /// `onyx@beta`, so no mutation of the pick can single it out; it fails only if
    /// the whole path stops resolving. The rules are separated by
    /// `macOS27StillResolvesTheStableCaskForSomeoneWhoInstalledIt` (host preference
    /// vs installed) and `withBothCasksInstalledTheHostDecides` (installed-first vs
    /// host tie-break). Same shape as `ScanRowAssemblyTests`'
    /// `anUnprovenCopyFallsBackToItsBundle`.
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
