import Foundation

enum com_meetily_ai {
    static let set = AppRecipeSet(
        family: "com-meetily-ai",
        githubRules: [
        // Meetily — local-first AI meeting transcription (Tauri). No SUFeedURL
        // (the release's `latest.json` is Tauri-updater state, not a feed we
        // read). v-tags with one legacy bare tag (`0.1.1`) deep in history —
        // /releases/latest returns the newest stable v-tag regardless. One
        // -click pins the aarch64 dmg (arm64-only; the x64 setup.exe/msi
        // siblings are Windows). Mounted v0.4.0: com.meetily.ai, short ==
        // build == tag, Team 554AZZ38TB, notarized.
        GitHubReleaseRule(
            bundleID: "com.meetily.ai",
            owner: "Zackriya-Solutions", repo: "meetily",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^meetily_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
