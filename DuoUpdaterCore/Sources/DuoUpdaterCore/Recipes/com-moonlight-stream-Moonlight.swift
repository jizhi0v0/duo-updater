import Foundation

enum com_moonlight_stream_Moonlight {
    static let set = AppRecipeSet(
        family: "com-moonlight-stream-Moonlight",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Moonlight — game streaming client. The release also carries
        // `Moonlight-SteamLink-<ver>.zip` and `MoonlightPortable-*` builds, which are
        // different targets; the `^Moonlight-<ver>.dmg$` anchor takes only the Mac app.
        // One-click: com.moonlight-stream.Moonlight, Team 45U78722YL, notarized.
        GitHubReleaseRule(
            bundleID: "com.moonlight-stream.Moonlight",
            owner: "moonlight-stream", repo: "moonlight-qt",
            installAssetPattern: #"^Moonlight-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
