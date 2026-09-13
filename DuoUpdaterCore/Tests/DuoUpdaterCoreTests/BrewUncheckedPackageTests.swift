import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BrewFormulaService.uncheckedPackages()` — installed third-party-tap packages
/// brew didn't read from their tap (see `BrewUncheckedPackage`).
///
/// The JSON shapes below are trimmed from real output measured 2026-09-13 on
/// Homebrew 7.0.0: an untrusted tap formula is absent from
/// `info --json=v2 --installed`; an untrusted cask is present with a bare
/// `full_token` and `"tap": null`, while every cask read from its tap or the API
/// has `tap` set. Names are fictitious (`zzfixture-*`), and the cask receipt read
/// is injected — only `theReceiptReaderFindsSourceTap` touches the disk, in a temp
/// Caskroom it builds itself (CLAUDE.md "测试不能问宿主").
///
/// Each test names the mutation it exists to catch.
@Suite struct BrewUncheckedPackageTests {

    private static func info(formulae: String = "", casks: String = "") -> Data {
        Data(#"{"formulae":[\#(formulae)],"casks":[\#(casks)]}"#.utf8)
    }

    private static let noReceipt: @Sendable (String) -> String? = { _ in nil }
    private static let noApp: @Sendable (String) -> Bool = { _ in false }

    // MARK: - Formulae

    /// Mutation: drop the formula loop (or its `where`) → nothing reported.
    @Test func aTapFormulaMissingFromInfoIsReportedWithItsRackVersion() {
        let result = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: ["zzfixture-org/tap/zzfixture-tool"],
            installedInfo: Self.info(),
            formulaVersions: ["zzfixture-tool": "1.3.14"],
            caskReceiptTap: Self.noReceipt,
            caskInstallsAnApp: Self.noApp)
        #expect(result == [BrewUncheckedPackage(
            fullName: "zzfixture-org/tap/zzfixture-tool", kind: .formula,
            installedVersion: "1.3.14", reason: .unreadable)])
        #expect(result.first?.name == "zzfixture-tool")
        #expect(result.first?.tap == "zzfixture-org/tap")
    }

    /// Mutation: drop the `loadedRacks` check → every trusted tap
    /// formula would read as unchecked.
    @Test func aTapFormulaBrewLoadedIsNotReported() {
        let result = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: ["zzfixture-org/tap/zzfixture-tool"],
            installedInfo: Self.info(formulae: #"{"name":"zzfixture-tool","full_name":"zzfixture-org/tap/zzfixture-tool"}"#),
            formulaVersions: ["zzfixture-tool": "1.0"],
            caskReceiptTap: Self.noReceipt,
            caskInstallsAnApp: Self.noApp)
        #expect(result.isEmpty)
    }

    /// Mutation: match `info` by `full_name` instead of rack name → a formula that
    /// moved taps (receipt says `zzfixture-old/tap/…`, brew loaded it by bare name)
    /// would read as unchecked while `brew outdated` still covers it.
    @Test func aFormulaThatMovedTapsIsNotReported() {
        let result = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: ["zzfixture-old/tap/zzfixture-moved"],
            installedInfo: Self.info(formulae: #"{"name":"zzfixture-moved","full_name":"zzfixture-moved","tap":"homebrew/core"}"#),
            formulaVersions: ["zzfixture-moved": "1.0"],
            caskReceiptTap: Self.noReceipt,
            caskInstallsAnApp: Self.noApp)
        #expect(result.isEmpty)
    }

    /// Mutation: drop the tap-qualified check → an official formula brew failed to
    /// load for some other reason would be blamed on a tap it doesn't have.
    @Test func bareOfficialFormulaNamesAreNeverReported() {
        let result = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: ["zzfixture-core"],
            installedInfo: Self.info(),
            formulaVersions: ["zzfixture-core": "1.0"],
            caskReceiptTap: Self.noReceipt,
            caskInstallsAnApp: Self.noApp)
        #expect(result.isEmpty)
    }

    // MARK: - Casks

    /// Mutation: drop the cask loop → the measured shape (present, `tap: null`)
    /// goes unseen.
    @Test func aCaskLoadedFromItsCaskroomCopyIsReportedWithItsReceiptTap() {
        let result = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: [],
            installedInfo: Self.info(casks: #"{"token":"zzfixture-cli","full_token":"zzfixture-cli","tap":null,"version":"1.0","installed":"1.0","outdated":false}"#),
            formulaVersions: [:],
            caskReceiptTap: { $0 == "zzfixture-cli" ? "zzfixture-org/tap" : nil },
            caskInstallsAnApp: Self.noApp)
        #expect(result == [BrewUncheckedPackage(
            fullName: "zzfixture-org/tap/zzfixture-cli", kind: .cask,
            installedVersion: "1.0", reason: .unreadable)])
    }

    /// Mutation: flag every cask (drop `where cask["tap"] is NSNull`), or treat an
    /// absent `tap` key like null → casks read from their tap or the API, and
    /// output from a brew that doesn't emit the key, would read as unchecked.
    @Test func aCaskWithATapOrNoTapKeyIsNotReported() {
        let result = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: [],
            installedInfo: Self.info(casks: """
                {"token":"zzfixture-cli","full_token":"zzfixture-org/tap/zzfixture-cli","tap":"zzfixture-org/tap","installed":"1.0"},
                {"token":"zzfixture-api","full_token":"zzfixture-api","tap":"homebrew/cask","installed":"1.0"},
                {"token":"zzfixture-old","full_token":"zzfixture-old","installed":"1.0"}
                """),
            formulaVersions: [:],
            caskReceiptTap: { _ in "zzfixture-org/tap" },
            caskInstallsAnApp: Self.noApp)
        #expect(result.isEmpty)
    }

    /// Mutation: drop the `caskInstallsAnApp` skip → an app cask, which already has
    /// its own row, would also be listed (and counted) as a Brew package.
    @Test func aCaskThatInstallsAnAppIsNotReported() {
        let result = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: [],
            installedInfo: Self.info(casks: #"{"token":"zzfixture-gui","full_token":"zzfixture-gui","tap":null,"installed":"1.0"}"#),
            formulaVersions: [:],
            caskReceiptTap: { _ in "zzfixture-org/tap" },
            caskInstallsAnApp: { $0 == "zzfixture-gui" })
        #expect(result.isEmpty)
    }

    /// Mutation: derive `tap` from the first two components of any name (or label
    /// by a prefix match) → a bare token with no receipt tap could be labeled
    /// "not trusted" and offered a `brew trust` command that names no tap.
    @Test func aCaskWithoutAReceiptTapStaysBareAndUnlabeled() {
        let candidates = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: [],
            installedInfo: Self.info(casks: #"{"token":"zzfixture-cli","full_token":"zzfixture-cli","tap":null,"installed":"1.0"}"#),
            formulaVersions: [:],
            caskReceiptTap: Self.noReceipt,
            caskInstallsAnApp: Self.noApp)
        #expect(candidates.map(\.fullName) == ["zzfixture-cli"])
        #expect(candidates.first?.tap == nil)
        let labeled = BrewFormulaService.label(candidates, untrustedTaps: ["zzfixture-cli"])
        #expect(labeled.first?.reason == .unreadable)
    }

    // MARK: - Fail closed

    /// Mutation: default a missing `formulae`/`casks` array to [] instead of
    /// bailing → a failed `brew info` read ("") would flag every tap formula.
    @Test func anUnparseableInfoReadReportsNothing() {
        let result = BrewFormulaService.uncheckedCandidates(
            formulaFullNames: ["zzfixture-org/tap/zzfixture-tool"],
            installedInfo: Data(),
            formulaVersions: [:],
            caskReceiptTap: { _ in "zzfixture-org/tap" },
            caskInstallsAnApp: Self.noApp)
        #expect(result.isEmpty)
    }

    // MARK: - Labeling

    /// Mutation: invert the `contains`, or label everything `.tapNotTrusted` →
    /// the trusted-tap and gone-tap cases would say "not trusted".
    @Test func onlyTapsTapInfoMarksUntrustedGetThatLabel() {
        let tapInfo = Data(#"""
        [{"name":"zzfixture-untrusted/tap","official":false,"trusted":false},
         {"name":"zzfixture-trusted/tap","official":false,"trusted":true}]
        """#.utf8)
        let untrusted = BrewFormulaService.parseUntrustedTaps(tapInfo)
        #expect(untrusted == ["zzfixture-untrusted/tap"])

        let labeled = BrewFormulaService.label([
            BrewUncheckedPackage(fullName: "zzfixture-untrusted/tap/a", kind: .formula,
                                 installedVersion: "1", reason: .unreadable),
            BrewUncheckedPackage(fullName: "zzfixture-trusted/tap/b", kind: .formula,
                                 installedVersion: "1", reason: .unreadable),
            BrewUncheckedPackage(fullName: "zzfixture-gone/tap/c", kind: .cask,
                                 installedVersion: "1", reason: .unreadable),
        ], untrustedTaps: untrusted)
        #expect(labeled.map(\.reason) == [.tapNotTrusted, .unreadable, .unreadable])
        #expect(labeled.first?.trustCommand == "brew trust --formula zzfixture-untrusted/tap/a")
        #expect(labeled.last?.trustCommand == "brew trust --cask zzfixture-gone/tap/c")
    }

    // MARK: - Service wiring

    /// End to end through the executor seam: which subcommands run, and that the
    /// label read is skipped when there's nothing to label.
    /// Mutation: add any `list --cask …` read (measured: `--versions` exits 1 when a
    /// cask is untrusted, `--full-name` prints it bare) → recorded as unexpected.
    @Test func serviceWiresTheReadsAndLabels() async {
        let calls = CallLog()
        let service = BrewFormulaService(executor: { arguments in
            calls.append(arguments)
            switch arguments {
            case ["list", "--formula", "--full-name"]:
                return (0, Data("zzfixture-core\nzzfixture-org/tap/zzfixture-tool\n".utf8))
            case ["list", "--formula", "--versions"]:
                return (0, Data("zzfixture-core 1.0\nzzfixture-tool 1.3.14\n".utf8))
            case ["info", "--json=v2", "--installed"]:
                return (0, Self.info(
                    formulae: #"{"name":"zzfixture-core","full_name":"zzfixture-core"}"#,
                    casks: #"{"token":"zzfixture-cli","full_token":"zzfixture-cli","tap":null,"installed":"0.1"}"#))
            case ["tap-info", "--json=v1", "--installed"]:
                return (0, Data(#"[{"name":"zzfixture-org/tap","trusted":false}]"#.utf8))
            default:
                Issue.record("unexpected arguments: \(arguments)")
                return (1, Data())
            }
        }, caskReceiptTap: { $0 == "zzfixture-cli" ? "zzfixture-org/tap" : nil })

        let result = await service.uncheckedPackages()
        #expect(result.map(\.fullName) == ["zzfixture-org/tap/zzfixture-cli",
                                           "zzfixture-org/tap/zzfixture-tool"])
        #expect(result.map(\.installedVersion) == ["0.1", "1.3.14"])
        #expect(result.allSatisfy { $0.reason == .tapNotTrusted })
        #expect(calls.contains(["tap-info", "--json=v1", "--installed"]))
    }

    /// Mutation: drop the `guard !candidates.isEmpty` → a 360 KB `tap-info` read
    /// on every refresh for machines with nothing to label.
    @Test func serviceSkipsTapInfoWhenNothingIsUnchecked() async {
        let calls = CallLog()
        let service = BrewFormulaService(executor: { arguments in
            calls.append(arguments)
            if arguments == ["info", "--json=v2", "--installed"] { return (0, Self.info()) }
            return (0, Data("zzfixture-core\n".utf8))
        })
        #expect(await service.uncheckedPackages().isEmpty)
        #expect(!calls.contains(["tap-info", "--json=v1", "--installed"]))
    }

    @Test func serviceReportsNothingWhenBrewIsAbsent() async {
        let service = BrewFormulaService(executor: { _ in nil })
        #expect(await service.uncheckedPackages().isEmpty)
    }

    /// The real receipt reader, against a Caskroom this test builds in a temp dir
    /// (never the host's). The receipt body is trimmed from the fixture cask's real
    /// `INSTALL_RECEIPT.json`. Mutation: read a different key (e.g. top-level
    /// `tap`) → nil.
    @Test func theReceiptReaderFindsSourceTap() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-Caskroom-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let meta = root.appendingPathComponent("zzfixture-cli/.metadata")
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        try Data(#"{"installed_on_request":true,"source":{"tap":"zzfixture-org/tap","tap_git_head":null,"version":"1.0"}}"#.utf8)
            .write(to: meta.appendingPathComponent("INSTALL_RECEIPT.json"))

        let paths = ["/nonexistent-ZZFixture-Caskroom", root.path]
        #expect(BrewFormulaService.realCaskReceiptTap("zzfixture-cli", caskroomPaths: paths) == "zzfixture-org/tap")
        #expect(BrewFormulaService.realCaskReceiptTap("zzfixture-missing", caskroomPaths: paths) == nil)
    }

    // MARK: - The "—" version on tap leaves

    /// `brew leaves` prints a tap formula tap-qualified; `list --versions` keys it
    /// by rack name. Mutation: look up `versions[name]` → "—".
    @Test func aTapQualifiedLeafGetsItsInstalledVersion() async throws {
        let service = BrewFormulaService(executor: { arguments in
            switch arguments {
            case ["leaves"]: return (0, Data("zzfixture-org/tap/zzfixture-tool\n".utf8))
            case ["list", "--formula", "--versions"]: return (0, Data("zzfixture-tool 1.4.2\n".utf8))
            default: return (1, Data())
            }
        })
        let leaves = try await service.installedLeaves()
        #expect(leaves.map(\.name) == ["zzfixture-org/tap/zzfixture-tool"])
        #expect(leaves.first?.installedVersion == "1.4.2")
    }

    final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [[String]] = []
        func append(_ c: [String]) { lock.lock(); calls.append(c); lock.unlock() }
        func contains(_ c: [String]) -> Bool { lock.lock(); defer { lock.unlock() }; return calls.contains(c) }
    }
}
