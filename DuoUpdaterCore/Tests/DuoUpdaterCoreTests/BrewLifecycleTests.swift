import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BrewLifecycle` — Homebrew's deprecate!/disable! verdict on an installed
/// formula, read from `brew info --json=v2 --installed`.
///
/// The field values are copied from four real formulae in formulae.brew.sh's
/// `formula.json` on 2026-10-08, one per shape brew distinguishes: aces_container
/// (deprecated, a disable date and a replacement), detox (deprecated, no disable
/// date), apophenia (disabled only), aescrypt-packetizer (both flags — its disable
/// date has passed). Names are fictitious (`zzfixture-*`).
///
/// Each test names the mutation it exists to catch.
@Suite struct BrewLifecycleTests {

    private static func entry(_ fields: String, name: String = "zzfixture-tool") -> [String: Any] {
        let json = #"{"name":"\#(name)","full_name":"\#(name)",\#(fields)}"#
        return try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    private static let acesContainer = #""deprecated":true,"deprecation_date":"2026-06-05","deprecation_reason":"repo_archived","deprecation_replacement_formula":"openimageio","deprecation_replacement_cask":null,"disabled":false,"disable_date":"2027-06-05","disable_reason":null,"disable_replacement_formula":null,"disable_replacement_cask":null"#
    private static let detox = #""deprecated":true,"deprecation_date":"2026-07-28","deprecation_reason":"unmaintained","deprecation_replacement_formula":null,"deprecation_replacement_cask":null,"disabled":false,"disable_date":null,"disable_reason":null,"disable_replacement_formula":null,"disable_replacement_cask":null"#
    private static let apophenia = #""deprecated":false,"deprecation_date":null,"deprecation_reason":null,"deprecation_replacement_formula":null,"deprecation_replacement_cask":null,"disabled":true,"disable_date":"2026-05-16","disable_reason":"needs `gsl` but is under an incompatible license","disable_replacement_formula":null,"disable_replacement_cask":null"#
    private static let aescrypt = #""deprecated":true,"deprecation_date":"2025-03-17","deprecation_reason":"switched to a commercial license in v4","deprecation_replacement_formula":null,"deprecation_replacement_cask":null,"disabled":true,"disable_date":"2026-03-17","disable_reason":"switched to a commercial license in v4","disable_replacement_formula":"zzfixture-free","disable_replacement_cask":null"#

    /// Mutation: read `disable_replacement_*` for a formula that isn't disabled →
    /// the replacement brew prints is lost.
    @Test func deprecatedCarriesItsReasonDateAndReplacement() {
        let l = BrewLifecycle.parse(Self.entry(Self.acesContainer))
        #expect(l == BrewLifecycle(
            stage: .deprecated, reason: "repo_archived", disableDate: "2027-06-05",
            replacementFormula: "openimageio", replacementCask: nil))
        #expect(l?.replacementCommand == "brew install --formula openimageio")
    }

    /// brew: no disable date → deprecation date `>> 12`. Mutation: drop the
    /// fallback → no date shown for the formulae that set none.
    @Test func aMissingDisableDateIsTheDeprecationDatePlusAYear() {
        #expect(BrewLifecycle.parse(Self.entry(Self.detox))?.disableDate == "2027-07-28")
        // Ruby's `Date#>>` clamps to the month's last day, and so does Calendar.
        #expect(BrewLifecycle.addingYear(to: "2024-02-29") == "2025-02-28")
        #expect(BrewLifecycle.addingYear(to: "not a date") == nil)
    }

    @Test func disabledOnlyIsDisabled() {
        let l = BrewLifecycle.parse(Self.entry(Self.apophenia))
        #expect(l?.stage == .disabled)
        #expect(l?.reason == "needs `gsl` but is under an incompatible license")
        #expect(l?.disableDate == "2026-05-16")
    }

    /// Both flags: brew's `DeprecateDisable.type` says deprecated (the installer only
    /// warns), while the replacement comes from the `disable_` fields. Mutation:
    /// check `disabled` first for the stage → this reads as refusing to upgrade,
    /// which brew doesn't do.
    @Test func bothFlagsIsDeprecatedWithTheDisableReplacement() {
        let l = BrewLifecycle.parse(Self.entry(Self.aescrypt))
        #expect(l?.stage == .deprecated)
        #expect(l?.reason == "switched to a commercial license in v4")
        #expect(l?.replacementFormula == "zzfixture-free")
    }

    @Test func neitherFlagIsNil() {
        #expect(BrewLifecycle.parse(Self.entry(#""deprecated":false,"disabled":false"#)) == nil)
    }

    /// `DeprecateDisable.replacement_with_type`. Mutation: always `--formula` →
    /// a cask replacement installs nothing.
    @Test func replacementCommandMatchesBrews() {
        func command(_ f: String?, _ c: String?) -> String? {
            BrewLifecycle(stage: .deprecated, reason: nil, disableDate: nil,
                          replacementFormula: f, replacementCask: c).replacementCommand
        }
        #expect(command("zzfixture-a", "zzfixture-a") == "brew install zzfixture-a")
        #expect(command("zzfixture-a", nil) == "brew install --formula zzfixture-a")
        #expect(command(nil, "zzfixture-b") == "brew install --cask zzfixture-b")
        #expect(command(nil, nil) == nil)
    }

    /// Keyed by `full_name`, the name `brew leaves` prints. Mutation: key by `name`
    /// → a tap formula's lifecycle never reaches its tap-qualified leaf.
    @Test func lifecyclesAreKeyedByFullName() {
        let info = Data(#"""
        {"formulae":[
          {"name":"zzfixture-tool","full_name":"zzfixture-org/tap/zzfixture-tool",\#(Self.detox)},
          {"name":"zzfixture-fine","full_name":"zzfixture-fine","deprecated":false,"disabled":false}
        ],"casks":[]}
        """#.utf8)
        let map = BrewFormulaService.lifecycles(installedInfo: info)
        #expect(Array(map.keys) == ["zzfixture-org/tap/zzfixture-tool"])
        #expect(BrewFormulaService.lifecycles(installedInfo: Data()).isEmpty)
    }

    /// Mutation: rebuild the formula in `merge` without its lifecycle → the second
    /// phase of every refresh wipes it.
    @Test func mergeKeepsTheLifecycle() {
        let lifecycle = BrewLifecycle.parse(Self.entry(Self.detox))
        var leaf = BrewInstalledFormula(name: "zzfixture-tool", installedVersion: "1.0", availableVersion: nil)
        leaf.lifecycle = lifecycle
        let merged = BrewFormulaService.merge(
            [leaf], outdated: [BrewOutdatedFormula(name: "zzfixture-tool", installedVersion: "1.0", currentVersion: "1.1")])
        #expect(merged.first?.lifecycle == lifecycle)
        #expect(merged.first?.availableVersion == "1.1")
    }

    // MARK: - Casks

    /// `info --installed` cask entries trimmed from real ones (2026-10-08): an `app`
    /// artifact records where it landed in `target` — renamed or not, as with
    /// thorium's `{"target": "Thorium Browser.app"}` — and a CLI cask has `binary`
    /// artifacts only. Flags and reasons from cask.json: ace-link (disabled,
    /// fails_gatekeeper_check), chromedriver (same, binary only), app-fair
    /// (deprecated, discontinued).
    private static let caskInfo = Data(#"""
    {"formulae":[],"casks":[
      {"token":"zzfixture-gui","installed":"2.1.0","deprecated":false,"disabled":true,"disable_date":"2026-09-01","disable_reason":"fails_gatekeeper_check",
       "artifacts":[{"app":["Thorium.app",{"target":"ZZFixture Browser.app"}],"target":"/Applications/ZZFixture Browser.app"},{"zap":[{"trash":"~/x"}]}]},
      {"token":"zzfixture-cli","installed":"152.0","deprecated":false,"disabled":true,"disable_date":"2026-09-01","disable_reason":"fails_gatekeeper_check",
       "artifacts":[{"binary":["zzfixture"],"target":"/opt/homebrew/bin/zzfixture"}]},
      {"token":"zzfixture-pkg","installed":"1.0","deprecated":true,"deprecation_date":"2026-01-01","deprecation_reason":"discontinued","disabled":false,
       "artifacts":[{"pkg":["Install.pkg"]}]},
      {"token":"zzfixture-fine","installed":"1.0","deprecated":false,"disabled":false,
       "artifacts":[{"app":["Fine.app"],"target":"/Applications/Fine.app"}]}
    ]}
    """#.utf8)

    /// Mutation: read the artifact's first element (`Thorium.app`) instead of its
    /// `target` → a renamed app's row never matches. Mutation: drop the
    /// `installsAnApp` seam → a `.pkg` cask's app gets a second, app-less row.
    @Test func caskLifecyclesCarryAppTargetsAndWhetherAnAppIsInstalled() {
        let casks = BrewFormulaService.caskLifecycles(
            installedInfo: Self.caskInfo, installsAnApp: { $0 == "zzfixture-pkg" })
        #expect(casks.map(\.token) == ["zzfixture-cli", "zzfixture-gui", "zzfixture-pkg"])
        #expect(casks.map(\.appPaths) == [[], ["/Applications/ZZFixture Browser.app"], []])
        #expect(casks.map(\.installsAnApp) == [false, true, true])
        #expect(casks.map(\.installedVersion) == ["152.0", "2.1.0", "1.0"])
        #expect(casks.map(\.lifecycle.stage) == [.disabled, .disabled, .deprecated])
        #expect(casks.first?.lifecycle.reason == "fails_gatekeeper_check")
        #expect(BrewFormulaService.caskLifecycles(installedInfo: Data(), installsAnApp: { _ in false }).isEmpty)
    }

    /// Through the service: the report carries the lifecycles from the same
    /// `info` read the unchecked packages use.
    @Test func serviceReportsLifecycles() async {
        let service = BrewFormulaService(executor: { arguments in
            switch arguments {
            case ["list", "--formula", "--full-name"]: return (0, Data("zzfixture-tool\n".utf8))
            case ["list", "--formula", "--versions"]: return (0, Data("zzfixture-tool 1.0\n".utf8))
            case ["info", "--json=v2", "--installed"]:
                return (0, Data(#"{"formulae":[{"name":"zzfixture-tool","full_name":"zzfixture-tool",\#(Self.apophenia)}],"casks":[]}"#.utf8))
            case ["formulae"]: return (0, Data("zzfixture-tool\n".utf8))
            case ["casks"]: return (0, Data())
            default: return (1, Data())
            }
        })
        let report = await service.installedReport()
        #expect(report.unchecked.isEmpty)
        #expect(report.lifecycles["zzfixture-tool"]?.stage == .disabled)
    }
}
