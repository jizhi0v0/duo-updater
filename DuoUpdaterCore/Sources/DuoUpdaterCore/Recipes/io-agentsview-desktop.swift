import Foundation

enum io_agentsview_desktop {
    static let set = AppRecipeSet(
        family: "io-agentsview-desktop",
        githubRules: [
        // History: docs/app-audits/io-agentsview-desktop.md#历史与实测
        // AgentsView — browser for past AI coding sessions, no SUFeedURL,
        // GitHub v-tags. Some releases ship no mac dmg at all (v0.41.0 and
        // v0.33.1 were tar.gz-only; History has the count when this was written)
        // — the release walk skips them and one-click lands on the newest
        // dmg-bearing release, same semantics the cask livecheck encodes. The
        // aarch64 dmg is arm64-only
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
