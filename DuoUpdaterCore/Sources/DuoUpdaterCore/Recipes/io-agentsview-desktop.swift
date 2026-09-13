import Foundation

enum io_agentsview_desktop {
    static let set = AppRecipeSet(
        family: "io-agentsview-desktop",
        githubRules: [
        // AgentsView — browser for past AI coding sessions, no SUFeedURL,
        // GitHub v-tags. Two of the last forty releases shipped no mac dmg at
        // all (v0.41.0 and v0.33.1 were tar.gz-only) — the release walk skips
        // them and one-click lands on the newest dmg-bearing release, same
        // semantics the cask livecheck encodes. The aarch64 dmg is arm64-only
        // (AgentsView_{v}_x64.dmg is the Intel twin); Team 2YMZH84KR8,
        // notarized. Mounted v0.41.1: io.agentsview.desktop, short == build.
        GitHubReleaseRule(
            bundleID: "io.agentsview.desktop",
            owner: "kenn-io", repo: "agentsview",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^AgentsView_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
