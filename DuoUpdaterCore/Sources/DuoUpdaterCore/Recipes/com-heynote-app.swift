import Foundation

enum com_heynote_app {
    static let set = AppRecipeSet(
        family: "com-heynote-app",
        githubRules: [
        // Heynote — an Electron scratchpad for developers (heyman/heynote). Its
        // own updater is electron-updater with `provider: github`, which states
        // no address `ElectronManifestSource` may use, so this rule is the route.
        // By default (`settings.autoUpdate`, `settings.autoInstallUpdates`) it
        // checks at launch and every 8 hours, downloads by itself into
        // `~/Library/Caches/heynote-updater/pending/` (`updaterCacheDirName`) and
        // installs on quit; `allowDowngrade` is on. No login item, launch agent
        // or resident helper ships in the bundle: the four `Heynote Helper*.app`
        // are Electron's own child processes.
        //
        // Tags read `v2.9.1`; the bundle says 2.9.1. Every release since v1.2.1
        // carries `Heynote_<v>_universal.dmg` beside `_arm64` / `_x64` dmgs and
        // zips; on v2.9.1 the arm64 and universal bundles differ only in
        // architecture. com.heynote.app, Team VY5Y3H438S, notarized, from v1.0.2
        // through v2.9.1.
        GitHubReleaseRule(
            bundleID: "com.heynote.app",
            owner: "heyman", repo: "heynote",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Heynote_[0-9]+(?:\.[0-9]+)+_universal\.dmg$"#,
            installerKind: .dmg),

        // Heynote beta — the same repo's prereleases (`v2.9.0-beta`,
        // `v2.9.0-beta.6`, `v2.9.1-beta`), same bundle id and Team; the bundle
        // keeps the suffix in both version fields. `ReleaseChannel.detect` reads
        // the numbered `-beta.N` copies as beta, and the stable rule refuses
        // them; without this rule they have no source. The app's own toggle
        // (`settings.allowBetaVersions`) sets electron-updater's
        // `allowPrerelease`, which then takes the newest release, stable or beta,
        // so the pattern accepts both tag shapes, as Zettlr's beta rule does: a
        // beta copy is offered the stable release that graduates from it.
        //
        // Not covered, see the audit: an UNNUMBERED beta copy (`2.9.1-beta`)
        // reads as stable and is served the stable rule, and a stable copy with
        // the toggle on reads as stable too.
        //
        // listPageSize: every release has a tag this pattern accepts, so the
        // first hit is the newest release; the default 20 stays (the floor is
        // pinned in `GitHubListPageSizeTests`).
        GitHubReleaseRule(
            bundleID: "com.heynote.app",
            owner: "heyman", repo: "heynote",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta(?:\.[0-9]+)?)?)$"#,
            installAssetPattern:
                #"^Heynote_[0-9]+\.[0-9]+\.[0-9]+(?:-beta(?:\.[0-9]+)?)?_universal\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),
        ],
        githubChannelProofs: [
        // Anchor, not artifact: the beta rule accepts stable tags on purpose, so
        // an artifact proof would fire on the graduation it exists to offer.
        // `usePrereleases` makes it read the list, `versionPattern` makes it
        // accept a `-beta` tag; same shape as Zettlr's proof.
        ChannelProofKey("com.heynote.app", .beta):
            .recipeAnchor(#"^true$|\(\?:-beta"#, in: ["usePrereleases", "versionPattern"]),
        ])
}
