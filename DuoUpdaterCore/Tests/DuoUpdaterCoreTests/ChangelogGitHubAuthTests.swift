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
