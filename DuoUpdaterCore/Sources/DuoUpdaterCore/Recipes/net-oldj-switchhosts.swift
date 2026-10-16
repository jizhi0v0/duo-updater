import Foundation

enum net_oldj_switchhosts {
    static let set = AppRecipeSet(
        family: "net-oldj-switchhosts",
        githubRules: [
        // SwitchHosts (oldj/SwitchHosts, Team J5J6USUX2F, notarized) — a hosts
        // file manager, rewritten in Tauri for v5. Its own updater is the Tauri
        // updater reading `/releases/latest/download/latest.json`
        // (src-tauri/tauri.conf.json), i.e. this repo's newest non-prerelease;
        // there is no beta switch in the app. `npm version` stamps package.json's
        // version into tauri.conf.json, and release.yml refuses a tag that
        // differs from it, so CFBundleShortVersionString == CFBundleVersion ==
        // the tag minus `v` (real 5.0.1 / 5.0.2 / 5.0.3-beta.3 bundles). Every
        // non-prerelease tag back to v3.0.0 is `vX.Y.Z`; the release workflow
        // marks a tag with a `-` suffix as prerelease, and the pattern is
        // `$`-anchored so `v5.0.3-beta.3` never reads as stable.
        //
        // Copies before v4.3.0 (Electron) are bundle id `SwitchHosts`, the same
        // Team; `BundleIDMigration` files them under this rule. v5 migrates the
        // v4 data on first launch (`src-tauri/src/migration`).
        //
        // One-click takes the universal dmg (one per release since
        // 5.0.0-beta.22, beside `-mac-aarch64.dmg` / `-mac-x64.dmg`). The bundle
        // carries an SMAppService LaunchDaemon (`swh_helper`, registered only
        // when the user first writes /etc/hosts); the Tauri updater swaps the
        // bundle in place the same way, and the app re-checks the helper's
        // protocol version on every status probe. See the audit, 一键安装.
        GitHubReleaseRule(
            bundleID: "net.oldj.switchhosts",
            owner: "oldj", repo: "SwitchHosts",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^SwitchHosts-[0-9][0-9A-Za-z.-]*-mac-universal\.dmg$"#,
            installerKind: .dmg),

        // SwitchHosts beta — the GitHub prereleases (`v5.0.3-beta.3`). A beta
        // bundle keeps the suffix in CFBundleShortVersionString, so
        // `ReleaseChannel.detect` reads it as `.beta` and the stable rule refuses
        // it; without this rule a beta copy has no source at all. The pattern
        // accepts the stable tags too, as WhatCable's beta rule does: a beta is
        // the next stable release, and a beta copy must be offered the stable
        // that graduates from it (the app's own updater offers only that).
        GitHubReleaseRule(
            bundleID: "net.oldj.switchhosts",
            owner: "oldj", repo: "SwitchHosts",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?)$"#,
            installAssetPattern: #"^SwitchHosts-[0-9][0-9A-Za-z.-]*-mac-universal\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),
        ],
        githubChannelProofs: [
        // Anchor, not artifact: the beta rule accepts stable tags on purpose, so
        // an artifact proof would fire on the graduation it exists to offer.
        // `usePrereleases` makes it read the list, `versionPattern` makes it
        // accept a `-beta.N` tag; same shape as WhatCable's proof.
        ChannelProofKey("net.oldj.switchhosts", .beta):
            .recipeAnchor(#"^true$|-beta\\\."#, in: ["usePrereleases", "versionPattern"]),
        ])
}
