import Foundation

/// The GitHub token the app's own API requests carry, for the vendor update
/// commands that ask `api.github.com` themselves and read a token from their
/// environment: uv (`UV_GITHUB_TOKEN`), bun (`GITHUB_ACCESS_TOKEN`) and mise
/// (`MISE_GITHUB_TOKEN`). Without one they share the 60-an-hour anonymous budget
/// of every program behind this IP address.
///
/// The other tools' one-clicks need none (sources read 2026-10-11; Boat's from
/// its binary): deno, fx, flyctl, ghcup, herdr, lorca, luvus, rustup, Vite+,
/// Claude Code, Cursor, Junie, Amp, Boat, bub, npm, Helm, Starship, OpenCode
/// (given `--version`) and nvm fetch from their vendor's own servers, a
/// registry, `raw.githubusercontent.com` or `github.com` itself (release
/// downloads, git), none of which is the API. Codex's installer asks the API
/// only when `releases.openai.com` fails; zoxide's `install.sh` and `atuin
/// update` (axoupdater, which takes a token only from `set_github_token`)
/// always ask it, and none of the three reads a token.
enum CLIToolGitHubToken {

    typealias Source = @Sendable () async -> String?

    static let app: Source = unlessRejected(
        isRejected: { GitHubCredentials.shared.isRejected },
        resolve: { await ChangelogService.gitHubToken() })

    /// The token to hand on, or nil once GitHub has rejected it this round.
    /// `ChangelogService.gitHubToken()` keeps answering a revoked token for its
    /// cache's lifetime; the app's own requests then go out anonymously
    /// (`GitHubCredentials`), and the vendor's must too: a rejected token fails
    /// a release lookup an anonymous one would still be answered.
    static func unlessRejected(isRejected: @escaping @Sendable () -> Bool, resolve: @escaping Source) -> Source {
        { isRejected() ? nil : await resolve() }
    }
}
