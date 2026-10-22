import Foundation

enum com_bradenwong_whispering {
    static let set = AppRecipeSet(
        family: "com-bradenwong-whispering",
        githubRules: [
        // Whispering — push-to-talk transcription, a Tauri 2 app in the
        // EpicenterHQ/epicenter monorepo (formerly braden-w/whispering, now
        // archived; `epicenter-os/epicenter` redirects here). Its own updater is
        // tauri-plugin-updater reading this repo's `/releases/latest/download/
        // latest.json`; it only downloads when the user clicks Install Update,
        // and swaps the bundle in the same call, so nothing is left parked.
        //
        // Tags read `v7.11.0`, the bundle says 7.11.0. Not read on purpose:
        // `models/parakeet-…` (model weights) and `feature/whi-61-…` (a 2024
        // branch build of 4.7.1), and `_assets` is a prerelease. If one of them
        // ever becomes `/releases/latest`, it carries no matching dmg and the
        // rule walks the list back to the newest Whispering release.
        // 7.6.0–7.7.1 named their dmg `…_aarch64_darwin.dmg`; 7.10.0 shipped
        // only an x64 dmg and is skipped as no Apple-silicon build.
        // One-click: com.bradenwong.whispering, Team 3C7J97QA5Z, notarized,
        // from 4.7.3 on (4.0.0–4.7.2 are ad-hoc, refused by the Team gate).
        GitHubReleaseRule(
            bundleID: "com.bradenwong.whispering",
            owner: "EpicenterHQ", repo: "epicenter",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Whispering_[0-9]+(?:\.[0-9]+)+_aarch64(?:_darwin)?\.dmg$"#,
            installerKind: .dmg),
        ])
}
