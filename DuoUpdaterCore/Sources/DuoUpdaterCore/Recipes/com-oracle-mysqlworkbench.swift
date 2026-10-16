import Foundation

enum com_oracle_mysqlworkbench {
    static let set = AppRecipeSet(
        family: "com-oracle-mysqlworkbench",
        probes: [
        // History: docs/app-audits/com-oracle-mysqlworkbench.md#历史与实测
        // MySQL Workbench 26 and later — the Electron rebuild on MySQL Shell,
        // bundle id `com.oracle.mysqlworkbench`, app "MySQL Workbench.app". It
        // carries no updater of its own (Electron's Squirrel.framework is in the
        // bundle, but `src/main.cjs` never calls `autoUpdater`), so this reads the
        // vendor's macOS download page, the page the old app's "Check for
        // Updates" sends people to.
        //
        // `os=33` is the page's macOS tab: one row per macOS package, each with
        // its filename in parentheses. The pattern takes only
        // `(mysql-workbench-<v>-macos-arm64.dmg)`, so the zip row, any other
        // architecture and any `-rc`-style filename never match. 8.0.x files are
        // spelled `mysql-workbench-community-…` and cannot match either. The page
        // lists only the current GA release; `selectHighest` costs nothing and
        // keeps a page that ever lists two from being read by position.
        //
        // 8.0 copies (`com.oracle.workbench.MySQLWorkbench`) are filed under this
        // id by `BundleIDMigration` (a rewrite entry, so the row asks the user
        // first), which is also why nothing here is keyed by the 8.0 id.
        //
        // ONE-CLICK via `.versionTemplate` on the CDN path the page's download
        // button resolves to, filled with the version that won the comparison.
        // Developer ID Oracle America, Inc. (VB5E2TV963), notarized; arm64 only
        // (the vendor publishes no x86_64 build of 26.x, and DuoUpdater is
        // arm64-only). The page publishes an MD5 per file, which
        // `checksumFormat` does not support, so the gate is the Team ID alone.
        VendorProbeRecipe(
            bundleID: "com.oracle.mysqlworkbench",
            url: URL(string: "https://dev.mysql.com/downloads/workbench/?os=33")!,
            mode: .responseBody,
            versionPattern: #"\(mysql-workbench-([0-9]+(?:\.[0-9]+)+)-macos-arm64\.dmg\)"#,
            downloadURL: URL(string: "https://dev.mysql.com/downloads/workbench/")!,
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://cdn.mysql.com/Downloads/MySQLGUITools/"
                    + "mysql-workbench-{version}-macos-arm64.dmg"),
                kind: .dmg)),
        ])
}
