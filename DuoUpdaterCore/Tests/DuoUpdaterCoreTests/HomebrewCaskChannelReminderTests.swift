import Testing
import Foundation
@testable import DuoUpdaterCore

/// The reminder for a cask brew installed whose copy the user replaced with a
/// nightly or beta: `brew` will put the stable cask over it. A reminder, not a
/// gate — `UpdateResult.replacesChannelWithStable` routes the row through the
/// existing confirmation and the update stays on offer.
///
/// The fixture is five **live catalog entries**, verbatim, from
/// `formulae.brew.sh/api/cask.json` fetched 2026-10-20, in catalog order
/// (positions 4179, 4180, 4888, 7359, 7360 of 7,798). Each is there for one
/// shape the rule has to get right:
///   - `lapce` — the case that found the gap (#1500): a standard cask, not
///     `auto_updates`, and the only Lapce cask; its nightly shares `Lapce.app`.
///   - `freelens` / `freelens@nightly` and `utm` / `utm@beta` — a standard cask
///     and its channel cask installing the SAME `.app`, neither `auto_updates`,
///     so the bundle cannot say which one brew installed and the token decides.
///
/// Mutations, each applied to the working tree and this suite run (2026-10-20);
/// the red column is what failed, not what was predicted:
///
/// | # | Mutation | Measured |
/// |---|---|---|
/// | 1 | `HomebrewCaskSource`: drop `if entry.isStandardStableCask { remote.offeredChannel = .stable }` | red: `aNightlyCopyOfAStableCaskIsReminded`, `theSameNightlyCopyUnderTheStandardCaskIs`, `aStableCopyOfAStableCaskIsNot`, `aProvenChannelCounts`, `survivesARescan` |
/// | 2 | `isStandardStableCask`: drop the `@` guard | red: `aChannelCaskIsNot`, `aVersionPinnedCaskIsSkippedToo`, `aNightlyCopyOfANightlyCaskIsNot`, `aBetaCopyOfABetaCaskIsNot` |
/// | 3 | `isStandardStableCask`: skip the `.app` name check (`true \|\| allSatisfy`) | red: `aSuffixlessCaskWhoseAppReadsAsAChannelIsNot` — and only it, which is what a backstop no live cask reaches looks like |
/// | 4 | `replacesChannelWithStable`: return `effectiveReleaseChannel` without the `.stable` check | red: `aStableCopyOfAStableCaskIsNot` |
/// | 5 | `isMajorUpgrade`: drop `\|\| replacesChannelWithStable != nil` | red: `aNightlyCopyOfAStableCaskIsReminded` |
struct HomebrewCaskChannelReminderTests {

    private static func index() throws -> CaskIndex {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/homebrew-cask-channels.json")
        return try HomebrewCaskCatalog.index(fromCatalogJSON: Data(contentsOf: url))
    }

    private static func entry(_ token: String) throws -> CaskEntry {
        let all = try index().allByAppFilename.values.flatMap { $0 }
        return try #require(all.first { $0.token == token })
    }

