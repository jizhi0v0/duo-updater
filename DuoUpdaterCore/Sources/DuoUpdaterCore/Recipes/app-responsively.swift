import Foundation

enum app_responsively {
    static let set = AppRecipeSet(
        family: "app-responsively",
        githubRules: [
        // Responsively App — Electron browser for responsive web development.
        // Source is responsively-org/responsively-app; the installers and the
        // update metadata are published to this releases-only repo. Its own
        // updater is electron-updater (`app-update.yml`: provider github, this
        // repo, `updaterCacheDirName: responsivelyapp-updater`), which states
        // no address `ElectronManifestSource` may use, so this rule is the
        // route. `src/main/app-updater.ts` calls `checkForUpdatesAndNotify()`
        // at launch with the library defaults: it downloads on its own and
        // installs on quit (Squirrel.Mac). No login item or helper outside
        // `Contents/Frameworks`.
        //
        // Tags read `v1.18.0`; the bundle says 1.18.0. Every release carries
        // `ResponsivelyApp-<v>-arm64.dmg` (arm64) beside the unsuffixed x64
        // dmg/zip; there is no universal build. Real 1.18.0 and 1.17.1 (and
        // the scaffold's 1.0.1): app.responsively, Team M4H33HFC4K,
        // notarized. The 0.x releases (2020–2022, x64 only) live in the
        // source repo under the same id and Team; their updater reads that
        // repo, whose newest release has no assets, so this rule is what
        // moves them on.
        GitHubReleaseRule(
            bundleID: "app.responsively",
            owner: "responsively-org", repo: "responsively-app-releases",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^ResponsivelyApp-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),

        // Beta — GitHub prereleases on the same bundle id (`v2.0.0-beta.0`,
        // 2026-09; earlier `v1.0.0-beta.6`). A beta bundle keeps the suffix in
        // CFBundleShortVersionString, so `ReleaseChannel.detect` reads it as
        // `.beta` and the stable rule refuses it. The app has no beta switch:
        // electron-updater turns `allowPrerelease` on by itself when the
        // running version has a prerelease part, and its GitHub provider then
        // takes the newest release whatever its kind, stable or beta. So this
        // rule accepts both tag shapes, as SwitchHosts' beta rule does.
        GitHubReleaseRule(
            bundleID: "app.responsively",
            owner: "responsively-org", repo: "responsively-app-releases",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-beta\.[0-9]+)?)$"#,
            installAssetPattern: #"^ResponsivelyApp-[0-9]+(?:\.[0-9]+)+(?:-beta\.[0-9]+)?-arm64\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),
        ],
        githubChannelProofs: [
        // Anchor, not artifact: the beta rule accepts stable tags on purpose,
        // so an artifact proof would fire on the graduation it exists to
        // offer. Same shape as SwitchHosts' proof.
        ChannelProofKey("app.responsively", .beta):
            .recipeAnchor(#"^true$|-beta\\\."#, in: ["usePrereleases", "versionPattern"]),
        ])
}
