import Foundation

enum asc_onlyoffice_ONLYOFFICE {
    static let set = AppRecipeSet(
        family: "asc-onlyoffice-ONLYOFFICE",
        changelogs: [
            // History: docs/app-audits/asc-onlyoffice-ONLYOFFICE.md#历史与实测
            // The Help Center has dated, per-version notes and the migration
            // notice that precedes the lists in the first rewritten release.
            ChangelogRecipe(
                bundleID: "asc.onlyoffice.ONLYOFFICE",
                source: URL(string: "https://helpcenter.onlyoffice.com/desktop/desktop-changelog")!,
                entryPattern: #"<h2\b[^>]*>\s*Version\s+(?<version>[0-9]+(?:\.[0-9]+)+)\s*(?:<a\b[^>]*>.*?</a>\s*)?</h2>\s*"#
                    + #"(?:<p>Release date:\s*(?<date>[^<]+)</p>\s*)?"#
                    + #"(?<body>.*?)(?=<h2\b|</article>|\z)"#,
                itemPatterns: [#"(?<item><li\b[^>]*>.*?</li>|<p\b[^>]*>\s*Important:.*?(?=</p>|</div>))"#],
                headingPattern: #"<h[34]\b[^>]*>\s*(?<heading>[^<]+)(?=<a\b|</h[34]>)"#),
        ])
}
