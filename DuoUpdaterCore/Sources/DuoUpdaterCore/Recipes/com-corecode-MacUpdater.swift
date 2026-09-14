import Foundation

enum com_corecode_MacUpdater {
    static let set = AppRecipeSet(
        family: "com-corecode-MacUpdater",
        probes: [
        // History: docs/app-audits/com-corecode-MacUpdater.md#历史与实测
        // MacUpdater — version is in an HTML comment marker on the product page.
        // NOTE: HTML scrape — more brittle than an API; refresh if it stops
        // matching.
        //
        // One-click: `macupdater_latest.dmg` is an unversioned "latest" URL holding
        // `MacUpdater.app` — bundle id com.corecode.MacUpdater, Team 9D78DG5ACV,
        // notarized.
        // Fixed rather than scraped: the page's only download href is that same
        // stable path.
        VendorProbeRecipe(
            bundleID: "com.corecode.MacUpdater",
            url: URL(string: "https://www.corecode.io/macupdater/")!,
            mode: .responseBody,
            versionPattern: #"<!--BEGINVERSION-->([0-9.]+)<!--ENDVERSION-->"#,
            changelogURL: URL(string: "https://www.corecode.io/macupdater/history3.html"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://www.corecode.io/downloads/macupdater_latest.dmg")!),
                kind: .dmg)),
        ],
        changelogs: [
        // MacUpdater — corecode.io/macupdater/history3.html is a single static
        // page of every release newest-first (no hydration). 3.5.0 is the final
        // release (the product is discontinued), so the page is effectively
        // frozen. Each version block is:
        //   <p><b>3.5.0</b> (Jan 2026):</p>
        //   <p>• item…</p>
        //   <p>• item…</p>
        // Version and date are in the <p><b>…</b> (…)</p> header; each change is a
        // bullet <p>• …</p> until the next version header. The bullet is a literal
        // U+2022, so the item pattern anchors on it to skip non-bullet paragraphs.
        ChangelogRecipe(
            bundleID: "com.corecode.MacUpdater",
            source: URL(string: "https://www.corecode.io/macupdater/history3.html")!,
            entryPattern:
                #"<p><b>(?<version>[0-9][0-9.]*)</b>\s*\((?<date>[^)]*)\):</p>"#
                + #"(?<body>.*?)"#
                + #"(?=<p><b>[0-9][0-9.]*</b>\s*\(|$)"#,
            itemPatterns: [#"<p>\s*•\s*(?<item>.*?)</p>"#],
            maxEntries: 20),
        ])
}
