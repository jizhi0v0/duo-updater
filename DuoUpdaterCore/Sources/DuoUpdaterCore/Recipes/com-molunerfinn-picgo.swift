import Foundation

enum com_molunerfinn_picgo {
    static let set = AppRecipeSet(
        family: "com-molunerfinn-picgo",
        githubRules: [
        // PicGo — an Electron image-upload tool (Molunerfinn/PicGo) that lives in
        // the menu bar. Its own update check (`src/main/utils/updateChecker.ts`)
        // only compares versions against the GitHub releases list and, on Yes,
        // opens the release page in the browser: no download, nothing staged.
        // The bundle carries electron-builder's `app-update.yml` (provider
        // github), but nothing in the app reads it — feed-discover reports
        // `electronProviderNeedsConstruction`, so this rule is the route.
        //
        // Tags read `v3.0.3`; the bundle says 3.0.3. The pattern leaves out the
        // nine `v2.3.0-beta.N` tags on purpose: they are betas the vendor did
        // not flag as prereleases (later betas are flagged), and a copy of one
        // reads `2.3.0-beta.8`, which `ReleaseChannel.detect` calls `.beta`, so
        // no stable rule serves it either way.
        //
        // One-click: `PicGo-<version>-arm64.dmg` (the `-x64.dmg` and the
        // `-beta.N-arm64.dmg` assets are left out by name), com.molunerfinn.picgo,
        // Team QDG8UZ6TCP, notarized. Copies up to 2.4.1 carry no Team (ad-hoc
        // or unsigned), so the Team gate refuses them and they update by hand once.
        GitHubReleaseRule(
            bundleID: "com.molunerfinn.picgo",
            owner: "Molunerfinn", repo: "PicGo",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^PicGo-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
