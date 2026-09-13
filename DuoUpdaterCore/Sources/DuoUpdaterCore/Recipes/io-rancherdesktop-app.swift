import Foundation

enum io_rancherdesktop_app {
    static let set = AppRecipeSet(
        family: "io-rancherdesktop-app",
        githubRules: [
        // MARK: - 2026-08-16, second pass
        //
        // These five — this file, `Recipes/com-kangfenmao-CherryStudio.swift`,
        // `Recipes/org-RedisLabs-RedisInsight-V2.swift`, `Recipes/org-upscayl-Upscayl.swift`
        // and `Recipes/io-github-wickenico-wailbrew.swift` — reached the earlier sweep's
        // "unclassified" pile only because
        // their artifact was too big to download that day — nothing about them is
        // hard. Each of their rules again states what was read off the very asset the
        // pattern selects, on a mounted copy of the real download.

        // Rancher Desktop — io.rancherdesktop.app, Team 2Q6FHJR3H3, notarized.
        // The release also ships a `-mac.aarch64.zip`; the dmg is the cask's choice
        // and the one verified here.
        GitHubReleaseRule(
            bundleID: "io.rancherdesktop.app",
            owner: "rancher-sandbox", repo: "rancher-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Rancher\.Desktop-[0-9.]+\.aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
