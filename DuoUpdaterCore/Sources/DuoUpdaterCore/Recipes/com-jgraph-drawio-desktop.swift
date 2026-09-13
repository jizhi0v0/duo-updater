import Foundation

enum com_jgraph_drawio_desktop {
    static let set = AppRecipeSet(
        family: "com-jgraph-drawio-desktop",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // draw.io desktop — each release ships arm64/x64/universal dmgs, arm64 and
        // x64 zips and a Windows zip; the pattern pins the arm64 dmg (the universal
        // one is 100 MB larger for no benefit here). One-click: com.jgraph.drawio.desktop,
        // Team UZEUFB4N53, notarized.
        GitHubReleaseRule(
            bundleID: "com.jgraph.drawio.desktop",
            owner: "jgraph", repo: "drawio-desktop",
            installAssetPattern: #"^draw\.io-arm64-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
