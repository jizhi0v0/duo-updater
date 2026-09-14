import Foundation

enum com_bjango_istatmenus {
    static let set = AppRecipeSet(
        family: "com-bjango-istatmenus",
        probes: [
        // Shared rationale for 2026-08-16 vendor batch: Recipes/dev-commandline-waveterm.swift.

        // iStat Menus — a "latest" link that 302s straight to the versioned zip
        // (`…/versions/iStatMenus7.30.zip`), so the redirect target is both the
        // version signal and the download. Verified 2026-08-16: the zip holds
        // `iStat Menus.app`, com.bjango.istatmenus, 7.30, Team Y93TK974AT,
        // notarized. The pattern skips the `7` in the product name and takes the
        // version that follows it.
        // This dated verification stays in code: `Recipes/dev-commandline-waveterm.swift`'s batch block relies on it.
        VendorProbeRecipe(
            bundleID: "com.bjango.istatmenus",
            url: URL(string: "https://download.istatmenus.app/istatmenus7/download/")!,
            mode: .redirectFilename,
            versionPattern: #"iStatMenus([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.zip"#,
            downloadURL: URL(string: "https://bjango.com/mac/istatmenus/"),
            changelogURL: URL(string: "https://bjango.com/mac/istatmenus/versionhistory/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.istatmenus.app/istatmenus7/download/")!),
                kind: .zip)),
        ])
}
