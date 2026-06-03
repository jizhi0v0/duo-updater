import Foundation

/// Resolves a GitHub API token to lift the unauthenticated rate limit (60/hour)
/// to the authenticated one (5000/hour). Best-effort: returns nil if none is
/// found, and the GitHub source then falls back to unauthenticated requests.
///
/// Resolution order (first hit wins):
///   1. an explicit value (e.g. one the user set in settings),
///   2. the `GITHUB_TOKEN` / `GH_TOKEN` environment variables,
///   3. the `gh` CLI's stored login (`gh auth token`) — zero-config for the
///      many developers who already have GitHub CLI authenticated.
public enum GitHubToken {
    public static func resolve(explicit: String? = nil) -> String? {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        let env = ProcessInfo.processInfo.environment
        for key in ["GITHUB_TOKEN", "GH_TOKEN"] {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return ghCLIToken()
    }

    /// Ask the `gh` CLI for its stored token. Cheap subprocess; callers should
    /// resolve once per check run rather than per request.
    private static func ghCLIToken() -> String? {
        guard let gh = ghExecutablePath() else { return nil }
        guard let out = run(gh, ["auth", "token"]) else { return nil }
        let token = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: - gh CLI availability & login status (for Settings UI)

    /// What the `gh` CLI integration looks like right now — drives the GitHub
    /// settings panel's status line.
    public enum CLIStatus: Equatable, Sendable {
        /// `gh` isn't installed (no executable on the usual Homebrew paths).
        case notInstalled
        /// `gh` is installed but no account is logged in.
        case notLoggedIn
        /// `gh` is installed and authenticated. `username` is the logged-in
        /// account login when it can be parsed from `gh auth status`.
        case authenticated(username: String?)
    }

    /// Inspect the local `gh` CLI: installed? logged in? as whom? Runs two cheap
    /// subprocesses and parses `gh auth status`; call off the main thread.
    public static func cliStatus() -> CLIStatus {
        guard let gh = ghExecutablePath() else { return .notInstalled }
        // `gh auth status` writes its human-readable report to stderr and exits
        // non-zero when no account is logged in.
        let (output, ok) = runCapturingStderr(gh, ["auth", "status"])
        guard ok else { return .notLoggedIn }
        return .authenticated(username: parseLogin(from: output))
    }

    /// Pull the account login out of `gh auth status` output. Recent gh prints
    /// "Logged in to github.com account NAME (…)"; older builds say "as NAME".
    static func parseLogin(from status: String) -> String? {
        for marker in ["account ", " as "] {
            guard let range = status.range(of: marker) else { continue }
            let rest = status[range.upperBound...]
            let name = rest.prefix { !$0.isWhitespace }
            if !name.isEmpty { return String(name) }
        }
        return nil
    }

    // MARK: - Token verification (for Settings UI)

    /// Outcome of checking a pasted token against `api.github.com/user`.
    public enum Verification: Equatable, Sendable {
        /// Token is valid; `username` is the account it belongs to, and
        /// `scopes` is GitHub's reported scope list (empty for fine-grained
        /// tokens, which don't report classic scopes).
        case valid(username: String, scopes: [String])
        /// Token reached GitHub but was rejected (401/403).
        case invalid
        /// Couldn't reach GitHub / unexpected response. `message` is for display.
        case failed(message: String)
    }

    /// Verify a token by fetching the authenticated user. This is what lets the
    /// settings panel confirm a pasted token works — and show whose account it
    /// is — *before* persisting it.
    public static func verify(_ token: String) async -> Verification {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }

        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.updates.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(message: "Unexpected response from GitHub.")
            }
            switch http.statusCode {
            case 200:
                let login = (try? JSONDecoder().decode(GitHubUser.self, from: data))?.login ?? "?"
                let scopes = (http.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return .valid(username: login, scopes: scopes)
            case 401, 403:
                return .invalid
            default:
                return .failed(message: "GitHub returned HTTP \(http.statusCode).")
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    private struct GitHubUser: Decodable { let login: String }

    private static func ghExecutablePath() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Run `gh` capturing stdout; nil on launch failure or non-zero exit.
    private static func run(_ executable: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Run `gh` capturing stderr (where `gh auth status` reports); returns the
    /// text plus whether the command exited zero.
    private static func runCapturingStderr(_ executable: String, _ args: [String]) -> (String, Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let err = Pipe()
        process.standardOutput = Pipe()
        process.standardError = err
        do { try process.run() } catch { return ("", false) }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus == 0)
    }
}
