import Foundation

/// What the menu-bar app's CLI surfaces and `duo` share about the tools as a
/// set: which providers there are, in what order, how they are asked at once,
/// and the rules a row is acted on by. Here rather than in the app so the two
/// hosts run one copy — `duo`'s contract is that a disagreement between it and
/// the app is a bug.
public enum CLITools {

    /// One provider per tool, in `CLIToolKind.allCases` order: what the app's
    /// `CLIToolsModel` asks by default, and what `duo` asks.
    public static func providers() -> [any CLIToolProvider] {
        inKindOrder([
            ClaudeCodeProvider(), BubProvider(), FxProvider(), UvProvider(), JunieProvider(), RustProvider(), NpmProvider(),
            BoatProvider(), CodexProvider(), BunProvider(), OpencodeProvider(), CursorAgentProvider(), AmpProvider(),
            VitePlusProvider(), HerdrProvider(), LuvusProvider(), LorcaProvider(), ZoxideProvider(), NvmProvider(),
            AtuinProvider(), GhcupProvider(),
            FlyctlProvider(), HelmProvider(), StarshipProvider(),
            DenoProvider(), MiseProvider(),
        ])
    }

    /// `providers` in `CLIToolKind.allCases` order, two of one kind in the order
    /// given: every report and scan is put in that order, whichever provider
    /// answers first.
    public static func inKindOrder(_ providers: [any CLIToolProvider]) -> [any CLIToolProvider] {
        let order = CLIToolKind.allCases
        return providers.enumerated().sorted {
            let (a, b) = (order.firstIndex(of: $0.element.kind)!, order.firstIndex(of: $1.element.kind)!)
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
    }

    /// `work` run on the providers at `indices` at once, each answer with its
    /// provider's index, in `providers` order.
    public static func inProviderOrder<T: Sendable>(
        _ providers: [any CLIToolProvider], _ indices: [Int],
        _ work: @escaping @Sendable (any CLIToolProvider) async -> T
    ) async -> [(Int, T)] {
        await withTaskGroup(of: (Int, T).self) { group in
            for index in indices {
                let provider = providers[index]
                group.addTask { (index, await work(provider)) }
            }
            var answers: [(Int, T)] = []
            for await answer in group { answers.append(answer) }
            return answers.sorted { $0.0 < $1.0 }
        }
    }

    /// What one install's requests are filed under in the request log: the
    /// package or toolchain when the row is one (`openclaw`, `rustup`), else the
    /// tool (`Claude Code`).
    public static func attributionID(_ status: CLIToolStatus) -> String {
        status.name ?? status.kind.displayName
    }

    /// What an update that exited 0 amounts to. Exit 0 is not proof of an
    /// update: measured, `claude update` exits 0 having stayed put ("… predates
    /// release-signature enforcement; staying on X"), and the updater then
    /// reports the version it left. Only a version other than the one clicked on
    /// counts. `after` is the updater's own re-read, else a fresh check's.
    public enum Settled: Equatable, Sendable {
        /// The copy now reads as this version.
        case updated(String)
        /// The copy still reads as the version it had.
        case unchanged(String)
        /// The copy's version could not be read afterwards.
        case unreadable
    }

    public static func settle(before: String?, after: String?) -> Settled {
        guard let after else { return .unreadable }
        return after != before ? .updated(after) : .unchanged(after)
    }
}

extension CLIToolStatus {
    /// Whether Update All runs this copy: an update is offered and it does not
    /// need an administrator password (`needsAdministrator`). Each of those asks
    /// on its own row's click, so a batch never raises a panel, let alone a stack
    /// of them; and one panel for the whole batch would run every such command as
    /// root on a single answer about none of them in particular.
    public var joinsUpdateAll: Bool { oneClick != nil && !needsAdministrator }

    /// The command to copy beside an update the user turned the tool's
    /// auto-update off for — the same command a one-click would run. nil
    /// otherwise: every other gate means it should not be run now, or it is
    /// DuoUpdater's to run.
    ///
    /// Some checks also hand theirs out where DuoUpdater will not run the update
    /// itself, and the vendor's documented command is the way forward: nvm,
    /// zoxide, Helm and Starship when their directory needs `sudo` (`NvmCheck`,
    /// `ZoxideCheck`, `HelmCheck`, `StarshipCheck`); zoxide when what its
    /// installer leaves could not be checked; flyctl on the `pre` channel
    /// (`FlyctlCheck`). A check sets the command only then — never beside a
    /// running update — so here the gate only has to rule out the others.
    ///
    /// Beside an update that asks for an administrator password: the same
    /// command, for a terminal, as the way to take it without DuoUpdater.
    public var commandToCopy: CLIToolCommand? {
        guard state == .updateAvailable else { return nil }
        if needsAdministrator { return manualCommand }
        guard let withheld, [.autoUpdateOff, .unsupportedInstaller, .unverified].contains(withheld)
        else { return nil }
        return manualCommand
    }
}

/// How the update commands `CLIToolCommandRunner` ran ended, for a host that
/// shows more than the line a failure is summed up by. `duo` sets `observer`
/// around a provider's `update`, so a failed update prints the vendor's exit
/// status beside its last line; the app sets none.
public enum CLIToolExit {
    public struct Status: Sendable, Equatable {
        public let executable: String
        /// The exit code, or the signal number when `signal`.
        public let status: Int32
        public let signal: Bool
        public let timedOut: Bool

        public init(executable: String, status: Int32, signal: Bool, timedOut: Bool) {
            self.executable = executable
            self.status = status
            self.signal = signal
            self.timedOut = timedOut
        }
    }

    @TaskLocal public static var observer: (@Sendable (Status) -> Void)?

    static func report(_ command: CLIToolCommand, _ outcome: ChildProcess.Outcome) {
        observer?(Status(executable: command.executable, status: outcome.terminationStatus,
                         signal: outcome.uncaughtSignal, timedOut: outcome.timedOut))
    }
}
