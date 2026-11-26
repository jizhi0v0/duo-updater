import Foundation
import Testing
@testable import DuoUpdaterCore

struct BrewReadMergeTests {
    private static let lifecycle = BrewLifecycle(
        stage: .deprecated, reason: "unmaintained", disableDate: nil,
        replacementFormula: nil, replacementCask: nil)
    private static let head = BrewHeadInstall(
        name: "zzfixture-tool", version: "HEAD-1234567", commit: "1234567",
        branch: nil, upstream: .other)
    private static let formula = BrewInstalledFormula(
        name: "zzfixture-tool", installedVersion: "1.0", availableVersion: "2.0",
        lifecycle: lifecycle, head: head)
    private static let cask = BrewInstalledFormula(
        name: "zzfixture-cask", installedVersion: "1.0", availableVersion: "2.0",
        lifecycle: lifecycle, kind: .cask)
    private static let caskLifecycle = BrewCaskLifecycle(
        token: "zzfixture-cask", installedVersion: "1.0", appPaths: [],
        installsAnApp: false, lifecycle: lifecycle)
    private static let association = BrewAppCask(row: cask, appPaths: ["/Applications/ZZFixture.app"])
    private static let formulaWarning = BrewUncheckedPackage(
        fullName: "zzfixture-legacy", kind: .formula, installedVersion: "1.0", reason: .renamed(to: "new"))
    private static let caskWarning = BrewUncheckedPackage(
        fullName: "zzfixture/tap/hidden", kind: .cask, installedVersion: "1.0", reason: .tapNotTrusted)

    private static func update(_ row: BrewInstalledFormula, version: String = "2.0") -> BrewOutdatedFormula {
        BrewOutdatedFormula(
            name: row.name, installedVersion: row.installedVersion, currentVersion: version, kind: row.kind)
    }

    private static var previous: BrewReadMerge {
        BrewReadMerge(
            inventory: [formula, cask], outdated: [update(formula), update(cask)],
            unchecked: [formulaWarning, caskWarning], caskLifecycles: [caskLifecycle],
            appCasks: [association])
    }

    private static var failedInfo: BrewFormulaService.InstalledReport {
        var report = BrewFormulaService.InstalledReport()
        report.formulaeRead = false
        report.casksRead = false
        report.uncheckedFormulaeRead = false
        report.uncheckedCasksRead = false
        report.readErrors = ["controlled info failure"]
        return report
    }

