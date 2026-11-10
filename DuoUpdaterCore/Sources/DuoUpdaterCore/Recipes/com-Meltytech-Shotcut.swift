import Foundation

enum com_Meltytech_Shotcut {
    static let set = AppRecipeSet(
        family: "com-Meltytech-Shotcut",
        githubRules: [
        // History: docs/app-audits/com-Meltytech-Shotcut.md#历史与实测
        //
        // Shotcut — Qt/MLT video editor (GPL). No Sparkle, no SUFeedURL. Its own
        // "check for updates" reads https://check.shotcut.org/version.json and,
        // when that names a newer version, shows a status-bar link that opens
        // the web site (`MainWindow::onUpgradeTriggered` → `Util::openUrl`): it
        // notifies only, never downloads or installs.
        //
        // The tag is NOT always the installed version. Meltytech respins under
        // the old tag with a new version: `v26.9.27` carries
        // `shotcut-macos-26.9.27.dmg` and, a day later, `shotcut-macos-26.9.28.dmg`,
        // whose bundle says 26.9.28 in both version keys. `installableAsset`
        // already installs the highest-named file; `assetVersionPattern` makes
        // the OFFER read that same file, so a 26.9.27 copy is offered 26.9.28
        // and a 26.9.28 copy is up to date. Read from the tag alone, the 26.9.27
        // copy would be called up to date for good.
        //
        // The install pattern keeps the dotted release dmg only: it leaves out
        // `shotcut-macos-unsigned-*.dmg` (an unsigned build shipped beside most
        // releases), `-resigned` respins, and the YYMMDD names releases used up
        // to 25.08.16 (`shotcut-macos-250816.dmg`), none of which a stable
        // `/releases/latest` answer carries today. The dmg is universal;
        // com.Meltytech.Shotcut, Team Y6RX44QG2G, Notarized Developer ID —
        // checked on 26.9.28, 26.9.27, 26.8.1, 25.08.16 and 24.04.28.
        //
        // Prereleases (`v26.10.30`, `prerelease: true`) share the tag shape, the
        // asset names and the bundle id, and their bundle keeps a plain version,
        // so a copy installed from one reads as stable. That is safe by
        // comparison: each prerelease so far was followed by a higher stable
        // release, so such a copy is up to date until then and is offered that
        // stable, never anything older. No beta rule (audit: 待用户决定).
        GitHubReleaseRule(
            bundleID: "com.Meltytech.Shotcut",
            owner: "mltframework", repo: "shotcut",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^shotcut-macos-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg,
            assetVersionPattern: #"^shotcut-macos-([0-9]+(?:\.[0-9]+)+)\.dmg$"#),
        ])
}
