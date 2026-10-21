import Foundation
import DuoUpdaterCore

/// The registry ids of our brew runs, and which of them the popover's Homebrew
/// row stands for and its one Cancel stops. What the rows draw of them is
/// `BrewRowSnapshot`'s, in Core. Kept out of `AppListModel` so the app's test
/// target can compile it.
enum BrewRowRuns {

    /// The registry's id for a formula row's upgrade: apart from the app rows',
    /// whose ids are bundle paths, and the tool rows' (`CLIToolsModel.jobID`).
    static func formulaJobID(_ name: String) -> String {
        "brew-formula:\(name)"
    }

    /// The registry's id for Upgrade All. Not a formula's: a formula name has
    /// no `:`.
    static let upgradeAllJobID = "brew-upgrade-all"

    /// The id `brew update`'s Cancel goes by while it waits its turn. It has
    /// no job: once it runs, it has no Cancel.
    static let homebrewUpdateJobID = "brew-update"

    /// The runs the row stands for: Upgrade All, and each formula's own
    /// upgrade from the workbench, which the row did not show at all before
    /// (2026-10-20). Not `brew update`: the row neither shows nor counts it,
    /// and the Brew tree has its own Cancel for it while it waits.
    static func jobIDs(upgradingAll: Bool, formulae: Set<String>) -> [String] {
        (upgradingAll ? [upgradeAllJobID] : []) + formulae.sorted().map(formulaJobID)
    }

    /// The runs a click on it cancels: those that still can be. Those past the
    /// upgrade's start finish.
    static func cancellable(_ jobIDs: [String], in cancels: [String: InstallCancelState]) -> [String] {
        jobIDs.filter { cancels[$0] == .available }
    }
}

extension BrewProgressLine {
    /// The line as the Homebrew rows show it.
    var text: String {
        switch self {
        case .queued: String(localized: "Queued")
        case .starting: String(localized: "Starting…")
        case .cancelling: String(localized: "Cancelling…")
        case .note(let note): note
        case .count(let current, let total): String(localized: "Upgrading… (\(current)/\(total))")
        case .runningBrewUpgrade: String(localized: "Running brew upgrade…")
        case .updating: String(localized: "Updating…")
        }
    }
}
