import Testing
@testable import DuoUpdaterCore

/// Which tools' checks read the GitHub API — what the app's background check
/// holds back to every 15 minutes when no token resolves (`readsGitHubAPI`).
/// Only constructs the providers; nothing is scanned or checked.
struct CLIToolGitHubAPITests {

    /// Bun and OpenCode ask `releases/latest` on every check, Herdr when its
    /// manifests do not name the build (measured 2026-10-08). Every other tool's
    /// version source revalidates to 304 without the GitHub API.
    ///
    /// Mutation: drop `readsGitHubAPI` from any of the three providers, or set it
    /// on another one.
    @Test func exactlyBunOpenCodeAndHerdrReadTheGitHubAPI() {
        let providers: [any CLIToolProvider] = [
            ClaudeCodeProvider(), BubProvider(), FxProvider(), UvProvider(), JunieProvider(), RustProvider(), NpmProvider(),
            BoatProvider(), CodexProvider(), BunProvider(), OpencodeProvider(), CursorAgentProvider(), AmpProvider(),
            VitePlusProvider(), HerdrProvider(), LuvusProvider(), LorcaProvider(), FlyctlProvider(), HelmProvider(),
            StarshipProvider(),
        ]
        #expect(Set(providers.map(\.kind)) == Set(CLIToolKind.allCases))
        #expect(Set(providers.filter(\.readsGitHubAPI).map(\.kind)) == [.bun, .opencode, .herdr])
    }
}
