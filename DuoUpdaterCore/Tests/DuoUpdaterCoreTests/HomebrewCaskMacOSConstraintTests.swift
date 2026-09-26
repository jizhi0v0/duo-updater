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
/// run (2026-09-15): every one **compiles** — not one is caught by the type
/// checker — and every one goes red (row 6 is retired, not applied). The "red"
/// column lists the tests that actually failed, not the ones predicted
/// beforehand.
///
/// Rows 16–20 came with routing `>=` through `SignatureVerifier.canRun`, and were
/// run with `--filter` over this suite plus `OSFloorIsLoadBearingTests`,
/// `InstallOSFloorGateTests` and `SparkleMaximumSystemVersionTests`, so their red
/// column can name tests outside this file. Rows 4, 5, 7, 8 and 9 — the ones
/// mutating `CaskMacOSRequirement.admits`, `truncated`, or the `macOS:` the
/// indexer passes — were re-run on that code with the same filter and say so.
/// Rows 1–3 and 10–15 (including `parse` and `CaskEntry.admits`) were not.
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
/// | 4 | `HomebrewCaskCatalog.index`: build `CaskEntry` with `macOS: nil` | red: 7 tests (re-run: the original 6, plus `atLeastAnswersWhatCanRunAnswers` via its non-empty-fixture guard) |
/// | 5 | `admits`: `.exactly` returns `true` | red: `macOS27PrefersTheOnyXCaskThatAdmits27`, `onyxAdmitsMacOS26PointReleasesAndNothingNewer`, `aHostNoCaskAdmitsFallsBackToTheFirst`, `withBothCasksInstalledTheHostDecides`, `theHostTieBreakRunsOverInstalledCasksOnly` (re-run; that last test postdates the first measurement) |
/// | 6 | *Retired.* `admits`: `.atLeast` uses `!= .orderedDescending` — the comparison it reversed no longer exists; row 20 is the same mutation on the `canRun` call | (was red: `onyxBetaAdmitsMacOS27AndNothingOlder`, `anUnconstrainedCaskDoesNotDisplaceAnAdmittedIncumbent`, `aHostBelowTheFirstCasksFloorPicksTheLaterOne`, `aHostNoCaskAdmitsFallsBackToTheFirst`) |
/// | 7 | `admits`: `.atMost` uses `!= .orderedAscending` (the sign reversed) | red: `atMostAdmitsOlderHostsAndRefusesNewerOnes` (re-run, unchanged) |
/// | 8 | `truncated`: return `version` unchanged (no truncation) — now reaches `==`/`<=` only | red: `atMostAdmitsOlderHostsAndRefusesNewerOnes`, `onyxAdmitsMacOS26PointReleasesAndNothingNewer` (re-run, unchanged) |
/// | 9 | `admits`: empty-declaration guard fails closed | red: `aDeclarationWithNoParseableVersionAdmitsEveryone` (re-run, unchanged) |
/// | 10 | `parse`: an unreadable `macos` object returns an empty requirement instead of `nil` | red: `anEmptyMacOSObjectIsNoConstraint` |
/// | 11 | `CaskEntry.admits`: `macOS?.admits(host) ?? false` | red: `anEmptyMacOSObjectIsNoConstraint`, `aHostBelowTheFirstCasksFloorPicksTheLaterOne` |
/// | 12 | `HomebrewCaskSource`: gate on the runnable cask only (the old single-entry provenance check) | red: `macOS27StillResolvesTheStableCaskForSomeoneWhoInstalledIt` |
/// | 13 | `HomebrewCaskSource`: take `installed.first`, dropping the host tie-break | red: `withBothCasksInstalledTheHostDecides`, `theHostTieBreakRunsOverInstalledCasksOnly` (re-measured after row 15) |
/// | 14 | `HomebrewCaskSource`: drop the provenance filter, take the runnable cask | red: `macOS27StillResolvesTheStableCaskForSomeoneWhoInstalledIt`, `neitherCaskInstalledStillDeclines` |
/// | 15 | `HomebrewCaskSource`: host preference over every candidate, then `installed.first` (added after review, measured on the pre-fix code) | red: `theHostTieBreakRunsOverInstalledCasksOnly` |
/// | 16 | `admits`: `.atLeast` back to the old truncate-then-`VersionComparator.compare` | red: `atLeastAnswersWhatCanRunAnswers`, `aFloorWrittenWithADashAdmitsALaterPointRelease` |
/// | 17 | `admits`: `.atLeast` off by one — `canRun(…) && compare(host, floor) != .orderedSame`, refusing the floor itself | red: `atLeastAnswersWhatCanRunAnswers`, `macOS27PrefersTheOnyXCaskThatAdmits27`, `onyxBetaAdmitsMacOS27AndNothingOlder`, `theHostTieBreakRunsOverInstalledCasksOnly`, `withBothCasksInstalledTheHostDecides` |
/// | 18 | `admits`: `.atLeast` drops `contains`, asking `canRun` about `declared[0]` only | red: `atLeastAnswersWhatCanRunAnswers` (its multi-entry half — no fixture has a second `>=` entry) |
/// | 19 | `SignatureVerifier.canRun` itself: `!= .orderedAscending` → `== .orderedDescending` | **`atLeastAnswersWhatCanRunAnswers` stays green**, by construction (both sides move). Red elsewhere: `macOS27PrefersTheOnyXCaskThatAdmits27`, `onyxBetaAdmitsMacOS27AndNothingOlder`, `theHostTieBreakRunsOverInstalledCasksOnly`, `withBothCasksInstalledTheHostDecides`, and in the other suites `aFloorAtOrBelowTheHostIsRunnable`, `aPkgPayloadFloorAboveThisMacIsRefused`, `noAppAlreadyInstalledOnThisMacWouldBeRefused`, `aProbeRecipesFloorStillGates`, `aMacBelowTheRCsFloorIsOfferedTheNewestRUNNABLEBuild`, `theXcodeRemoteCarriesTheOfferedReleasesFloor` |
/// | 20 | `admits`: `.atLeast` negated — `!declared.contains { canRun(…) }` | red: `atLeastAnswersWhatCanRunAnswers`, `aFloorWrittenWithADashAdmitsALaterPointRelease`, `aHostBelowTheFirstCasksFloorPicksTheLaterOne`, `aHostNoCaskAdmitsFallsBackToTheFirst`, `anUnconstrainedCaskDoesNotDisplaceAnAdmittedIncumbent`, `macOS27PrefersTheOnyXCaskThatAdmits27`, `onyxBetaAdmitsMacOS27AndNothingOlder`, `theHostTieBreakRunsOverInstalledCasksOnly`, `withBothCasksInstalledTheHostDecides` |
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

    /// The host breaks the tie among the casks that are INSTALLED, not among every
    /// candidate. The OnyX pair cannot tell those apart — with both installed, the
    /// two sets are the same — so this needs a third cask that the host prefers but
    /// the Caskroom does not hold, listed first. Hand-built for that reason; the
    /// catalog has no such triple.
    ///
    /// Mutation (row 15): compute the preference over `candidates` and fall back to
    /// `installed.first` — the shape this shipped with in review. It answers
    /// `zzfixture-b`, the installed cask this Mac cannot run.
    @Test func theHostTieBreakRunsOverInstalledCasksOnly() async throws {
        func cask(_ token: String, _ requirement: CaskMacOSRequirement) -> CaskEntry {
            CaskEntry(token: token, version: "1.0", url: nil, autoUpdates: false,
                      installKind: .brew, macOS: requirement)
        }
        let at27 = CaskMacOSRequirement(comparison: .atLeast, versions: ["27"])
        let only26 = CaskMacOSRequirement(comparison: .exactly, versions: ["26"])
        let casks = [
            cask("zzfixture-a", at27),    // host prefers it; not installed
            cask("zzfixture-b", only26),  // installed; this Mac can't run it
            cask("zzfixture-c", at27),    // installed; this Mac can run it
        ]
        let index = CaskIndex(allByAppFilename: ["onyx.app": casks], allByBundleID: [:])
        let remote = try await HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: index),
            inventory: BrewLocalInventory(installedTokens: ["zzfixture-b", "zzfixture-c"]),
            hostOSVersion: "27.0.0"
        ).latestVersion(for: Self.onyxApp())
        #expect(remote?.sourceIdentifier == "zzfixture-c")
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

    // MARK: - `>=` is a floor, so it answers what gate 6 answers

    /// Every `>=` value the two fixtures declare, read back through the indexer
    /// rather than typed out, so a refreshed fixture with a different floor is
    /// covered without anyone editing a list here.
    private static func fixtureFloors() throws -> [String] {
        try (onyxCasks() + cccCasks())
            .compactMap(\.macOS)
            .filter { $0.comparison == .atLeast }
            .flatMap(\.versions)
    }

    /// Not in any catalog today (every live `>=` value is a bare major), so these
    /// are hand-built: the separators `VersionComparator` splits on besides `.`,
    /// which is exactly where the old truncate-then-compare disagreed with
    /// `canRun`, plus a real vendor floor spelled with text (Alcove's).
    private static let edgeFloors = [
        "13-1", "13_1", "13+1", "13 1", "13.0-1", "26.0_1", "13.1", "10.15", "15 Sequoia",
    ]

    /// Numeric hosts only — `x`, `x.y`, `x.y.z` — spanning one major either side of
    /// every floor. Numeric because production's host is always
    /// `HostOS.numericVersion()`. The pre-`canRun` code answered differently in two
    /// shapes: a separator floor on a numeric host (`edgeFloors`, pinned below),
    /// and a host with trailing text — which cannot occur, so it is not generated.
    private static func hosts(around floors: [String]) -> [String] {
        let majors = floors.compactMap { Int($0.prefix { $0.isNumber }) }
        guard let low = majors.min(), let high = majors.max() else { return [] }
        return (low - 1...high + 1).flatMap { major in
            ["\(major)"] + (0...3).flatMap { minor in
                ["\(major).\(minor)"] + (0...2).map { "\(major).\(minor).\($0)" }
            }
        }
    }

    /// The invariant `HostOS` states: a cask's `>=` and install-time gate 6 cannot
    /// disagree about the same pair of versions. Asserted as equality with
    /// `SignatureVerifier.canRun` itself, not as a table of expected booleans, so
    /// it goes red on divergence rather than on whatever the table's author
    /// believed the answer was.
    ///
    /// ⚠️ Blind by construction to a bug inside `canRun`: both sides would move
    /// together (measured, mutation 19). That half is `InstallOSFloorGateTests`'
    /// and `onyxBetaAdmitsMacOS27AndNothingOlder`'s job.
    @Test func atLeastAnswersWhatCanRunAnswers() throws {
        let fixtureFloors = try Self.fixtureFloors()
        // Without this the loop below is vacuous when the indexer stops reading
        // `depends_on.macos` — the fixtures would contribute nothing.
        try #require(!fixtureFloors.isEmpty)
        let floors = fixtureFloors + Self.edgeFloors
        let hosts = Self.hosts(around: floors)

        var mismatches: [String] = []
        for floor in floors {
            let requirement = CaskMacOSRequirement(comparison: .atLeast, versions: [floor])
            var outcomes = Set<Bool>()
            for host in hosts {
                let gate6 = SignatureVerifier.canRun(minimumSystemVersion: floor, on: host)
                outcomes.insert(gate6)
                if requirement.admits(host) != gate6 {
                    mismatches.append(">= \(floor) on \(host): admits \(!gate6), canRun \(gate6)")
                }
            }
            // The grid must straddle each floor, or agreement proves nothing.
            #expect(outcomes == [true, false], "hosts do not straddle \(floor)")
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) disagree, e.g. \(mismatches.prefix(5))")

        // A multi-entry `>=` list (none exists today) admits a host any one of its
        // entries admits, in either order.
        var listMismatches: [String] = []
        for a in floors {
            for b in floors where a != b {
                let requirement = CaskMacOSRequirement(comparison: .atLeast, versions: [a, b])
                for host in hosts {
                    let expected = SignatureVerifier.canRun(minimumSystemVersion: a, on: host)
                        || SignatureVerifier.canRun(minimumSystemVersion: b, on: host)
                    if requirement.admits(host) != expected {
                        listMismatches.append(">= [\(a), \(b)] on \(host)")
                    }
                }
            }
        }
        #expect(listMismatches.isEmpty,
                "\(listMismatches.count) disagree, e.g. \(listMismatches.prefix(5))")
    }

    /// The one answer routing `>=` through `canRun` changed on a host production
    /// can produce. The old code truncated the host by `.`-separated components
    /// (one, for `"13-1"`) while `VersionComparator` also splits on `-`, so 13.2.0
    /// became `"13"`, compared below `[13, 1]`, and was refused. Gate 6 admits it,
    /// and gate 6 is what the install would ask.
    @Test func aFloorWrittenWithADashAdmitsALaterPointRelease() {
        let floor = CaskMacOSRequirement(comparison: .atLeast, versions: ["13-1"])
        #expect(floor.admits("13.2.0"))
        #expect(!floor.admits("13.0.0"))
    }
}
