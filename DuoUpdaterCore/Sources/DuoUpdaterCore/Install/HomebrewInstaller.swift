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
                let tail = output.split(separator: "\n").suffix(3).joined(separator: " ")
                return "brew failed (\(code)): \(tail)"
            }
        }
    }

    /// Run `brew install --cask --force <token>`, streaming output lines.
    public func upgrade(
        caskToken: String,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws {
        guard let brew = Self.brewPath() else { throw BrewError.brewNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["install", "--cask", "--force", caskToken]
        // Non-interactive so brew never blocks on a prompt we can't answer.
        // We deliberately allow auto-update here: our detection reads the fresh
        // formulae.brew.sh API, so the local tap must refresh first or brew
        // might install a stale version (or think it's already current).
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collected = OutputBox()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            collected.append(text)
            for line in text.split(separator: "\n") {
                onOutput(String(line))
            }
        }

        try process.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        handle.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw BrewError.failed(code: process.terminationStatus, output: collected.text)
        }
    }

    /// Thread-safe accumulator for the brew output streamed off a background
    /// readability handler.
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = ""
        func append(_ s: String) { lock.lock(); buffer += s; lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return buffer }
    }

    /// Locate brew: Apple Silicon default, then Intel default, then PATH.
    static func brewPath() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}
