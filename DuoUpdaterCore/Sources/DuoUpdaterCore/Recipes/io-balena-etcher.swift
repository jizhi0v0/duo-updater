import Foundation

enum io_balena_etcher {
    static let set = AppRecipeSet(
        family: "io-balena-etcher",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // balenaEtcher — an arm64 and an x64 dmg ship together (plus darwin zips of
        // the same builds), so the pattern pins the arm64 dmg.
        // One-click: io.balena.etcher, Team 66H43P8FRG, notarized.
        GitHubReleaseRule(
            bundleID: "io.balena.etcher",
            owner: "balena-io", repo: "etcher",
            installAssetPattern: #"^balenaEtcher-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
