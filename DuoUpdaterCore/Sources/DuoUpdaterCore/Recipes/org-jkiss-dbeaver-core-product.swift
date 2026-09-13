import Foundation

enum org_jkiss_dbeaver_core_product {
    static let set = AppRecipeSet(
        family: "org-jkiss-dbeaver-core-product",
        githubRules: [
        // DBeaver Community — tags are bare dotted versions (no `v` prefix), e.g.
        // `26.1.0`; the `dbeaver/dbeaver` repo tracks the Community version scheme,
        // so /releases/latest matches the installed CE version directly.
        //
        // One-click verified 2026-08-09 on 26.1.4: `dbeaver-ce-<ver>-macos-aarch64.dmg`
        // holds `DBeaver.app`, bundle id org.jkiss.dbeaver.core.product, Team
        // 42B6MDKMW8, spctl "Notarized Developer ID". The pattern pins `aarch64` so
        // the x86_64 asset published alongside it can never be picked on an Apple
        // Silicon Mac.
        GitHubReleaseRule(
            bundleID: "org.jkiss.dbeaver.core.product",
            owner: "dbeaver", repo: "dbeaver",
            installAssetPattern: #"^dbeaver-ce-[0-9.]+-macos-aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
