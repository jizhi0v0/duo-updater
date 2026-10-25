import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `duo` follows the app's GitHub sign-in settings: the "Use the GitHub CLI's
/// sign-in" switch and the token pasted into Settings.
///
/// Both live in Core as process globals the app fills from `Preferences`. `duo`
/// only used them for `Settings.githubToken`, so the paths that ask the globals —
/// `GitHubToken.resolve()` in `duo verify`, and the uv, bun and mise token
/// hand-off in `duo install` — still read `GH_TOKEN` and ran `gh` for a user who
/// had turned both off.
///
/// The Keychain is injected and the preferences domain is a scratch suite, so
/// nothing here reads the user's token or raises a prompt. `GH_TOKEN` is set in
/// this process only, hence the serialized suite.
@Suite(.serialized) struct SettingsGitHubSignInTests {

    /// Runs `body` with `GH_TOKEN` set to `value`, or unset, and the globals at
    /// their defaults before and after.
    private func withEnvironmentToken(_ value: String? = "token-from-the-environment",
                                      _ body: () async -> Void) async {
        let previous = ProcessInfo.processInfo.environment["GH_TOKEN"]
        if let value { setenv("GH_TOKEN", value, 1) } else { unsetenv("GH_TOKEN") }
        GitHubToken.setUsesCLI(true)
        ChangelogService.setExplicitGitHubToken(nil)
        await body()
        GitHubToken.setUsesCLI(true)
        ChangelogService.setExplicitGitHubToken(nil)
        if let previous { setenv("GH_TOKEN", previous, 1) } else { unsetenv("GH_TOKEN") }
    }

    /// Mutation: drop the `GitHubToken.setUsesCLI` call from `load`.
    @Test func loadingSettingsAppliesTheSwitchToTheTokenHandOff() async {
        let scratch = ScratchDefaults("github-sign-in-load")
        defer { scratch.clear() }
        scratch.defaults.set(false, forKey: GitHubToken.usesCLIKey)

        await withEnvironmentToken {
            let settings = await Settings.load(defaults: scratch.defaults, keychain: { _ in nil })
            #expect(settings.githubToken == nil)
            #expect(GitHubToken.preresolved() == nil)
            #expect(await CLITools.vendorUpdatersGetOurToken() == false)
        }
    }

    /// Mutation: drop the `ChangelogService.setExplicitGitHubToken` call from `load`.
    @Test func theTokenFromSettingsReachesTheTokenHandOffWithTheSwitchOff() async {
        let scratch = ScratchDefaults("github-sign-in-explicit")
        defer { scratch.clear() }
        scratch.defaults.set(false, forKey: GitHubToken.usesCLIKey)

        // No GH_TOKEN: without the hand-off the globals would send this to `gh`.
        await withEnvironmentToken(nil) {
            let settings = await Settings.load(
                defaults: scratch.defaults,
                keychain: { $0 == "github-token" ? "token-from-settings" : nil })
            #expect(settings.githubToken == "token-from-settings")
            #expect(await CLITools.vendorUpdatersGetOurToken() == true)
        }
    }

    /// `duo verify` never loads settings, so `main` applies the switch alone.
    /// Mutation: make `configureGitHubSignIn(defaults:)` do nothing.
    @Test func theSwitchAloneIsAppliedWithoutLoadingSettings() async {
        let scratch = ScratchDefaults("github-sign-in-switch")
        defer { scratch.clear() }

        await withEnvironmentToken {
            Settings.configureGitHubSignIn(defaults: scratch.defaults)
            // Absent reads as on.
            #expect(GitHubToken.preresolved() == "token-from-the-environment")
            scratch.defaults.set(false, forKey: GitHubToken.usesCLIKey)
            Settings.configureGitHubSignIn(defaults: scratch.defaults)
            #expect(GitHubToken.preresolved() == nil)
            #expect(await GitHubToken.resolve() == nil)
        }
    }
}
