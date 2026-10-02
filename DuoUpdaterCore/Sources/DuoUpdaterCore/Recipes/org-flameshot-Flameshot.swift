import Foundation

enum org_flameshot_Flameshot {
    static let set = AppRecipeSet(
        family: "org-flameshot-Flameshot",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.
        // Shared rationale for digest-only: Recipes/org-alacritty.swift.

        // Flameshot — ad-hoc signed, no Team ID. One dmg per architecture
        // (`-macos-arm64`, `-macos-intel`); older releases put `-artifact` before
        // `-macos`, which `.+` covers. The `.sha256sum` siblings are not dmgs.
        GitHubReleaseRule(
            bundleID: "org.flameshot.Flameshot",
            owner: "flameshot-org", repo: "flameshot",
            installAssetPattern: #"^Flameshot-.+-macos-(arm64|intel)\.dmg$"#,
            installerKind: .dmg,
            installTrust: .publishedDigestOnly),
        ])
}
