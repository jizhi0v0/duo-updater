import Foundation
import Observation
import Synchronization

/// One change the CLI tab runs: one of Homebrew's, or one "Other tools" copy's update.
public enum CLIOperation: Hashable, Sendable {
    /// `brew update`.
    case homebrewUpdate
    /// Upgrade All, with the formulae and casks it set out to upgrade.
    case upgradeAll(targets: Set<String>)
    /// One formula's own `brew upgrade --formula <name>`.
    case upgradeFormula(String)
    /// One copy's update, with the Homebrew formulae it runs on
    /// (`CLIConcurrency.homebrewFormulae(of:)`).
    case tool(id: String, homebrewFormulae: Set<String>)

    var isHomebrew: Bool {
        if case .tool = self { return false }
        return true
    }

    /// The formulae this run changes, by short name; nil for a tool's update.
    /// `brew update` changes Homebrew itself and no formula.
    var upgrades: Set<String>? {
        switch self {
        case .homebrewUpdate: return []
        case .upgradeAll(let targets): return Set(targets.map(CLIConcurrency.shortName))
        case .upgradeFormula(let name): return [CLIConcurrency.shortName(name)]
        case .tool: return nil
        }
    }
}

/// When an operation may start, given the ones running (`CLIConcurrency.start`).
public enum CLIStart: Equatable, Sendable {
    /// Nothing it conflicts with is running.
    case now
    /// It waits for this one to finish.
    case after(CLIOperation)
    /// A running one already does it.
    case redundant
}

/// Which CLI-tab changes may run at once — the one rule every Update and Upgrade
/// All, in the popover and the workbench, and every model action consults.
///
/// - Homebrew vs. Homebrew: one at a time. brew takes one global lock; a second
///   run on top of the first fails on it. A formula Upgrade All is already
///   upgrading, or one its own row is, is redundant.
/// - Homebrew vs. a tool: only when the tool runs on a formula the brew run
///   upgrades — an npm copy on Homebrew's `node`, pnpm or Yarn from Homebrew.
///   A copy on nvm's node, or a tool that is not JavaScript at all, never waits
///   for brew, nor brew for it.
/// - Tool vs. tool: not decided here. Each tool's own rules stay
///   (`CLIToolsModel.lane(of:)`), and this answers `.now`.
public enum CLIConcurrency {

    public static func start(_ operation: CLIOperation, running: [CLIOperation]) -> CLIStart {
        switch operation {
        case .upgradeFormula(let name):
            for other in running {
                if case .upgradeFormula(let busy) = other, shortName(busy) == shortName(name) { return .redundant }
                if case .upgradeAll(let targets) = other, targets.map(shortName).contains(shortName(name)) {
                    return .redundant
                }
            }
        case .upgradeAll:
            if running.contains(where: { if case .upgradeAll = $0 { true } else { false } }) { return .redundant }
        case .homebrewUpdate:
            if running.contains(.homebrewUpdate) { return .redundant }
        case .tool(let id, _):
            if running.contains(where: { if case .tool(id, _) = $0 { true } else { false } }) { return .redundant }
        }
        for other in running where conflict(operation, other) { return .after(other) }
        return .now
    }

    private static func conflict(_ a: CLIOperation, _ b: CLIOperation) -> Bool {
        if a.isHomebrew && b.isHomebrew { return true }
        switch (a, b) {
        case (.tool(_, let formulae), _): return !(b.upgrades ?? []).isDisjoint(with: formulae)
        case (_, .tool(_, let formulae)): return !(a.upgrades ?? []).isDisjoint(with: formulae)
        default: return false
        }
    }

    /// The Homebrew formulae `status`'s update runs on, by short name: the node
    /// keg an npm copy's prefix links to (`node`, `node@22`), and Homebrew's pnpm
    /// or Yarn with the node they run on. Empty for everything else — a copy on
    /// nvm's node, bun's packages (bun runs them, not node), every other tool.
    public static func homebrewFormulae(of status: CLIToolStatus) -> Set<String> {
        homebrewFormulae(of: status, homebrewRoots: ["/opt/homebrew", "/usr/local"])
    }

    static func homebrewFormulae(of status: CLIToolStatus, homebrewRoots: [String]) -> Set<String> {
        var kegs: [String?] = []
        switch status.detail {
        case .npm(let package) where package.install.bun == nil:
            if let manager = package.install.global?.manager {
                kegs += [manager.homebrewKeg, manager.runtime?.homebrewKeg]
            } else {
                kegs.append(package.install.runtime.homebrewKeg)
            }
        case .claudeCode(let claude) where claude.install.method == .npm:
            if let prefix = claude.install.nodePrefix {
                let url = URL(fileURLWithPath: prefix)
                let node = url.appendingPathComponent("bin/node").resolvingSymlinksInPath()
                kegs.append(NodePrefixes.homebrewKeg(ofNode: node, prefix: url, homebrewRoots: homebrewRoots))
            }
        default:
            break
        }
        return Set(kegs.compactMap { $0.map(formula(ofKeg:)) })
    }

    /// `/opt/homebrew/Cellar/node@22/22.20.0` → `node@22`.
    static func formula(ofKeg keg: String) -> String {
        URL(fileURLWithPath: keg).deletingLastPathComponent().lastPathComponent
    }

    /// `oven-sh/bun/bun` → `bun`: kegs are named by the short name.
    public static func shortName(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    /// Run `attempt` until it starts its operation, waiting between tries for a
    /// change to what `inputs` reads (Observation). `attempt` returns true once it
    /// has claimed its run; it must claim in the same main-actor turn it decides
    /// in, so two waiters woken by one change cannot both start. It and `inputs`
    /// write observed state only when it changes, or two waiters wake each other
    /// for ever.
    @MainActor
    public static func waitForTurn(inputs: @escaping @MainActor () -> Void, attempt: @MainActor () -> Bool) async {
        while !attempt() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let pending = Pending(continuation)
                // Registered in the turn `attempt` failed in: no change can fall
                // between the two.
                withObservationTracking {
                    MainActor.assumeIsolated { inputs() }
                } onChange: {
                    pending.resume()
                }
            }
        }
    }

    /// A continuation resumed once, by the first change.
    private final class Pending: Sendable {
        private let continuation: Mutex<CheckedContinuation<Void, Never>?>
        init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = Mutex(continuation) }
        func resume() { continuation.withLock { $0.take() }?.resume() }
    }
}
