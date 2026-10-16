import Foundation

enum com_kruszoneq_macUSB {
    static let set = AppRecipeSet(
        family: "com-kruszoneq-macUSB",
        githubRules: [
        // macUSB (Kruszoneq/macUSB, Team 27NC66L8P2, notarized from 2.0) — a
        // bootable-USB creator with no SUFeedURL. Its own "check for updates"
        // (UpdateChecker.swift) reads `version.json` on `main`, whose `url` is
        // this repo's `/releases/latest`; tags are `v<CFBundleShortVersionString>`
        // (two- and three-part: v2.5, v2.3.1). No pre-release has been published;
        // the anchored pattern keeps a future `-rc`/`-beta` tag off the stable
        // track. One universal dmg per release since v1.1.2 (`macUSB.2.5.dmg`);
        // v1.0–v1.1.1 shipped zips that the latest release never offers.
        GitHubReleaseRule(
            bundleID: "com.kruszoneq.macUSB",
            owner: "Kruszoneq", repo: "macUSB",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^macUSB\.[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
