import Foundation

/// Delegate to the vendor's atomic self-updater after authenticating the old
/// binary. Authenticate its result too. No shell, sudo, agent setup or hooks.
public struct LeafUpdater: Sendable {
    let scanner: LeafScanner
    let check: LeafCheck
    let verifier: LeafVerifier
    let busy: @Sendable () -> Bool
    let environment: @Sendable () -> [String: String]
    static let deadline = ChildProcess.Deadline(terminateAfter: .seconds(300), killAfter: .seconds(330))

    public init() {
        self.init(scanner: LeafScanner(), check: LeafCheck(), verifier: LeafVerifier(),
                  busy: { LeafActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
                  environment: { ProcessInfo.processInfo.childEnvironmentWithSystemProxy })
    }

    init(scanner: LeafScanner, check: LeafCheck, verifier: LeafVerifier,
         busy: @escaping @Sendable () -> Bool, environment: @escaping @Sendable () -> [String: String]) {
        self.scanner = scanner
        self.check = check
        self.verifier = verifier
        self.busy = busy
        self.environment = environment
    }

    public func update(_ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }) async -> CLIToolUpdateOutcome {
        guard status.oneClick != nil, case .leaf(let install) = status.detail,
              let before = install.version, let binary = install.binary, let target = install.target else { return .notOffered }
        let busy = self.busy
        if await offCooperativePool({ busy() }) { return .busy("Leaf is already being updated") }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.scan().first { $0.path == install.path } }), now == install else {
            return .failed(message: "not run: the Leaf install changed after it was checked", output: "")
        }
        let current = await check.status(of: now, busy: false, published: check.published())
        guard current.oneClick != nil else { return .failed(message: "not run: Leaf is no longer ready to update", output: "") }
        progress("Checking Leaf \(before) against its published SHA-256…")
        switch await verifier.verify(binary: binary, version: before, target: target) {
        case .matches: break
        case .differs(let reason), .couldNotVerify(let reason): return .failed(message: "not run: \(reason)", output: reason)
        }
        // Downloads may have taken seconds: recheck the file identity and busy
        // state before handing control to the verified executable.
        if await offCooperativePool({ busy() }) { return .busy("Leaf is already being updated") }
        guard let fresh = await offCooperativePool({ scanner.read(install.path) }), fresh == now,
              await offCooperativePool({ verifier.knownVerdict(binary: binary, version: before, target: target) }) == true else {
            return .failed(message: "not run: the verified Leaf file changed", output: "")
        }
        var environment = self.environment()
        environment["HOME"] = scanner.home.path
        environment["PATH"] = CLIToolCommandRunner.systemPath
        let childEnvironment = environment
        do {
            return try await InstallCommit.run("Leaf upgrade") {
                let run = await CLIToolCommandRunner.run(LeafCheck.command(binary), environment: childEnvironment,
                                                        deadline: Self.deadline, standardInput: Data(), progress: progress)
                guard case .finished(let outcome) = run.result else {
                    return .failed(message: "could not start leaf upgrade", output: run.text)
                }
                guard outcome.succeeded else {
                    return .failed(message: CLIToolCommandRunner.failureMessage(run.lines, outcome, deadline: Self.deadline), output: run.text)
                }
                guard let after = await offCooperativePool({ scanner.read(install.path) }),
                      let version = after.version, let newBinary = after.binary, let newTarget = after.target,
                      VersionComparator.compare(version, before) == .orderedDescending else {
                    return .failed(message: "leaf upgrade finished without leaving a newer readable Leaf", output: run.text)
                }
                switch await verifier.verify(binary: newBinary, version: version, target: newTarget) {
                case .matches: return .updated(version: version)
                case .differs(let reason), .couldNotVerify(let reason):
                    return .failed(message: "leaf upgrade finished, but \(reason)", output: run.text)
                }
            }
        } catch { return .failed(message: "Leaf update cancelled before starting", output: "") }
    }
}
