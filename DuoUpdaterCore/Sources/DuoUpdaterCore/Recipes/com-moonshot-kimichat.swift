import Foundation

enum com_moonshot_kimichat {
    static let set = AppRecipeSet(
        family: "com-moonshot-kimichat",
        changelogs: [
        // Kimi — the version comes from `ElectronManifestSource` (the bundle's own
        // `app-update.yml`), which carries no notes; the manifest's `releaseNotes`
        // is a one-line Chinese summary anyway (3.2.7's, 2026-09-11:
        // `新增滚动截图与插件推荐`). The full notes are this help-centre page.
        //
        // Server-rendered: one `<h2 id="327-2026-09-11">3.2.7 (2026-09-11)</h2>` per
        // release, newest first, then `<p><strong>New|Changed|Fixed</strong></p>` +
        // `<ul>` groups. An entry is version/date/items, so those labels are not
        // carried and the groups flatten in document order (New first).
        //
        // Two shapes the patterns are built around, both on the page 2026-09-11:
        // - The last release is followed by `</ul></div><section …>Was this article
        //   helpful?`, so the body stops at the next `<h2` OR that `</div>`.
        // - 3.2.1 nests a `<ul>` inside an `<li>`. A lazy `<li>(.*?)</li>` stops at
        //   the first `</li>` it meets — the child's — and glues the parent line to
        //   its first sub-item. The item stops at the next `<li`/`</li>` instead, so
        //   the parent and each child come out as lines of their own.
        ChangelogRecipe(
            bundleID: "com.moonshot.kimichat",
            source: URL(string: "https://www.kimi.com/en/help/kimi-work/release-notes")!,
            entryPattern:
                #"<h2[^>]*>\s*(?<version>[0-9]+(?:\.[0-9]+)+)\s*"#
                + #"(?:\((?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\))?\s*</h2>"#
                + #"(?<body>.*?)(?=<h2\b|</div>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>(?:(?!</?li\b).)*)"#]),
        ])
}
