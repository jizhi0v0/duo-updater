import Foundation
import DuoUpdaterCore

/// The complete Brew tree after one refresh. Each failed read keeps only its
/// previous answer; a successful empty read clears it. Update eligibility is
/// unchanged while a check fails — the UI explains that these are last results.
struct BrewReadMerge {
    var inventory: [BrewInstalledFormula]
    var outdated: [BrewOutdatedFormula]
    var unchecked: [BrewUncheckedPackage]
    var caskLifecycles: [BrewCaskLifecycle]
    var appCasks: [BrewAppCask]

    init(
        inventory: [BrewInstalledFormula], outdated: [BrewOutdatedFormula],
        unchecked: [BrewUncheckedPackage], caskLifecycles: [BrewCaskLifecycle],
        appCasks: [BrewAppCask]
    ) {
        self.inventory = inventory
        self.outdated = outdated
        self.unchecked = unchecked
        self.caskLifecycles = caskLifecycles
        self.appCasks = appCasks
    }

    /// Optional lists distinguish failed reads from successful empty arrays.
    /// `report` has the same distinction per kind and for its extra warning reads.
    func merging(
        leaves: [BrewInstalledFormula]?, formulaUpdates: [BrewOutdatedFormula]?,
        caskUpdates: [BrewOutdatedFormula]?, report: BrewFormulaService.InstalledReport
    ) -> Self {
        let formulaRows = leaves ?? inventory.filter { $0.kind == .formula }
        let caskRows = report.casksRead
            ? report.appLessCasks + report.appCasks.map(\.row)
            : inventory.filter { $0.kind == .cask }
        let formulae = formulaUpdates ?? outdated.filter { $0.kind == .formula }
        let rowTokens = Set(caskRows.map(\.name))
        // A blocked package still displays an available version, but is absent
        // from the actionable count (`outdated`). Keep its badge as well.
        let priorCaskUpdates = inventory.compactMap { row -> BrewOutdatedFormula? in
            guard row.kind == .cask, let version = row.availableVersion else { return nil }
            return BrewOutdatedFormula(
                name: row.name, installedVersion: row.installedVersion,
                currentVersion: version, kind: .cask)
        }
        let casks = (caskUpdates ?? priorCaskUpdates)
            .filter { rowTokens.contains($0.name) }
        let blocked = Set(caskRows.filter {
            $0.manualInstaller || $0.missingAppPath != nil || $0.incompatibility != nil
        }.map(\.name))

        let formulaWarnings = report.uncheckedFormulaeRead
            ? report.unchecked.filter { $0.kind == .formula }
            : unchecked.filter { $0.kind == .formula }
        let caskWarnings = report.uncheckedCasksRead
            ? report.unchecked.filter { $0.kind == .cask }
            : unchecked.filter { $0.kind == .cask }
        let warnings = (formulaWarnings + caskWarnings).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let shadowed = Set(warnings.compactMap(\.leafName))
        let previousRows = Dictionary(inventory.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = BrewFormulaService.merge(formulaRows + caskRows, outdated: formulae + casks)
            .filter { $0.kind == .cask || !shadowed.contains($0.name) }
            .map { row in
                guard row.kind == .formula else { return row }
                var row = row
                row.lifecycle = report.formulaeRead ? report.lifecycles[row.name] : previousRows[row.key]?.lifecycle
                row.head = report.formulaeRead ? report.headInstalls[row.name] : previousRows[row.key]?.head
                return row
            }
        return Self(
            inventory: rows, outdated: formulae + casks.filter { !blocked.contains($0.name) },
            unchecked: warnings,
            caskLifecycles: report.casksRead ? report.caskLifecycles : caskLifecycles,
            appCasks: report.casksRead ? report.appCasks : appCasks)
    }
}
