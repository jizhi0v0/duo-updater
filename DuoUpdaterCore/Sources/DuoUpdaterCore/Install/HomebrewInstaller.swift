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

        public var errorDescription: String? {
            switch self {
            case .brewNotFound:
                return "Homebrew isn’t installed (no brew found in the usual locations)."
            case .failed(let code, let output):
                return HomebrewInstaller.failureDescription(code: code, output: output)
            }
        }
    }

    /// The one-line description both `BrewError.failed` copies (this one and
    /// `BrewFormulaService.BrewError`) report. Every surface renders it with
    /// `.lineLimit(1)`, so what comes first is all the user sees.
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
    /// Without an `Error:` line this is exactly the old tail. The full output stays
    /// in the `output` payload; nothing reads it from the description.
    static func failureDescription(code: Int32, output: String) -> String {
        let errorLine = output
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { MASInstaller.stripANSI(String($0)) }
            .first { $0.hasPrefix("Error:") }
        if let errorLine {
            return "brew failed (\(code)): \(errorLine.trimmingCharacters(in: .whitespaces))"
        }
        let tail = output.split(separator: "\n").suffix(3).joined(separator: " ")
        return "brew failed (\(code)): \(tail)"
    }

    /// Run `brew install --cask --force <token>`, streaming output lines.
    public func upgrade(
        caskToken: String,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        guard let brew = Self.brewPath() else { throw BrewError.brewNotFound }

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
        let (outcome, output) = try await StreamedLines.run(
            brew, arguments, environment: env, onOutput: onOutput)

        guard outcome.succeeded else {
            throw BrewError.failed(code: outcome.terminationStatus, output: output)
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
