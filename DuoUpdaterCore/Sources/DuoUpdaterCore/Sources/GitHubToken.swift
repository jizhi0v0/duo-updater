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
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        guard let gh = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["auth", "token"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let token = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
