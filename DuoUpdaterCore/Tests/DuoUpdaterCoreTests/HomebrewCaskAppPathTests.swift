import Testing
import Foundation
@testable import DuoUpdaterCore

/// The app-filename key is the name brew installs the `.app` **under**, not the
/// artifact string: the target's last component when the artifact has one, else
/// the source's (`Cask::Artifact::Relocated#target`). Until this suite the whole
/// source string was the key, so `j9.7/jbrk.app` could never equal an installed
/// `jbrk.app`, and `Telegram.app → Telegram Desktop.app` was filed under the name
/// it is installed *away from*.
///
/// The fixture is 11 casks cut from the live `formulae.brew.sh/api/cask.json`,
/// fetched 2026-09-26, verbatim and in catalog order (positions 139 … 7077):
/// nested sources (`j`, `omegat@latest` with its `//`, `box-tools`), relative,
/// absolute and `~` targets (`telegram-desktop`, `ftdi-vcp-driver`,
/// `box-tools`), and the two pairs whose candidate lists this change moves.
/// Counts over the whole catalog: `docs/engine-notes/homebrew-cask-catalog.md` §5.
///
/// Mutation table. Each row was applied to `appFilenames(in:)` and run with
/// `--filter HomebrewCask` on 2026-09-26, which covers this suite and the two
/// existing ones. Every row compiles and every row goes red. The "red" column
/// lists the tests that actually failed.
///
/// | # | Mutation | Measured |
/// |---|---|---|
/// | 1 | The old rule: every string in the artifact ending in `.app`, verbatim | red: all 7 tests in this suite |
/// | 2 | Ignore the target; key by the source's last component | red: `aTargetReplacesTheSourceName`, `aTargetedCaskNoLongerAdoptsTheAppAtItsSourceName`, `absoluteAndHomeTargetsAreKeyedByTheirLastComponent` |
/// | 3 | Take the target verbatim (no last component) | red: `absoluteAndHomeTargetsAreKeyedByTheirLastComponent` |
/// | 4 | Take the source verbatim when there is no target | red: `aNestedSourceIsKeyedByItsLastComponent`, `aNestedAppResolvesToItsCask`, `ownerCaskStillDecidesWhenANewCollisionAppears`, `anEmptyTargetFallsBackToTheSourceName` |
/// | 5 | Key by both the source's and the target's last components | red: `aTargetReplacesTheSourceName`, `aTargetedCaskNoLongerAdoptsTheAppAtItsSourceName`, `absoluteAndHomeTargetsAreKeyedByTheirLastComponent` |
/// | 6 | Drop the empty-target guard (`.first` instead of `.first { !$0.isEmpty }`) | red: `anEmptyTargetFallsBackToTheSourceName` only. It was **green** before that hand-built test existed, because no live cask has an empty target |
struct HomebrewCaskAppPathTests {

    private static func index() throws -> CaskIndex {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/homebrew-cask-app-paths.json")
        return try HomebrewCaskCatalog.index(fromCatalogJSON: Data(contentsOf: url))
    }

    private static func tokens(_ key: String) throws -> [String]? {
        try index().allByAppFilename[key]?.map(\.token)
    }

    /// A path that does not exist, like `HomebrewCaskMacOSConstraintTests.onyxApp`:
    /// only `lastPathComponent` is read, and a real `/Applications` path would put
    /// the answer in the hands of whatever this Mac has installed.
    private static func app(_ filename: String) -> InstalledApp {
        let path = "/Applications/ZZFixture-app-paths/\(filename)"
        #expect(!FileManager.default.fileExists(atPath: path))
        return InstalledApp(
            name: (filename as NSString).deletingPathExtension, bundleID: nil,
            shortVersion: "0.1", buildVersion: nil, path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil)
    }

