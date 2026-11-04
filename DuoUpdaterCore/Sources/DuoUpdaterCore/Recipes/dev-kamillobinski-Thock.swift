import Foundation

enum dev_kamillobinski_Thock {
    static let set = AppRecipeSet(
        family: "dev-kamillobinski-Thock",
        githubRules: [
        // Thock — the bundle declares
        // `SUFeedURL = https://github.com/kamillobinski/thock/releases/latest/download/appcast.xml`,
        // but no release ships an `appcast.xml` asset, so the Sparkle source gets a
        // 404 and the row was `.unknown` — no version, no notes.
        //
        // Tags are bare `1.23.0`; the release bodies carry the changelog and
        // `GitHubMarkdownParser` renders it. Detection-only: with the appcast
        // missing there is no signed feed to cross-check, and no installer was
        // verified here.
        GitHubReleaseRule(
            bundleID: "dev.kamillobinski.Thock",
            owner: "kamillobinski", repo: "thock",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#),
        ])
}
