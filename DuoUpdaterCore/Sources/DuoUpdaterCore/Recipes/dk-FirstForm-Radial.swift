import Foundation

enum dk_FirstForm_Radial {
    static let set = AppRecipeSet(
        family: "dk-FirstForm-Radial",
        changelogs: [
        // Radial — Sparkle gives detection (`dk.FirstForm.Radial`), but every item
        // in its appcast carries no `<description>` and no
        // `<sparkle:releaseNotesLink>`, so the pane had a version and nothing else.
        //
        // The vendor's changelog is server-rendered, newest first, one `<article>`
        // per release:
        //   <article id="v5-3-0">
        //     <p class="font-mono …">October 30, 2026</p>
        //     <h2 …>5.3.0</h2>
        //     <p class="mt-5 …">summary</p>
        //     <section>
        //       <p class="self-start …"><span …></span>New</p>
        //       <ul><li>…</li></ul>
        //     </section>
        //   </article>
        //
        // Anchored on the `<article>` element and the `h2` that follows its date,
        // so the sidebar's version list (same page, `<a data-version=…>`) cannot be
        // read as an entry. The section label is the heading; the items are the
        // `li`s inside the article's own body, which is why the sidebar's `<li>`s
        // are out of reach.
        ChangelogRecipe(
            bundleID: "dk.FirstForm.Radial",
            source: URL(string: "https://radial.appverge.net/changelog")!,
            entryPattern:
                #"<article id="v[^"]+"[^>]*>\s*<p[^>]*>(?<date>[^<]*)</p>\s*<h2[^>]*>(?<version>[^<]*)</h2>\s*(?<body>.*?)</article>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 20,
            headingPattern:
                #"<p class="self-start[^"]*"[^>]*>\s*<span[^>]*></span>\s*(?<heading>[^<]+)</p>"#),
        ])
}