    private static func source(installed: Set<String>) throws -> HomebrewCaskSource {
        HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: try index()),
            inventory: BrewLocalInventory(installedTokens: installed),
            hostOSVersion: "26.4.0")
    }

    // MARK: - The index

    /// `"app": ["j9.7/jbrk.app"]` installs `/Applications/jbrk.app`; the directory
    /// inside the download is not part of the name.
    @Test func aNestedSourceIsKeyedByItsLastComponent() throws {
        for name in ["jbrk.app", "jqt.app", "jcon.app"] {
            #expect(try Self.tokens(name) == ["j"], "\(name)")
        }
        #expect(try Self.tokens("j9.7/jbrk.app") == nil)
    }

    /// `"Telegram.app", {"target": "Telegram Desktop.app"}` installs
    /// `Telegram Desktop.app`. The source name must not be a key as well: that is
    /// where the *other* Telegram (the `telegram` cask) lives.
    @Test func aTargetReplacesTheSourceName() throws {
        #expect(try Self.tokens("telegram desktop.app")
            == ["telegram-desktop", "telegram-desktop@beta"])
        #expect(try Self.tokens("telegram.app") == ["telegram", "telegram@beta"])
    }

    /// Absolute and `~` targets: the directory brew moves to is not part of the
    /// name either. `box-tools` has a nested source *and* a `~` target, so it also
    /// pins that the target wins over the source's last component (the two agree
    /// here — it is `ftdi-vcp-driver`, whose source name carries a version, that
    /// tells them apart).
    @Test func absoluteAndHomeTargetsAreKeyedByTheirLastComponent() throws {
        #expect(try Self.tokens("ftdiusbserialdextinstaller.app") == ["ftdi-vcp-driver"])
        #expect(try Self.tokens("ftdiusbserialdextinstaller_1_5_0.app") == nil)
        for name in ["box device trust.app", "box edit.app",
                     "box local com server.app", "box tools custom apps.app"] {
            #expect(try Self.tokens(name) == ["box-tools"], "\(name)")
        }
    }

    /// `target: ""` installs under the source's name (`@target_string.presence ||
    /// source.basename`), and the API can carry one: it serializes `to_args`, i.e.
    /// `@dsl_args.compact_blank`, and `{target: ""}` is not blank. Hand-built —
    /// none of the 64 live targets is empty (§5), so no real body has this shape.
    @Test func anEmptyTargetFallsBackToTheSourceName() throws {
        let json = #"[{"token": "zzfixture", "version": "1.0", "artifacts": [{"app": ["Dir/Foo.app", {"target": ""}]}]}]"#
        let index = try HomebrewCaskCatalog.index(fromCatalogJSON: Data(json.utf8))
        #expect(index.allByAppFilename["foo.app"]?.map(\.token) == ["zzfixture"])
    }

    // MARK: - Through the source, where the provenance gate decides

    /// The reported shape end to end: a brew-installed `jqt.app` used to find no
    /// cask at all (and `j` declares no bundle id to fall back on).
    @Test func aNestedAppResolvesToItsCask() async throws {
        let remote = try await Self.source(installed: ["j"]).latestVersion(for: Self.app("jqt.app"))
        #expect(remote?.sourceIdentifier == "j")
        #expect(remote?.shortVersion == "9.7.1")
    }

    /// `omegat@latest`'s source is `OmegaT_5.7.1_Beta_Mac_Notarized//OmegaT.app`,
    /// so fixing the key makes `OmegaT.app` newly claimed by two casks. Both are
    /// kept (§2) and the Caskroom picks — in each direction.
    @Test func ownerCaskStillDecidesWhenANewCollisionAppears() async throws {
        #expect(try Self.tokens("omegat.app") == ["omegat", "omegat@latest"])
        let beta = try await Self.source(installed: ["omegat@latest"])
            .latestVersion(for: Self.app("OmegaT.app"))
        #expect(beta?.sourceIdentifier == "omegat@latest")
        #expect(beta?.shortVersion == "5.7.1")
        let stable = try await Self.source(installed: ["omegat"])
            .latestVersion(for: Self.app("OmegaT.app"))
        #expect(stable?.sourceIdentifier == "omegat")
    }

    /// `thorium` is Thorium Reader at `Thorium.app`; `alex313031-thorium` is a
    /// browser whose `Thorium.app` brew installs as `Thorium Browser.app`. Keyed by
    /// source, a Mac with the browser brew-installed passed the provenance gate for
    /// *Reader* and was offered the browser's M138 build. Keyed by the installed
    /// name, Reader is not adopted, and the browser's own row resolves.
    @Test func aTargetedCaskNoLongerAdoptsTheAppAtItsSourceName() async throws {
        let source = try Self.source(installed: ["alex313031-thorium"])
        let reader = try await source.latestVersion(for: Self.app("Thorium.app"))
        #expect(reader == nil)
        let browser = try await source.latestVersion(for: Self.app("Thorium Browser.app"))
        #expect(browser?.sourceIdentifier == "alex313031-thorium")
        #expect(browser?.shortVersion == "M138.0.7204.303")
    }
}
