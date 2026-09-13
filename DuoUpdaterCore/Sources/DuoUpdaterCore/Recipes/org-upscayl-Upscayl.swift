import Foundation

enum org_upscayl_Upscayl {
    static let set = AppRecipeSet(
        family: "org-upscayl-Upscayl",
        githubRules: [
        // Upscayl — org.upscayl.Upscayl, Team W2T4W74X87, notarized. (Homebrew's
        // cask says `org.upscayl.app`; the mounted bundle says otherwise, and the
        // bundle wins.) One universal dmg, no per-architecture asset — the name
        // carries no arch token to match on, and the post-download architecture
        // gate is what makes that safe.
        GitHubReleaseRule(
            bundleID: "org.upscayl.Upscayl",
            owner: "upscayl", repo: "upscayl",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^upscayl-[0-9.]+-mac\.dmg$"#,
            installerKind: .dmg),
        ])
}
