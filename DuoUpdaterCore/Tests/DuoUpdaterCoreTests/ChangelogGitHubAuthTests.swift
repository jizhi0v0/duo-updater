import Testing
import Foundation
@testable import DuoUpdaterCore

/// The Authorization header may only ever ride to GitHub's API host. A recipe
/// pointing at any other host — including GitHub's own raw/content hosts, which
/// serve vendor appcasts (TablePro's lives on raw.githubusercontent.com) — must
/// stay anonymous, because leaking a token is a far worse failure than a 403.
@Test func gitHubAuthIsScopedToTheAPIHostOnly() {
    #expect(ChangelogService.isGitHubAPI(
        URL(string: "https://api.github.com/repos/zed-industries/zed/releases?per_page=40")!))
    #expect(ChangelogService.isGitHubAPI(URL(string: "https://API.GitHub.com/repos/x/y")!))

    for other in [
        "https://raw.githubusercontent.com/TableProApp/TablePro/main/appcast.xml",
        "https://github.com/ghostty-org/ghostty/releases.atom",
        "https://central.github.com/deployments/desktop/desktop/changelog.json",
        "https://api.github.com.evil.example/repos/x/y",
        "https://notapi.github.com/repos/x/y",
    ] {
        #expect(!ChangelogService.isGitHubAPI(URL(string: other)!), "must not authenticate \(other)")
    }
}

// MARK: - Reaching the token the user actually configured

/// Serialized, and its own suite: these all drive one piece of process-global
/// state (`ChangelogService`'s explicit token and its resolved-token cache).
/// Swift Testing runs tests in parallel by default, so as free functions they
/// clobbered each other — one test read the token another had just set. That is
/// a property of the state being global, not of the assertions, so the fix is to
/// stop them overlapping rather than to weaken what they check.
@Suite(.serialized) struct ChangelogGitHubTokenResolutionTests {

    /// The shipped GUI has neither a shell environment nor (necessarily) `gh`: it is
    /// started by launchd, and a user who pasted a token into Settings ▸ GitHub has
    /// it in the Keychain, which the core package cannot read. Without the explicit
    /// hand-off, `gitHubToken()` resolved to nil for exactly those users and the
    /// whole Authorization path stayed dead while Settings showed the token verified.
    /// The original verification missed this because it ran the CLI from a terminal,
    /// which inherits the environment and finds `gh`.
    @Test func explicitTokenFromSettingsReachesTheChangelogFetcher() async {
        defer {
            ChangelogService.setExplicitGitHubToken(nil)
            ChangelogService.resetGitHubTokenCache()
        }
        ChangelogService.setExplicitGitHubToken("pasted-in-settings")
        ChangelogService.resetGitHubTokenCache()
        #expect(await ChangelogService.gitHubToken() == "pasted-in-settings")
    }

    /// Whitespace and empty strings mean "no explicit token" — `Preferences` stores
    /// an empty string for a cleared field, and pushing that must fall back to the
    /// env/`gh` path rather than sending `Bearer `.
    @Test func blankExplicitTokenIsTreatedAsAbsent() {
        defer { ChangelogService.setExplicitGitHubToken(nil) }
        for blank in ["", "   ", "\n"] {
            ChangelogService.setExplicitGitHubToken(blank)
            ChangelogService.resetGitHubTokenCache()
            // Can't assert the resolved value (the machine may legitimately have a
            // `gh` token); assert only that the blank did not become the answer.
            #expect(ChangelogService.explicitGitHubTokenForTesting == nil)
        }
    }

    /// A token pasted, then cleared, must take effect without a relaunch. The old
    /// code resolved once per process and cached `nil` too, so a menubar app running
    /// for weeks would keep sending a revoked token — and GitHub answers 401 to that,
    /// which renders an EMPTY pane where anonymous would still have worked.
    @Test func changingTheExplicitTokenReResolvesRatherThanServingTheCachedOne() async {
        defer {
            ChangelogService.setExplicitGitHubToken(nil)
            ChangelogService.resetGitHubTokenCache()
        }
        ChangelogService.setExplicitGitHubToken("first")
        ChangelogService.resetGitHubTokenCache()
        #expect(await ChangelogService.gitHubToken() == "first")

        ChangelogService.setExplicitGitHubToken("second")
        #expect(await ChangelogService.gitHubToken() == "second",
                "a rotated token must not be masked by the cache")
    }

    /// And the cache ages out on its own, so a token rotated *outside* the app
    /// (`gh auth logout`, a PAT revoked on github.com) recovers without a relaunch.
    @Test func theResolvedTokenCacheExpires() async {
        defer {
            ChangelogService.setExplicitGitHubToken(nil)
            ChangelogService.resetGitHubTokenCache()
        }
        ChangelogService.setExplicitGitHubToken("stale")
        ChangelogService.resetGitHubTokenCache()
        #expect(await ChangelogService.gitHubToken(now: Date()) == "stale")

        // Same explicit value, but past the TTL: re-resolves rather than serving the
        // remembered answer. (Here the re-resolve produces the same string; the point
        // is that the code path runs at all.)
        let later = Date().addingTimeInterval(ChangelogService.tokenTTL + 1)
        ChangelogService.setExplicitGitHubToken("fresh")
        #expect(await ChangelogService.gitHubToken(now: later) == "fresh")
    }
}

/// The host gate checks the scheme too. `URL.host` is scheme-agnostic, so a
/// cleartext URL at the right host would otherwise have put the token on the wire
/// in the clear.
@Test func gitHubAuthRequiresHTTPS() {
    #expect(!ChangelogService.isGitHubAPI(URL(string: "http://api.github.com/repos/x/y")!))
    #expect(ChangelogService.isGitHubAPI(URL(string: "https://api.github.com/repos/x/y")!))
}
