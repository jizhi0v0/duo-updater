import Foundation

/// Installs/upgrades a cask by delegating to the user's Homebrew, which handles
/// the download, checksum verification, and bundle replacement itself. We use
/// `install --cask --force` so it works whether or not the app was originally
/// installed through brew (our matching is by `.app` filename, not by brew's
/// own ledger).
public actor HomebrewInstaller {

    public init() {}

    public enum BrewError: LocalizedError {
        case brewNotFound
        case failed(code: Int32, output: String)
        /// brew exited 0 and the app is the bundle it was before: same version
        /// pair, same executable. `caskroomVersion` is what brew records as
        /// installed, nil when the Caskroom has no entry for the token.
        case unchanged(caskToken: String, onDisk: VersionSide, caskroomVersion: String?)

        public var errorDescription: String? {
            switch self {
            case .brewNotFound:
                return "Homebrew isn’t installed (no brew found in the usual locations)."
            case .failed(let code, let output):
                return HomebrewInstaller.failureDescription(code: code, output: output)
            case .unchanged(let token, let onDisk, let caskroomVersion):
                let disk = onDisk.text(withBuild: true)
                guard let caskroomVersion else {
                    return "brew exited without replacing the app: it is still \(disk) on disk"
                }
                return "brew considers \(token) current (Caskroom records \(caskroomVersion))"
                    + " while the app on disk is \(disk) — brew did not replace it"
            }
        }
    }

    /// What says whether brew's run replaced the bundle: both version fields,
    /// read from the Info.plist on disk, and the main executable's identity
    /// (`RuntimeVersion.executableIdentity`, size and modification time).
    /// The executable is there for a cask revision the bundle never carries
    /// (#1562): brew replaces the app and the version pair reads the same.
    struct BundleSnapshot: Equatable {
        var version: VersionSide
        var executable: String?

        static func read(_ app: URL) -> BundleSnapshot {
            let info = NSDictionary(contentsOf: BundleLayout.infoPlistURL(for: app)) as? [String: Any]
            let executable = AppRuntimeDetector.executableURL(
                bundleAt: app, infoPlist: info ?? [:], fm: FileManager.default)
            return BundleSnapshot(
                version: StagedRelaunch.diskVersionSide(app),
                executable: executable.flatMap { RuntimeVersion.executableIdentity(of: $0) })
        }

        /// Whether `after` is the same bundle as this one. False when either
        /// side could not be read: a cask renamed in its new version leaves
        /// nothing at the old path, and that is not "unchanged".
        func isUnchanged(_ after: BundleSnapshot) -> Bool {
            !version.isEmpty && executable != nil && self == after
        }
    }

    /// Test seam: the brew to run instead of ``brewPath()``. Bound per task;
    /// production never binds it.
    @TaskLocal static var brewPathOverride: String?

    /// The one-line description both `BrewError.failed` copies (this one and
    /// `BrewFormulaService.BrewError`) report. The popover and workbench rows render
    /// it with `.lineLimit(1)`, so there what comes first is all the user sees.
    ///
    /// brew's own `Error:` line leads when there is one. The last three lines used
    /// to lead, and brew puts its remediation after the error: a formula with no
    /// bottle on a machine with outdated Command Line Tools surfaced as
    /// `brew failed (1): Alternatively, manually download them from: …`, with
    /// `Error: Your Command Line Tools are too outdated.` eight lines up.
    /// The first `Error:` line, not the last: brew reports the cause first.
    ///
    /// ANSI escapes are stripped before the prefix check, not after: with
    /// `HOMEBREW_COLOR` set (it reaches `brew update` from the user's shell
    /// environment) brew writes `ESC[31mError:ESC[0m …`, which does not start with
    /// `Error:` until the escapes are gone.
    ///
    /// The old tail still follows the error, after ` — `: the same string is the
    /// popover's install-error tooltip, `duo install`'s `failed:` line and `--json`
    /// reason, and the install log, none of which truncate, and brew's remediation
    /// ("download the Command Line Tools for Xcode 27.0") is only in the tail. It
    /// is taken from the lines after the error line, so an error that is itself one
    /// of the last lines is not repeated. Without an `Error:` line this is exactly
    /// the old tail.
    static func failureDescription(code: Int32, output: String) -> String {
        let errorLine = output
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { MASInstaller.stripANSI(String($0)) }
            .first { $0.hasPrefix("Error:") }
        let lines = output.split(separator: "\n")
        guard let errorLine else {
            return "brew failed (\(code)): \(lines.suffix(3).joined(separator: " "))"
        }
        let error = errorLine.trimmingCharacters(in: .whitespaces)
        let at = lines.firstIndex { MASInstaller.stripANSI(String($0)).contains(errorLine) }
        let after = at.map { lines[lines.index(after: $0)...] } ?? lines[...]
        let tail = after.suffix(3).joined(separator: " ")
        return tail.isEmpty ? "brew failed (\(code)): \(error)" : "brew failed (\(code)): \(error) — \(tail)"
    }

    /// Run `brew install --cask --force <token>`, streaming output lines, and
    /// throw `BrewError.unchanged` when it exits 0 and `app` is still the
    /// bundle it was.
    ///
    /// Exit 0 is not proof of an update. `brew install` hands a cask that is
    /// already installed to its upgrade path, which skips one whose Caskroom
    /// version is current with `Warning: Not upgrading <token>, the latest
    /// version is already installed` and exits 0; `--force` only lets it
    /// overwrite existing files (Homebrew 7.0.10, `cmd/install.rb` and
    /// `cask/upgrade.rb`). Measured 2026-10-22: Caskroom at
    /// `hoppscotch-selfhost` 26.9.0-0, the app replaced by the vendor's 26.8.2,
    /// and this route reported it installed while 26.8.2 stayed on disk.
    public func upgrade(
        caskToken: String,
        app: URL,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        guard let brew = Self.brewPathOverride ?? Self.brewPath() else { throw BrewError.brewNotFound }

        // `--` terminates option parsing so a token can never be misread as a flag.
        let arguments = ["install", "--cask", "--force", "--", caskToken]
        // Non-interactive so brew never blocks on a prompt we can't answer.
        // We deliberately allow auto-update here: our detection reads the fresh
        // formulae.brew.sh API, so the local tap must refresh first or brew
        // might install a stale version (or think it's already current).
        var env = ProcessInfo.processInfo.environmentWithSystemProxy
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"
        // Lines, not chunks, and until the output ends, not just the exit — see
        // `StreamedLines`. Runs to completion if the caller is cancelled: this is
        // brew replacing what is installed, and a SIGKILL halfway is worse than
        // letting it finish (the `terminationHandler` wait it replaced was not
        // cancellable either).
        //
        // The whole brew run is this route's point of no return (`InstallCommit`):
        // brew's fetch and its swap are one command we cannot split, so a cancel
        // either stops the install before brew starts or is not seen at all.
        // The journal learns brew's pid, so a launch after this process was
        // killed leaves alone what a still-running brew is writing. Read here:
        // `onLaunch` runs in `ChildProcess`'s detached task, which has no
        // task-locals.
        let journal = InstallJournal.current
        let before = BundleSnapshot.read(app)
        try await InstallCommit.run("brew upgrade") { [env] in
            let (outcome, output) = try await StreamedLines.run(
                brew, arguments, environment: env, onOutput: onOutput,
                onLaunch: { journal?.noteChild($0) })
            // brew ran: a failure from here may have moved the old app aside
            // (its rescue does not always put it back), so it is no "nothing
            // changed". One that could not even start throws above, unmarked.
            InstallCommit.handedOver()

            guard outcome.succeeded else {
                throw BrewError.failed(code: outcome.terminationStatus, output: output)
            }
            if before.isUnchanged(BundleSnapshot.read(app)) {
                throw BrewError.unchanged(
                    caskToken: caskToken, onDisk: before.version,
                    caskroomVersion: BrewLocalInventory().installedVersion(caskToken: caskToken))
            }
        }
    }

    /// Locate brew at its fixed install prefixes: Apple Silicon default, then Intel
    /// default. Deliberately does NOT consult `$PATH`, so a `brew` planted earlier on
    /// the path can't be run.
    static func brewPath() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}