    private static func app(
        _ filename: String, bundleID: String, version: String, channel: ReleaseChannel
    ) -> InstalledApp {
        InstalledApp(
            name: String(filename.dropLast(4)), bundleID: bundleID, shortVersion: version,
            buildVersion: "1", path: URL(fileURLWithPath: "/Applications/\(filename)"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: channel)
    }

    /// Runs the real source over the fixture with `installed` in the Caskroom and
    /// builds the row the checker would, as an available update.
    private static func row(
        for app: InstalledApp, installed: Set<String>, provenChannel: ReleaseChannel? = nil
    ) async throws -> UpdateResult {
        let remote = try #require(try await HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: index()),
            inventory: BrewLocalInventory(installedTokens: installed),
            hostOSVersion: "27.0.0"
        ).latestVersion(for: app))
        return UpdateResult(
            app: app, remote: remote,
            status: .updateAvailable(latest: remote.displayVersion ?? "?"),
            provenChannel: provenChannel)
    }

    /// A Freelens copy as the scanner reads it: the channel comes from the
    /// version's `-nightly-` tail (`ReleaseChannel.detect` step 4), so this asks
    /// the real rule rather than asserting a channel.
    private static func freelens(version: String) -> InstalledApp {
        let channel = ReleaseChannel.detect(
            name: "Freelens", bundleID: "app.freelens.Freelens", keystoneChannel: nil, version: version)
        return app("Freelens.app", bundleID: "app.freelens.Freelens", version: version, channel: channel)
    }

    private static func lapce(_ channel: ReleaseChannel) -> InstalledApp {
        app("Lapce.app", bundleID: "io.lapce", version: "0.4.5", channel: channel)
    }

    // MARK: - Which casks are the standard stable one

    @Test func aSuffixlessCaskIsTheStandardStableOne() throws {
        #expect(try Self.entry("lapce").isStandardStableCask)
        #expect(try Self.entry("freelens").isStandardStableCask)
        #expect(try Self.entry("utm").isStandardStableCask)
    }

    /// Homebrew names an alternative channel `<token>@<channel>`. `utm@beta`
    /// installs the very `UTM.app` the stable cask does, so nothing but the token
    /// says it is a beta.
    @Test func aChannelCaskIsNot() throws {
        #expect(try !Self.entry("utm@beta").isStandardStableCask)
        #expect(try !Self.entry("freelens@nightly").isStandardStableCask)
    }

    /// Version-pinned casks carry `@` too and are skipped with the channel ones —
    /// the accepted miss `isStandardStableCask` documents. Same live fixture the
    /// macOS-constraint suite reads (`carbon-copy-cloner@6`, 2026-09-15).
    @Test func aVersionPinnedCaskIsSkippedToo() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/homebrew-cask-ccc-pair.json")
        let index = try HomebrewCaskCatalog.index(fromCatalogJSON: Data(contentsOf: url))
        let pinned = try #require(
            index.allByAppFilename.values.flatMap { $0 }.first { $0.token == "carbon-copy-cloner@6" })
        #expect(!pinned.isStandardStableCask)
    }

    /// The second check: no `@`, but its `.app` reads as a channel word. Built by
    /// hand from the real `alpha` cask (token, version and `Alpha.app` as the
    /// 2026-10-20 catalog has them) because that cask is `disabled`, which the
    /// indexer drops — no live cask the indexer keeps has this shape today, so
    /// this check is a backstop, and this is the only way to reach it.
    @Test func aSuffixlessCaskWhoseAppReadsAsAChannelIsNot() {
        let alpha = CaskEntry(
            token: "alpha", version: "9.2.3", url: nil, autoUpdates: false,
            installKind: .brew, appFilenames: ["Alpha.app"])
        #expect(!alpha.isStandardStableCask)
        let lapce = CaskEntry(
            token: "lapce", version: "0.4.6", url: nil, autoUpdates: false,
            installKind: .brew, appFilenames: ["Lapce.app"])
        #expect(lapce.isStandardStableCask)
    }

    // MARK: - The reminder on a row

    /// The case itself: `brew install --cask lapce`, then the nightly dragged
    /// over it. The update stays on offer, behind the confirmation.
    @Test func aNightlyCopyOfAStableCaskIsReminded() async throws {
        let row = try await Self.row(for: Self.lapce(.nightly), installed: ["lapce"])
        #expect(row.remote?.sourceName == "Homebrew")
        #expect(row.remote?.offeredChannel == .stable)
        #expect(row.replacesChannelWithStable == .nightly)
        #expect(row.isMajorUpgrade)
        #expect(row.hasUpdate)
    }

    /// The normal case — a stable cask over a stable copy — says nothing, and is
    /// not a major upgrade (0.4.5 → 0.4.6).
    @Test func aStableCopyOfAStableCaskIsNot() async throws {
        let row = try await Self.row(for: Self.lapce(.stable), installed: ["lapce"])
        #expect(row.remote?.offeredChannel == .stable)
        #expect(row.replacesChannelWithStable == nil)
        #expect(!row.isMajorUpgrade)
    }

    /// The other normal case: a nightly copy installed by the `@nightly` cask is
    /// exactly where it belongs.
    @Test func aNightlyCopyOfANightlyCaskIsNot() async throws {
        let freelens = Self.freelens(version: "2.0.0-0-nightly-2026-10-01")
        let row = try await Self.row(for: freelens, installed: ["freelens@nightly"])
        #expect(row.remote?.sourceIdentifier == "freelens@nightly")
        #expect(row.remote?.offeredChannel == nil)
        #expect(row.replacesChannelWithStable == nil)
    }

    /// And the same copy under the standard cask is reminded — the pair differs
    /// only in which token the Caskroom holds.
    @Test func theSameNightlyCopyUnderTheStandardCaskIs() async throws {
        let freelens = Self.freelens(version: "2.0.0-0-nightly-2026-10-01")
        let row = try await Self.row(for: freelens, installed: ["freelens"])
        #expect(row.remote?.sourceIdentifier == "freelens")
        #expect(row.replacesChannelWithStable == .nightly)
    }

    /// Same for a beta cask sharing the stable cask's `.app`.
    @Test func aBetaCopyOfABetaCaskIsNot() async throws {
        let utm = Self.app("UTM.app", bundleID: "com.utmapp.UTM", version: "4.0.0", channel: .beta)
        let row = try await Self.row(for: utm, installed: ["utm@beta"])
        #expect(row.remote?.sourceIdentifier == "utm@beta")
        #expect(row.replacesChannelWithStable == nil)
    }

    /// A channel only an earlier check proved (UTM's beta is told apart remotely)
    /// counts: it is what the row shows.
    @Test func aProvenChannelCounts() async throws {
        let utm = Self.app("UTM.app", bundleID: "com.utmapp.UTM", version: "4.0.0", channel: .stable)
        let row = try await Self.row(for: utm, installed: ["utm"], provenChannel: .beta)
        #expect(row.replacesChannelWithStable == .beta)
    }

    /// Only an available update is reminded — nothing is about to be replaced.
    @Test func noUpdateNoReminder() async throws {
        let row = try await Self.row(for: Self.lapce(.nightly), installed: ["lapce"])
        let current = UpdateResult(app: row.app, remote: row.remote, status: .upToDate)
        #expect(current.replacesChannelWithStable == nil)
    }

    /// The workbench rescans on every focus and rebuilds each row through
    /// `carriedForward`; the reminder must survive that, also when the copy
    /// changed version but is still a nightly.
    @Test func survivesARescan() async throws {
        let row = try await Self.row(for: Self.lapce(.nightly), installed: ["lapce"])
        let rescanned = Self.app("Lapce.app", bundleID: "io.lapce", version: "0.4.5.1", channel: .nightly)
        let carried = row.carriedForward(
            onto: rescanned, remote: row.remote, status: row.status, proven: nil)
        #expect(carried.replacesChannelWithStable == .nightly)
    }
}
