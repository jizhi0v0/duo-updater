import Foundation

/// One change the CLI tab runs: one of Homebrew's, or an "Other tools" update.
public enum CLIOperation: Hashable, Sendable {
    /// `brew update`.
    case homebrewUpdate
    /// Upgrade All: `brew upgrade --formula`, then the listed casks by name.
    case upgradeAll
    /// One formula's own `brew upgrade --formula <name>`.
    case upgradeFormula
    /// One copy's update, or Update All's.
    case tool

    public var isHomebrew: Bool { self != .tool }
}

/// Whether an operation may start, given the ones running (`CLIConcurrency.start`).
public enum CLIStart: Equatable, Sendable {
    case now
    /// This running one must finish first.
    case blocked(by: CLIOperation)
}

/// Which CLI-tab changes may run at once — the one rule every Update and Upgrade
/// All, in the popover and the workbench, and every model action reads (#1312).
/// The buttons each used to carry their own condition, and they drifted apart.
///
/// - Homebrew vs. Homebrew: one at a time. `brew update` takes a lock of its own;
///   an upgrade locks the formula and all its dependencies, and a second run
///   that needs one of them fails with "already in progress" (Homebrew 7.0.9:
///   `cmd/update.sh` `lock update`, `FormulaInstaller#lock`).
/// - Homebrew vs. a tool: one at a time, whatever the tool. brew guards nothing
///   against a process outside it: its locks are flock files only brew takes,
///   it unlinks a formula's old keg (`bin/node` gone) before installing the new
///   one, and removes old kegs at the end of the run, with no check for a
///   process using them (`install.rb` `kegs.each(&:unlink)`, `Cleanup`). And
///   which Homebrew files a tool's update runs on can't be known in full ahead
///   of time: an npm copy may run on Homebrew's node, that node links a score of
///   Homebrew libraries any of which Upgrade All may replace, and an updater can
///   start programs of its own. A rule that let some through would fail open for
///   every case it missed.
/// - Tool vs. tool: not decided here (`.now`). Each tool's own rules stay
///   (`CLIToolsModel.lane(of:)`).
public enum CLIConcurrency {

    public static func start(_ operation: CLIOperation, running: [CLIOperation]) -> CLIStart {
        for other in running where operation.isHomebrew || other.isHomebrew {
            return .blocked(by: other)
        }
        return .now
    }
}
