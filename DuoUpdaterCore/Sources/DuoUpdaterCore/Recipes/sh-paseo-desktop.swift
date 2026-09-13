import Foundation

enum sh_paseo_desktop {
    static let set = AppRecipeSet(
        family: "sh-paseo-desktop",
        githubRules: [
        // Paseo — self-hosted daemon/desktop for AI coding agents. Stable v-tags
        // plus a beta train cut as prerelease releases (`v0.7.0-beta.2`, assets
        // `beta-mac.yml` + dmg) — the anchored stable pattern rejects the beta
        // suffix and /releases/latest excludes prereleases anyway, so the stable
        // rule never serves a beta. One-click pins the arm64 dmg (the deb/
        // AppImage siblings are Linux). Mounted v0.6.1: sh.paseo.desktop, short
        // == build == tag, Team 99ZMJMKU9Y, notarized.
        GitHubReleaseRule(
            bundleID: "sh.paseo.desktop",
            owner: "getpaseo", repo: "paseo",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Paseo-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
