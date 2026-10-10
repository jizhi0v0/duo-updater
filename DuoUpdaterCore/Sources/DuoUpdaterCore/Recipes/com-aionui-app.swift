import Foundation

enum com_aionui_app {
    static let set = AppRecipeSet(
        family: "com-aionui-app",
        probes: [
        // History: docs/app-audits/com-aionui-app.md#历史与实测
        // AionUi — official electron-builder arm64 manifest. `version` matches the
        // mounted app exactly. com.aionui.app, Team 52JQX2HUSC, notarized.
        //
        // ONE-CLICK via `.versionTemplate`, and NOT via `.bodyPatternRelative`,
        // which is what an electron-builder manifest normally invites. The
        // manifest's `path`/`url` entries are bare filenames, but they do NOT
        // resolve against the manifest's own directory. The real
        // layout inserts the version as a directory, so the relative case would
        // have produced a link that never downloads.
        //
        // The manifest this probe reads is the arm64 one; Intel has a separate
        // manifest and artifact that no host of ours can ask for (arm64-only, see
        // `App/project.yml`), so the template pins arm64 the way the rest of the
        // registry does rather than waiting for host-architecture selection.
        //
        // The checksum comes from the manifest's TOP-LEVEL `sha512`, anchored at
        // column 0 so it cannot match the indented per-file digests under `files:`
        // — those list the dmg as well, and the first of them is only the zip's by
        // accident of ordering. The top-level digest is by definition the one for
        // `path:`, which is the zip this template builds.
        VendorProbeRecipe(
            bundleID: "com.aionui.app",
            url: URL(string: "https://static.aionui.com/releases/latest-arm64-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*v?([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://www.aionui.com/"),
            changelogURL: URL(string: "https://github.com/iOfficeAI/AionUi/releases"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://static.aionui.com/releases/{version}/"
                    + "AionUi-{version}-mac-arm64.zip"),
                kind: .zip,
                checksumPattern: #"(?m)^sha512:\s*(\S+)\s*$"#)),
        ],
        changelogs: [
        // History: docs/app-audits/com-aionui-app.md#历史与实测
        // AionUi — the vendor writes its notes on the GitHub releases of
        // iOfficeAI/AionUi (the probe's `changelogURL`), as Markdown lists. Tags
        // are `v<version>`, the same string the manifest's `version:` carries, so
        // an entry lines up with what the probe offers.
        //
        // `tagPattern` exists for one stable tag, `v2.1.47-final`: without it that
        // entry reads `2.1.47-final`, a version no install ever reports. The
        // pattern drops the suffix and nothing else; the repo's `-dev-<hash>`
        // tags are prereleases, which a stable rail never reads anyway.
        ChangelogRecipe(
            bundleID: "com.aionui.app",
            source: URL(string: "https://api.github.com/repos/iOfficeAI/AionUi/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)(?:-final)?$"#),
        ])
}
