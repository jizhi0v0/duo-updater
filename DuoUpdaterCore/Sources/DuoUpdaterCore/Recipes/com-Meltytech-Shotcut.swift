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
        // Prereleases (`v26.10.30`, `prerelease: true`, "beta" on the web site)
        // share the tag shape, the asset names and the bundle id, and their
        // bundle keeps a plain version: nothing local tells them apart. The beta
        // rule below proves a copy's track from GitHub's `prerelease` bit on its
        // exact tag; a copy this cannot prove answers here.
        GitHubReleaseRule(
            bundleID: "com.Meltytech.Shotcut",
            owner: "mltframework", repo: "shotcut",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^shotcut-macos-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg,
            assetVersionPattern: #"^shotcut-macos-([0-9]+(?:\.[0-9]+)+)\.dmg$"#),
        // Beta: a copy whose exact tag (`v` + its version) GitHub marks as a
        // prerelease. Shotcut versions are dates and every release, of either
        // kind, is numbered above the ones before it, so such a copy is offered
        // the newest release of any kind: the next prerelease, or the stable
        // release that follows it, after which it proves stable and answers on
        // the rule above. A respin's version names no tag of its own
        // (26.9.28 lives under `v26.9.27`), so it cannot be proven and answers
        // on the stable rule, as does a copy from before the dotted names
        // (short version `25.08`). Asset, kind and version reading are the
        // stable rule's; the prerelease dmg is the same id and Team, notarized.
        GitHubReleaseRule(
            bundleID: "com.Meltytech.Shotcut",
            owner: "mltframework", repo: "shotcut",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installedTagPrefix: "v",
            installAssetPattern: #"^shotcut-macos-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg,
            channel: .beta,
            assetVersionPattern: #"^shotcut-macos-([0-9]+(?:\.[0-9]+)+)\.dmg$"#),
        ],
        githubChannelProofs: [
        // Anchor, not artifact: the beta rule offers stable releases on purpose
        // (the graduation), so an artifact proof would fire on it. The track
        // itself is proven per copy by the exact-tag lookup.
        ChannelProofKey("com.Meltytech.Shotcut", .beta):
            .recipeAnchor(#"^true$"#, in: ["usePrereleases"]),
        ])
}
