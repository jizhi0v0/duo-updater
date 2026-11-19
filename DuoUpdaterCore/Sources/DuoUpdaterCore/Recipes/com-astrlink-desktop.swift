import Foundation

enum com_astrlink_desktop {
    static let set = AppRecipeSet(
        family: "com-astrlink-desktop",
        githubRules: [
        // AstrLink (Calcium-Ion/AstrLink, Team 7XWQYGN832, notarized) — a Tauri
        // local AI gateway. No SUFeedURL; its own updater (src-tauri/src/updates.rs)
        // reads the release's `latest.json`, which is Tauri-updater state, not a
        // feed we read. release-updates.mjs takes a SemVer tag, `v` optional (every
        // tag so far carries it), stamps it minus `v` into tauri.conf.json, so
        // CFBundleShortVersionString == CFBundleVersion == the tag's version, and
        // marks a SemVer pre-release tag (`-…`) as a GitHub pre-release and never
        // `latest`; the anchored pattern keeps those off the stable track.
        // Match both the legacy Tauri DMGs and the renamed DMGs. The shared
        // GitHub asset selector recognizes both sets of architecture markers.
        // History: docs/app-audits/com-astrlink-desktop.md#历史与实测
        GitHubReleaseRule(
            bundleID: "com.astrlink.desktop",
            owner: "Calcium-Ion", repo: "AstrLink",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^(?:AstrLink_[0-9][0-9A-Za-z.-]*_(?:aarch64|x64)|astrlink-[0-9]+(?:\.[0-9]+)+-(?:arm64|amd64))\.dmg$"#,
            installerKind: .dmg),
        ])
}
