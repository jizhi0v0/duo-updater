import Testing
import Foundation
@testable import DuoUpdaterCore

/// A disabled cask is one brew will not update, so the index drops it and a
/// brew-installed app whose cask is disabled falls through to the next source
/// instead of being offered a one-click `brew install --cask --force` that brew
/// then refuses. Deprecated casks stay: brew only warns about those.
///
/// Fixture: `Fixtures/homebrew-cask-disabled.json`, six entries copied verbatim
/// from `https://formulae.brew.sh/api/cask.json` on 2026-09-26 (`analytics`
/// dropped), in catalog order:
///
/// | token | `disabled` | `deprecated` | `disable_date` | indexed? |
/// |---|---|---|---|---|
/// | gauntlet | false | true | — | yes — brew warns and installs |
/// | keepassxc | false | false | — | yes |
/// | keepassxc@snapshot | true | false | 2026-09-01 | no — same `KeePassXC.app` and bundle id as `keepassxc` |
/// | mjolnir | false | true | 2026-11-30 (future) | yes — deprecated until that date |
/// | sleipnir | true | false | 2026-09-01 | no — `brew install` raises |
/// | unlox | true | true | 2026-03-02 | no — `brew install` only warns, `brew upgrade` skips it |
///
/// Mutation table, each applied to the guard in `index(fromCatalogJSON:)` and
/// this suite run (2026-09-26); the red column is what actually failed:
///
/// | # | Mutation | Measured |
/// |---|---|---|
/// | 1 | delete the `disabled` guard | red: `aDisabledCaskIsNotIndexed`, `aCaskBothDisabledAndDeprecatedIsNotIndexed`, `aDisabledChannelCaskLeavesItsSiblingAlone`, `aBrewInstalledAppOfADisabledCaskFallsThrough` |
/// | 2 | brew install's predicate: drop only `disabled && !deprecated` | red: `aCaskBothDisabledAndDeprecatedIsNotIndexed` |
/// | 3 | also drop `deprecated == true` | red: `aDeprecatedCaskIsStillIndexed`, `aCaskDisabledOnlyInTheFutureIsStillIndexed` |
/// | 4 | drop on `disable_date` present instead of `disabled` | red: `aCaskDisabledOnlyInTheFutureIsStillIndexed` |
struct HomebrewCaskDisabledTests {

    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/homebrew-cask-disabled.json")
    }

    private static func index() throws -> CaskIndex {
        try HomebrewCaskCatalog.index(fromCatalogJSON: Data(contentsOf: fixtureURL))
    }

    private static func tokens(forAppFilename filename: String) throws -> [String]? {
        try index().allByAppFilename[filename.lowercased()]?.map(\.token)
    }

    /// The tests below assert absences, which a fixture refresh that lost the
    /// flags would satisfy for free. Pin the shapes they depend on.
    @Test func theFixtureCarriesEachShape() throws {
        let casks = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixtureURL))
                as? [[String: Any]])
        func flags(_ token: String) -> (Bool?, Bool?, String?) {
            let cask = casks.first { $0["token"] as? String == token }
            return (cask?["disabled"] as? Bool, cask?["deprecated"] as? Bool,
                    cask?["disable_date"] as? String)
        }
        #expect(flags("sleipnir") == (true, false, "2026-09-01"))
        #expect(flags("unlox") == (true, true, "2026-03-02"))
        #expect(flags("gauntlet") == (false, true, nil))
        #expect(flags("mjolnir") == (false, true, "2026-11-30"))
        #expect(flags("keepassxc") == (false, false, nil))
        #expect(flags("keepassxc@snapshot") == (true, false, "2026-09-01"))
    }

    @Test func aDisabledCaskIsNotIndexed() throws {
        #expect(try Self.tokens(forAppFilename: "Sleipnir.app") == nil)
    }

    /// brew's `check_deprecate_disable` asks `deprecated?` first, so
    /// `brew install --cask --force unlox` only warns — but `brew upgrade` skips
    /// every disabled cask, and brew documents disabled as "cannot be used".
    @Test func aCaskBothDisabledAndDeprecatedIsNotIndexed() throws {
        #expect(try Self.tokens(forAppFilename: "Unlox.app") == nil)
    }

    @Test func aDeprecatedCaskIsStillIndexed() throws {
        #expect(try Self.tokens(forAppFilename: "Gauntlet.app") == ["gauntlet"])
    }

    /// `disable!` with a future date is a deprecation until that date; the
    /// catalog says `disabled: false` and brew installs it.
    @Test func aCaskDisabledOnlyInTheFutureIsStillIndexed() throws {
        #expect(try Self.tokens(forAppFilename: "Mjolnir.app") == ["mjolnir"])
    }

    @Test func aDisabledChannelCaskLeavesItsSiblingAlone() throws {
        let index = try Self.index()
        #expect(index.allByAppFilename["keepassxc.app"]?.map(\.token) == ["keepassxc"])
        #expect(index.allByBundleID["org.keepassxc.keepassxc"]?.map(\.token) == ["keepassxc"])
    }

    /// End to end through the source: someone who brew-installed the disabled
    /// `keepassxc@snapshot` gets no Homebrew answer (the row falls through to
    /// the next source), while someone on `keepassxc` still does.
    @Test func aBrewInstalledAppOfADisabledCaskFallsThrough() async throws {
        let path = "/Applications/ZZFixture-disabled/KeePassXC.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        let app = InstalledApp(
            name: "KeePassXC", bundleID: "org.keepassxc.keepassxc",
            shortVersion: "2.7.0", buildVersion: nil, path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil)
        func source(installed token: String) throws -> HomebrewCaskSource {
            HomebrewCaskSource(
                catalog: HomebrewCaskCatalog(testIndex: try Self.index()),
                inventory: BrewLocalInventory(installedTokens: [token]),
                hostOSVersion: "26.0")
        }

        #expect(try await source(installed: "keepassxc@snapshot").latestVersion(for: app) == nil)

        let stable = try #require(
            try await source(installed: "keepassxc").latestVersion(for: app))
        #expect(stable.sourceIdentifier == "keepassxc")
        #expect(stable.shortVersion == "2.7.12")
    }
}