    /// Removing the nil fallback drops the version and Update, the original bug.
    @Test func aFailedCaskCheckKeepsTheBadgeAndUpdateWhileFormulaeRefresh() {
        var report = BrewFormulaService.InstalledReport()
        report.appLessCasks = [Self.cask]
        let merged = Self.previous.merging(
            leaves: [Self.formula], formulaUpdates: [Self.update(Self.formula, version: "3.0")],
            caskUpdates: nil, report: report)
        #expect(merged.inventory.first { $0.kind == .cask }?.availableVersion == "2.0")
        #expect(merged.inventory.first { $0.kind == .cask }?.canUpgrade == true)
        #expect(merged.inventory.first { $0.kind == .formula }?.availableVersion == "3.0")
        #expect(Set(merged.outdated.map { "\($0.name):\($0.currentVersion)" })
            == ["zzfixture-tool:3.0", "zzfixture-cask:2.0"])
    }

    @Test func aFailedFormulaCheckDoesNotUndoASuccessfulEmptyCaskCheck() {
        var report = BrewFormulaService.InstalledReport()
        report.appLessCasks = [Self.cask]
        let merged = Self.previous.merging(
            leaves: [Self.formula], formulaUpdates: nil, caskUpdates: [], report: report)
        #expect(merged.inventory.first { $0.kind == .formula }?.availableVersion == "2.0")
        #expect(merged.inventory.first { $0.kind == .formula }?.canUpgrade == true)
        #expect(merged.inventory.first { $0.kind == .cask }?.availableVersion == nil)
        #expect(merged.outdated.map(\.name) == ["zzfixture-tool"])
    }

    /// Mutating the metadata assignments to always use report's empty maps loses
    /// both the deprecation and the explicit HEAD interpretation.
    @Test func aFailedInfoReadKeepsWarningsHEADAndAppAssociation() {
        let merged = Self.previous.merging(
            leaves: nil, formulaUpdates: nil, caskUpdates: nil, report: Self.failedInfo)
        #expect(merged.inventory.first { $0.kind == .formula }?.lifecycle == Self.lifecycle)
        #expect(merged.inventory.first { $0.kind == .formula }?.head == Self.head)
        #expect(merged.inventory.first { $0.kind == .cask }?.lifecycle == Self.lifecycle)
        #expect(merged.unchecked == [Self.caskWarning, Self.formulaWarning])
        #expect(merged.caskLifecycles == [Self.caskLifecycle])
        #expect(merged.appCasks == [Self.association])
        #expect(Set(merged.inventory.filter(\.canUpgrade).map(\.key)) == ["zzfixture-tool", "cask:zzfixture-cask"])
    }

    @Test func aSuccessfulUpdateReadStillAppliesWhenInstalledInfoFails() {
        let merged = Self.previous.merging(
            leaves: [Self.formula], formulaUpdates: [],
            caskUpdates: [Self.update(Self.cask, version: "3.0")], report: Self.failedInfo)
        #expect(merged.inventory.first { $0.kind == .formula }?.availableVersion == nil)
        #expect(merged.inventory.first { $0.kind == .formula }?.lifecycle == Self.lifecycle)
        #expect(merged.inventory.first { $0.kind == .cask }?.availableVersion == "3.0")
        #expect(merged.inventory.first { $0.kind == .cask }?.lifecycle == Self.lifecycle)
    }

    /// Successful empty must remove the very last package as well as its badges
    /// and warnings. Testing only a non-empty replacement missed this before.
    @Test func successfulEmptyReadsClearTheLastPackagesAndTheirWarnings() {
        let merged = Self.previous.merging(
            leaves: [], formulaUpdates: [], caskUpdates: [], report: .init())
        #expect(merged.inventory.isEmpty)
        #expect(merged.outdated.isEmpty)
        #expect(merged.unchecked.isEmpty)
        #expect(merged.caskLifecycles.isEmpty)
        #expect(merged.appCasks.isEmpty)
    }

    @Test func aRecoveredCheckCanRemoveOldBadgesAndLifecycleWarnings() {
        var report = BrewFormulaService.InstalledReport()
        var cask = Self.cask
        cask.lifecycle = nil
        report.appLessCasks = [cask]
        let merged = Self.previous.merging(
            leaves: [Self.formula], formulaUpdates: [], caskUpdates: [], report: report)
        #expect(Set(merged.inventory.map(\.key)) == ["zzfixture-tool", "cask:zzfixture-cask"])
        #expect(merged.inventory.allSatisfy { !$0.hasUpdate && $0.lifecycle == nil && $0.head == nil })
        #expect(merged.outdated.isEmpty && merged.unchecked.isEmpty)
        #expect(merged.caskLifecycles.isEmpty && merged.appCasks.isEmpty)
    }

    @Test func uncheckedWarningsAreKeptIndependentlyAndStillShadowTheirLeaf() {
        var report = BrewFormulaService.InstalledReport()
        report.uncheckedFormulaeRead = false
        // Homebrew loads a renamed leaf under its new name. The old package's
        // warning is the replacement for that new-name leaf, as leafName states.
        let renamed = BrewInstalledFormula(name: "new", installedVersion: "1.0", availableVersion: nil)
        let merged = Self.previous.merging(
            leaves: [Self.formula, renamed], formulaUpdates: [], caskUpdates: [], report: report)
        #expect(merged.unchecked == [Self.formulaWarning])
        #expect(!merged.inventory.contains { $0.name == "new" })
        #expect(!merged.unchecked.contains { $0.kind == .cask })
    }

    @Test func aBlockedCaskKeepsItsVersionEvenThoughItWasExcludedFromTheCount() {
        var cask = Self.cask
        cask.manualInstaller = true
        let previous = BrewReadMerge(
            inventory: [cask], outdated: [], unchecked: [], caskLifecycles: [], appCasks: [])
        let merged = previous.merging(
            leaves: [], formulaUpdates: [], caskUpdates: nil, report: Self.failedInfo)
        #expect(merged.inventory.map(\.availableVersion) == ["2.0"])
        #expect(merged.inventory[0].hasListedUpdate)
        #expect(!merged.inventory[0].canUpgrade)
        #expect(merged.outdated.isEmpty)
    }

    @Test func anIncompatibleCaskKeepsItsBadgeAndReasonOutsideTheActionableCount() {
        var cask = Self.cask
        let reason = CaskIncompatibility.architecture(required: [.x86_64], host: .arm64)
        cask.incompatibility = reason
        let previous = BrewReadMerge(
            inventory: [cask], outdated: [], unchecked: [], caskLifecycles: [], appCasks: [])
        let failed = previous.merging(
            leaves: [], formulaUpdates: [], caskUpdates: nil, report: Self.failedInfo)
        #expect(failed.inventory.map(\.availableVersion) == ["2.0"])
        #expect(failed.inventory.first?.incompatibility == reason)
        #expect(!failed.inventory[0].canUpgrade && failed.outdated.isEmpty)

        var report = BrewFormulaService.InstalledReport()
        cask.incompatibility = nil
        report.appLessCasks = [cask]
        let recovered = failed.merging(
            leaves: [], formulaUpdates: [], caskUpdates: [Self.update(cask)], report: report)
        #expect(recovered.inventory.first?.incompatibility == nil)
        #expect(recovered.inventory.first?.canUpgrade == true)
        #expect(recovered.outdated.map(\.name) == ["zzfixture-cask"])
    }
}
