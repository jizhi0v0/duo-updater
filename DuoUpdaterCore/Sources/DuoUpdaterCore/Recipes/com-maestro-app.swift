import Foundation

enum com_maestro_app {
    static let set = AppRecipeSet(
        family: "com-maestro-app",
        // History: docs/app-audits/com-maestro-app.md#历史与实测
        changelogs: [
        // The same release bodies the rule below reads, through
        // `MaestroReleaseNotes`: the headline changes are paragraphs under a
        // heading naming the version (`# 1.0.2 Highlights`), which the shared
        // parser drops (1.0.2: 6 of 10 changes, no headings). The tag pattern
        // is the rule's, so the RC tags GitHub does not flag as prereleases
        // (v0.15.4-RC, v0.15.0-RC, v0.11.2-rc, v0.8.8-rc) stay out. One page of
        // 40 is read, so RCs interleaving leave fewer stable entries than that.
        ChangelogRecipe(
            bundleID: "com.maestro.app",
            source: URL(string: "https://api.github.com/repos/RunMaestro/Maestro/releases?per_page=40")!,
            mode: .json,
            maxEntries: 12,
            channel: .stable,
            structuredFormat: .maestroReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        // The RC track (`MaestroChannel`) is offered RCs and stable releases
        // alike (the rule below), so its notes list both: prereleases, plus the
        // stable releases `includesPromotedStable` keeps, under the RC rule's
        // tag pattern, so an entry's version is the string an RC bundle
        // reports (`1.1.0-RC`). Without it the stable recipe above would answer
        // for an RC copy and leave out the RC it is offered.
        ChangelogRecipe(
            bundleID: "com.maestro.app",
            source: URL(string: "https://api.github.com/repos/RunMaestro/Maestro/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            includesPromotedStable: true,
            structuredFormat: .maestroReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-(?:RC|rc))?)$"#),
        ],
        githubRules: [
        // Maestro — an Electron "agent orchestration command center"
        // (RunMaestro/Maestro, renamed from pedramamini/Maestro; the old slug
        // redirects). Its own updater is electron-updater: `app-update.yml`
        // says provider github, this repo, `updaterCacheDirName:
        // maestro-updater`, which states no address `ElectronManifestSource`
        // may use (`electronProviderNeedsConstruction`), so this rule is the
        // route. `src/main/auto-updater.ts` sets `autoDownload = false`,
        // `autoInstallOnAppQuit = true` and `allowPrerelease = false`: the app
        // checks the releases API itself (`src/main/update-checker.ts`) and
        // downloads only when the user clicks, into
        // `~/Library/Caches/maestro-updater/pending/`. The four nested apps
        // are the stock Electron helpers in `Contents/Frameworks`
        // (LSUIElement, children of the main process); no login item.
        //
        // Tags read `v1.0.2`; the bundle says 1.0.2. The anchored pattern
        // leaves out the `-RC` tags, including the four the vendor did not
        // flag as prereleases (v0.15.4-RC, v0.15.0-RC, v0.11.2-rc,
        // v0.8.8-rc). An RC copy says `1.1.0-RC`; `VersionComparator` ranks it
        // above 1.0.2 and below 1.1.0, so with RCs off (`MaestroChannel`) this
        // rule offers it nothing until the next stable release, which is what
        // the app's own check does with its switch off (the default).
        //
        // One-click: `maestro-<v>-arm64-mac.zip` (the zip electron-updater
        // itself installs; the dmg and the x64 assets are left out by name),
        // com.maestro.app, Team 4N4DQ24LED, notarized, on 1.0.2 and 1.0.1.
        // Copies up to 0.8.0 are ad-hoc signed, so the Team gate refuses them
        // and they update by hand once; 0.8.1 onward carry the same Team.
        GitHubReleaseRule(
            bundleID: "com.maestro.app",
            owner: "RunMaestro", repo: "Maestro",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^maestro-[0-9]+(?:\.[0-9]+)+-arm64-mac\.zip$"#,
            installerKind: .zip),
        // RC — Settings ▸ "Include beta and release candidate updates"
        // (`MaestroChannel`). With it on, the app's own check takes every
        // non-draft release, sorts them by version (`compareVersions`) and
        // offers the first: the HIGHEST version, RC or not. The RC line is
        // published ahead of later stable patches (1.1.0-RC came out before
        // 1.0.1 and 1.0.2), so list order is not version order, hence
        // `.highestVersion`. RC zips are named like stable ones (`maestro-1.1.0-RC-arm64-mac.zip`),
        // same id and Team; the bundle says `1.1.0-RC`, the version this
        // pattern reads off the tag.
        GitHubReleaseRule(
            bundleID: "com.maestro.app",
            owner: "RunMaestro", repo: "Maestro",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-(?:RC|rc))?)$"#,
            candidateScope: .highestVersion,
            installAssetPattern: #"^maestro-[0-9]+(?:\.[0-9]+)+(?:-(?:RC|rc))?-arm64-mac\.zip$"#,
            installerKind: .zip,
            channel: .beta,
            // `v0.16.16-RC` also carries a stable `maestro-0.16.16-arm64-mac.zip`,
            // which `installableAsset` ranks above the RC zip. Reading the
            // offer off the chosen file keeps the offer and the install equal.
            assetVersionPattern: #"^maestro-([0-9]+(?:\.[0-9]+)+(?:-(?:RC|rc))?)-arm64-mac\.zip$"#),
        ],
        githubChannelProofs: [
        // Anchor, not artifact: a beta copy is offered stable releases on
        // purpose. Every part of the request must hold: the list read, the
        // tag pattern taking `-RC`, and the version-ordered pick.
        ChannelProofKey("com.maestro.app", .beta):
            .recipeAnchor(#"^true$|-\(\?:RC\|rc\)\)\?\)\$$|^highestVersion$"#,
                          in: ["usePrereleases", "versionPattern", "candidateScope"]),
        ])
}
