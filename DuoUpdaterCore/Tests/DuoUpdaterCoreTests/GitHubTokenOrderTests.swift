import Testing
import Foundation
@testable import DuoUpdaterCore

/// The resolution order, with Settings › GitHub's "Use the GitHub CLI’s sign-in"
/// on and off. The environment and `gh` are injected: nothing here reads the
/// host's environment or runs `gh`.
struct GitHubTokenOrderTests {

    /// Counts the times `gh auth token` would have run.
    final class CLI: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        var count: Int { lock.withLock { calls } }
        func token() -> String? { lock.withLock { calls += 1 }; return "from-gh" }
    }

    static func resolve(
        explicit: String? = nil, env: [String: String] = [:], usesCLI: Bool, cli: CLI
    ) async -> String? {
        await GitHubToken.resolve(explicit: explicit, usesCLI: usesCLI, environment: env, cli: { cli.token() })
    }

    /// On: explicit, then the environment, then `gh`. Each step is reached only
    /// when the ones before it have nothing.
    @Test func onTheCLIIsTheLastStep() async {
        let cli = CLI()
        #expect(await Self.resolve(explicit: "pasted", env: ["GH_TOKEN": "env"], usesCLI: true, cli: cli) == "pasted")
        #expect(await Self.resolve(env: ["GH_TOKEN": "env"], usesCLI: true, cli: cli) == "env")
        #expect(cli.count == 0)
        #expect(await Self.resolve(usesCLI: true, cli: cli) == "from-gh")
        #expect(cli.count == 1)
    }

    /// Off: `gh` is never asked; a pasted token and the environment still answer.
    /// Mutation: drop `guard usesCLI`.
    @Test func offTheCLIIsNeverAsked() async {
        let cli = CLI()
        #expect(await Self.resolve(usesCLI: false, cli: cli) == nil)
        #expect(await Self.resolve(explicit: "pasted", usesCLI: false, cli: cli) == "pasted")
        #expect(await Self.resolve(env: ["GITHUB_TOKEN": "env"], usesCLI: false, cli: cli) == "env")
        #expect(cli.count == 0)
    }
}
