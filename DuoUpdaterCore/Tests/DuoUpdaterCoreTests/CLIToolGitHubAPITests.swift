import Testing
@testable import DuoUpdaterCore

/// Which tools' checks read the GitHub API — what the app's background check
/// holds back to every 15 minutes when no token resolves (`readsGitHubAPI`).
/// Only constructs the providers; nothing is scanned or checked.
struct CLIToolGitHubAPITests {

    /// Registered providers that use the GitHub release API for version checks.
    ///
    /// Mutation: drop `readsGitHubAPI` from any of these providers, or set it
    /// on another one.
    @Test func exactlyExpectedStandaloneProvidersReadTheGitHubAPI() {
        let providers = CLITools.standaloneProviders()
        #expect(Set(providers.map(\.kind)) == Set(CLIToolKind.allCases).subtracting([.managed]))
        #expect(Set(providers.filter(\.readsGitHubAPI).map(\.kind)) == [.bun, .opencode, .herdr, .zoxide, .nvm, .terminalMac, .multica, .nospeaker])
    }

    /// No manager's check asks api.github.com from our process (design §3.4):
    /// mise's own process may, with its own token chain, which is its
    /// `updaterSpendsGitHubAPI`, not this. Holds for every registered adapter.
    ///
    /// Mutation: set `readsGitHubAPI` on `ManagedProvider`.
    @Test func noManagedProviderReadsTheGitHubAPI() {
        #expect(ManagerRegistry.providers().allSatisfy { !$0.readsGitHubAPI })
        #expect(!ManagedProvider(ManagedModelTests.FakeAdapter()).readsGitHubAPI)
    }
}
