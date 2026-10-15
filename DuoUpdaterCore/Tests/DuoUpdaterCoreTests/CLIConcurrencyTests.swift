import Testing
import Foundation
@testable import DuoUpdaterCore

/// Which CLI-tab changes wait for which (`CLIConcurrency`, #1312).
@Suite struct CLIConcurrencyTests {

    static let nvmNode = CLIOperation.tool(id: "npm:nvm", homebrewFormulae: [])
    static let brewNode = CLIOperation.tool(id: "npm:brew", homebrewFormulae: ["node"])

    // MARK: - Homebrew vs. a tool

    /// The reported case: Upgrade All runs, and node is in it, but the npm copy
    /// is nvm's. Neither waits for the other.
    @Test func aCopyOnNvmsNodeNeverWaitsForBrew() {
        let all = CLIOperation.upgradeAll(targets: ["node", "xz"])
        #expect(CLIConcurrency.start(Self.nvmNode, running: [all]) == .now)
        #expect(CLIConcurrency.start(all, running: [Self.nvmNode]) == .now)
    }

    /// Mutation: drop the formula intersection in `conflict` → `.now` both ways.
    @Test func aCopyOnHomebrewsNodeWaitsWhenTheRunUpgradesNode() {
        let all = CLIOperation.upgradeAll(targets: ["node", "xz"])
        #expect(CLIConcurrency.start(Self.brewNode, running: [all]) == .after(all))
        #expect(CLIConcurrency.start(all, running: [Self.brewNode]) == .after(Self.brewNode))
        let row = CLIOperation.upgradeFormula("node")
        #expect(CLIConcurrency.start(Self.brewNode, running: [row]) == .after(row))
        #expect(CLIConcurrency.start(row, running: [Self.brewNode]) == .after(Self.brewNode))
    }

    @Test func aCopyOnHomebrewsNodeDoesNotWaitWhenTheRunLeavesNodeAlone() {
        let all = CLIOperation.upgradeAll(targets: ["xz", "uv"])
        #expect(CLIConcurrency.start(Self.brewNode, running: [all]) == .now)
        #expect(CLIConcurrency.start(all, running: [Self.brewNode]) == .now)
        #expect(CLIConcurrency.start(Self.brewNode, running: [.upgradeFormula("xz"), .homebrewUpdate]) == .now)
    }

    /// A tap formula is targeted by its full name; its keg is the short one.
    @Test func aTapQualifiedTargetMeetsItsKeg() {
        let pnpm = CLIOperation.tool(id: "pnpm", homebrewFormulae: ["pnpm"])
        let all = CLIOperation.upgradeAll(targets: ["zzfixture/tap/pnpm"])
        #expect(CLIConcurrency.start(pnpm, running: [all]) == .after(all))
    }

    @Test func aToolThatIsNotJavaScriptNeverWaitsForBrew() {
        let uv = CLIOperation.tool(id: "uv", homebrewFormulae: [])
        let all = CLIOperation.upgradeAll(targets: ["node"])
        #expect(CLIConcurrency.start(uv, running: [all, .homebrewUpdate]) == .now)
    }

    // MARK: - Homebrew vs. Homebrew

    /// Mutation: drop the `.redundant` loop for `.upgradeFormula` → `.after`.
    @Test func aFormulaInUpgradeAllsSnapshotIsRedundant() {
        let all = CLIOperation.upgradeAll(targets: ["node", "xz"])
        #expect(CLIConcurrency.start(.upgradeFormula("xz"), running: [all]) == .redundant)
        #expect(CLIConcurrency.start(.upgradeFormula("xz"), running: [.upgradeFormula("xz")]) == .redundant)
    }

    @Test func aFormulaOutsideTheSnapshotWaitsForTheRun() {
        let all = CLIOperation.upgradeAll(targets: ["node", "xz"])
        #expect(CLIConcurrency.start(.upgradeFormula("uv"), running: [all]) == .after(all))
    }

