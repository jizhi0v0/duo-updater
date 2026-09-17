import Foundation

enum com_bjango_istatmenus {
    static let set = AppRecipeSet(
        family: "com-bjango-istatmenus",
        probes: [
        // Shared rationale for 2026-08-16 vendor batch: Recipes/dev-commandline-waveterm.swift.

        // iStat Menus — a "latest" link that 302s straight to the versioned zip
        // (e.g. `…/versions/iStatMenus7.30.zip`), so the redirect target is the
        // download, and the archive the version is read from. Verified 2026-08-16: the zip holds
        // `iStat Menus.app`, com.bjango.istatmenus, 7.30, Team Y93TK974AT,
        // notarized. The pattern skips the `7` in the product name and takes the
        // version that follows it.
        // snapshot-lint:allow — this dated verification stays in code: `Recipes/dev-commandline-waveterm.swift`'s batch block relies on it.
        //
        // The filename does not name the release the bundle reports. The vendor
        // re-publishes a release under a third component — `iStatMenus7.50.1.zip`
        // holds a bundle reporting 7.50, and only its build moved — so the
        // filename alone is either a permanent phantom update (compare `7.50.1`
        // against the installed 7.50) or a missed one (compare `7.50`). The mode
        // therefore reads the archive's own `Info.plist` by byte range and offers
        // that marketing/build pair; the pattern only has to recognise the file.
        // History: docs/app-audits/com-bjango-istatmenus.md#历史与实测
        VendorProbeRecipe(
            bundleID: "com.bjango.istatmenus",
            url: URL(string: "https://download.istatmenus.app/istatmenus7/download/")!,
            mode: .redirectArchiveInfoPlist(entry: "iStat Menus.app/Contents/Info.plist"),
            versionPattern: #"iStatMenus([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.zip"#,
            downloadURL: URL(string: "https://bjango.com/mac/istatmenus/"),
            changelogURL: URL(string: "https://bjango.com/mac/istatmenus/versionhistory/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.istatmenus.app/istatmenus7/download/")!),
                kind: .zip)),
        ])
}
