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
        ],
        changelogs: [
        // History: docs/app-audits/com-oracle-mysqlworkbench.md#历史与实测
        // MySQL Workbench 8.0 — the release notes publish one page per version;
        // `news-8-0.html` is their index, newest first, so the first
        // `news-8-0-<n>.html` href is the newest 8.0 release (8.0.39 and 8.0.37
        // are listed as "Not released" and have pages of their own). The 26.x
        // app has no recipe: the vendor's release notes stop at 8.0.47.
        //
        // The 8.0 app (`com.oracle.workbench.MySQLWorkbench`) has notes here but
        // no probe: its `CFBundleShortVersionString` is `8.0.47.CE`, every vendor
        // surface says `8.0.47`, and `VersionComparator` reads `8.0.47` as newer
        // than `8.0.47.CE`, so a probe would offer every current copy itself.
        // The audit has the measurement and the open decision. These notes still
        // serve a copy another source answers for (Homebrew).
        //
        // The detail page is DocBook output: one `<h3 class="title">` naming
        // "Changes in MySQL Workbench <v> (<date>)", `<h4>` sections
        // ("Functionality Added or Changed", "Bugs Fixed"), and one
        // `<li class="listitem">` per change, which may hold several `<p>`s and
        // a link. The body ends at the page navigation that follows the last
        // section.
        ChangelogRecipe(
            bundleID: "com.oracle.workbench.MySQLWorkbench",
            source: URL(string: "https://dev.mysql.com/doc/relnotes/workbench/en/news-8-0.html")!,
            entryPattern:
                #"<h3 class="title">\s*<a name="news-[0-9-]+"></a>Changes in MySQL Workbench "#
                + #"(?<version>[0-9]+(?:\.[0-9]+)+) \((?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\)</h3>"#
                + #"(?<body>.*?)<div id="docs-in-page-nav-container">"#,
            // A release with nothing to list says so in one `<p>` and has no
            // `<li>` (8.0.46: "This release contains no functional changes."),
            // so the paragraph is the fallback item.
            itemPatterns: [
                #"<li class="listitem">(?<item>.*?)</li>"#,
                #"<p>(?<item>.*?)</p>"#,
            ],
            maxEntries: 1,
            indexLinkPattern: #"href="(?<link>news-8-0-[0-9]+\.html)""#,
            headingPattern: #"<h4 class="title">\s*<a name="[^"]*"></a>(?<heading>[^<]+)</h4>"#),
        ])
}
