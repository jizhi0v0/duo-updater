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
        // The arm64 dmg ships with the release; the x64 dmg is attached later by
        // release-macos-x86_64.yml, and v0.2.5 never got one — an Intel Mac then
        // sees "nothing to offer", not a broken rule.
        GitHubReleaseRule(
            bundleID: "com.astrlink.desktop",
            owner: "Calcium-Ion", repo: "AstrLink",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^AstrLink_[0-9][0-9A-Za-z.-]*_(?:aarch64|x64)\.dmg$"#,
            installerKind: .dmg),
        ])
}
