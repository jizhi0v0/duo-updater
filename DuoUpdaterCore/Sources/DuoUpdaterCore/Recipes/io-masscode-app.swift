import Foundation

enum io_masscode_app {
    static let set = AppRecipeSet(
        family: "io-masscode-app",
        githubRules: [
        // massCode — Electron snippet manager (massCodeIO/massCode). Its own
        // updater is electron-updater with `provider: github`, which states no
        // address `ElectronManifestSource` may use, so this rule is the route.
        // That updater downloads a same-major release on its own (the
        // `updates.autoUpdate` preference, on by default) and installs it on
        // quit; a new major is only announced.
        //
        // Tags read `v6.3.1`; the bundle says 6.3.1. The pattern leaves out
        // `v2.0.0-beta.1`…`beta.6` (2022, not flagged prerelease, older than
        // v2.0.0) and the flagged `v3.0.0-beta.1` / `v4.0.0-beta.2` /
        // `v4.0.0.beta-1`. A copy of any of them reports `x.y.z-beta.N`, which
        // `ReleaseChannel.detect` reads as beta, so this stable rule does not
        // serve it.
        //
        // `massCode-<v>-arm64.dmg` is io.masscode.app, Team GCU493MNF8,
        // notarized (6.0.0, 6.2.1, 6.3.1). The unsuffixed dmg/zip are the x64
        // build (`electron-builder --mac --x64 --arm64`); there is no universal.
        GitHubReleaseRule(
            bundleID: "io.masscode.app",
            owner: "massCodeIO", repo: "massCode",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^massCode-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ],
        // One-click only for 5.x and 6.x copies. v6 opens only a Markdown
        // Vault and dropped SQLite and the built-in migration (v6.0.0 release
        // notes: "Existing Markdown Vault users can continue using their
        // vault"; a v4 `massCode.db` goes through v5.12.0 first, a v3
        // `db.json` through v4.7.1 and then v5.12.0). v5 is where the vault
        // arrived, migrating a v4 library on upgrade (v5.0.0 release notes),
        // so a 5.x copy's library is already one v6 reads; a 4.x or older copy
        // would open v6 with its library unreadable. Those keep detection.
        // The vendor's own updater installs no new major by itself, so admit
        // the next major only once its release notes have been read for the
        // same kind of break.
        oneClickGates: [
            OneClickGate(
                bundleID: "io.masscode.app",
                requirement: .installedVersion(pattern: #"^[56]\."#),
                reason: "massCode 6 cannot open a library from massCode 4 or earlier; migrate it with massCode 5.12.0 first (see the v6.0.0 release notes), then update by hand"),
        ])
}