    /// One brew mutation at a time: brew takes one global lock.
    @Test func brewRunsWaitForEachOther() {
        #expect(CLIConcurrency.start(.upgradeAll(targets: ["xz"]), running: [.upgradeFormula("uv")])
            == .after(.upgradeFormula("uv")))
        #expect(CLIConcurrency.start(.homebrewUpdate, running: [.upgradeFormula("uv")]) == .after(.upgradeFormula("uv")))
        #expect(CLIConcurrency.start(.upgradeFormula("uv"), running: [.homebrewUpdate]) == .after(.homebrewUpdate))
        #expect(CLIConcurrency.start(.upgradeFormula("uv"), running: [.upgradeFormula("xz")]) == .after(.upgradeFormula("xz")))
        #expect(CLIConcurrency.start(.upgradeAll(targets: []), running: [.upgradeAll(targets: ["xz"])]) == .redundant)
        #expect(CLIConcurrency.start(.homebrewUpdate, running: []) == .now)
    }

    // MARK: - Which formulae a copy runs on

    /// An npm Claude Code under a Homebrew root runs on the keg its `bin/node`
    /// links into; the same layout outside a Homebrew root runs on none.
    ///
    /// Mutation: return `[]` for `.claudeCode` → the first expectation fails.
    @Test func claudeCodeOnHomebrewsNodeRunsOnTheNodeFormula() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-brew-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let keg = root.appendingPathComponent("Cellar/node@22/22.20.0")
        try FileManager.default.createDirectory(at: keg.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data().write(to: keg.appendingPathComponent("bin/node"))
        try Data("{}".utf8).write(to: keg.appendingPathComponent("INSTALL_RECEIPT.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("bin/node").path, withDestinationPath: "../Cellar/node@22/22.20.0/bin/node")
        let status = Self.claudeCode(prefix: root.path)

        #expect(CLIConcurrency.homebrewFormulae(of: status, homebrewRoots: [root.path]) == ["node@22"])
        #expect(CLIConcurrency.homebrewFormulae(of: status, homebrewRoots: ["/opt/homebrew"]).isEmpty)
    }

    @Test func npmPackageRunsOnItsRuntimesKeg() {
        let onBrew = Self.npm(keg: "/opt/homebrew/Cellar/node/26.10.0_1")
        #expect(CLIConcurrency.homebrewFormulae(of: onBrew) == ["node"])
        let onNvm = Self.npm(keg: nil)
        #expect(CLIConcurrency.homebrewFormulae(of: onNvm).isEmpty)
    }

    @Test func otherToolsRunOnNoFormula() {
        let fx = CLIToolStatus(
            kind: .fx, path: "/ZZFixture-fx", installedVersion: "1", latestVersion: "2", channel: nil,
            state: .updateAvailable, oneClick: nil, withheld: nil, note: nil,
            detail: .fx(FxInstall(path: "/ZZFixture-fx", version: "1")))
        #expect(CLIConcurrency.homebrewFormulae(of: fx).isEmpty)
    }

    // MARK: - brew's per-formula start line

    @Test func upgradingLineNamesTheFormulaAndNotTheRunsHeading() {
        #expect(BrewFormulaService.upgradingFormula(fromLine: "==> Upgrading zzfixture-alpha") == "zzfixture-alpha")
        #expect(BrewFormulaService.upgradingFormula(fromLine: "==> Upgrading zzfixture/tap/zzfixture-alpha") == "zzfixture-alpha")
        #expect(BrewFormulaService.upgradingFormula(fromLine: "==> Upgrading 3 outdated packages:") == nil)
        #expect(BrewFormulaService.upgradingFormula(fromLine: "==> Pouring zzfixture-alpha--1.0.arm64_tahoe.bottle.tar.gz") == nil)
    }

    // MARK: - Fixtures

    static func claudeCode(prefix: String) -> CLIToolStatus {
        let install = ClaudeCodeInstall(
            path: prefix + "/lib/node_modules/@anthropic-ai/claude-code", method: .npm, origin: .conventional,
            executable: nil, version: "2.1.280", signature: .anthropic, problem: nil, nodePrefix: prefix)
        return CLIToolStatus(
            kind: .claudeCode, path: install.path, installedVersion: "2.1.280", latestVersion: "2.1.285", channel: nil,
            state: .updateAvailable, oneClick: nil, withheld: nil, note: nil,
            detail: .claudeCode(ClaudeCodeStatus(
                install: install, channel: .latest, latestVersion: "2.1.285", versionConfirmed: nil,
                state: .updateAvailable, oneClick: nil, note: nil)))
    }

    static func npm(keg: String?) -> CLIToolStatus {
        let path = "/ZZFixture-prefix/lib/node_modules/zzfixture-pkg"
        let install = NpmInstall(
            path: path, name: "zzfixture-pkg", version: "1.0.0", manifestName: nil,
            prefix: NodePrefix(path: "/ZZFixture-prefix", source: .system, layoutNodeVersion: nil),
            runtime: NpmRuntime(node: "/ZZFixture-prefix/bin/node", npm: nil, npmVersion: nil, nodeSignature: .adHoc,
                                nodeQuarantined: false, nodeVersion: nil, homebrewKeg: keg))
        return CLIToolStatus(
            kind: .npm, path: path, installedVersion: "1.0.0", latestVersion: "1.1.0", channel: nil,
            state: .updateAvailable, oneClick: nil, withheld: nil, note: nil,
            detail: .npm(NpmPackage(install: install)))
    }
}
