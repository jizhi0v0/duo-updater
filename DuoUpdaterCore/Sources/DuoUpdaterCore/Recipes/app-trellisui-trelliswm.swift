import Foundation

enum app_trellisui_trelliswm {
    static let set = AppRecipeSet(
        family: "app-trellisui-trelliswm",
        changelogs: [
        // TrellisWM — detection, one-click and deltas are the bundle's own Sparkle
        // feed (`trelliswm.app/appcast.xml`). Its items carry no inline notes, only
        // `<sparkle:releaseNotesLink>` to `releases/TrellisWM-<version>.html`, which
        // the pane would otherwise embed as a page.
        //
        // That page is a small static HTML file: per release an `<h1>` with the
        // version, `<h2>` sections (New / Improved / Fixed / …) and an `<ul>` of
        // `<li>` items. The 0.9.5 page (2026-10-19) also carries 0.9.4's section,
        // so the version comes from each `<h1>`, not from the URL, and each
        // section is its own entry. The 0.9.4 and 0.9.3 pages have no `<h1>`;
        // they match nothing and fall back to the embedded page, which only
        // matters if one of them is ever the offered update again.
        ChangelogRecipe(
            bundleID: "app.trellisui.trelliswm",
            source: URL(string: "https://trelliswm.app/appcast.xml")!,
            entryPattern:
                #"<h1>\s*(?<version>[0-9]+(?:\.[0-9]+)+)\s*</h1>(?<body>.*?)(?=<h1>|</body>|\z)"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            sourceTemplate: "https://trelliswm.app/releases/TrellisWM-{version}.html",
            headingPattern: #"<h2>(?<heading>.*?)</h2>"#),
        ])
}
