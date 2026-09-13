import Foundation

enum pl_maketheweb_cleanshotx {
    static let set = AppRecipeSet(
        family: "pl-maketheweb-cleanshotx",
        changelogs: [
        // CleanShot X — Nuxt page, very regular markup. Re-derived 2026-09-01, when
        // the 5.0 release shipped with the page rebuilt around it:
        //   <div class="version"><div class="date">1 September, 2026</div>
        //     <div class="content"><div class="topbar">
        //       <div class="number">5.0</div><div class="text-badge">Major Update</div>
        //     </div>
        //     <p class="change-intro">…</p> <a class="video-link">…</a>   ← 5.0 only
        //     <ul class="changes"><li class="change">…</li>…</ul></div></div>
        //
        // Three things moved at once, which is why nothing matched afterwards: the
        // date now comes *before* the number rather than after it, two wrappers
        // (`content`, `topbar`) appeared between the version div and the number, and
        // a feature release puts a paragraph and two video links between the number
        // and the list. The first two are why the old pattern's `\s*` joints failed;
        // the third is why the number→list gap has to be permissive.
        //
        // That gap is tempered rather than a plain `.*?` so it cannot leave the
        // block it started in. All 102 blocks on today's page carry a
        // `ul.changes`, so a lazy `.*?` finds the right one — but the day one of
        // them doesn't, a lazy gap silently pairs that version with the *next*
        // one's notes, which is the failure that reads as correct. Costs 0.6 ms
        // over the whole 183 KB page.
        ChangelogRecipe(
            bundleID: "pl.maketheweb.cleanshotx",
            source: URL(string: "https://cleanshot.com/changelog")!,
            entryPattern:
                #"<div class="version"[^>]*>\s*"#
                + #"<div class="date"[^>]*>(?<date>[^<]*)</div>\s*"#
                + #"<div class="content"[^>]*>\s*<div class="topbar"[^>]*>\s*"#
                + #"<div class="number"[^>]*>(?<version>[^<]+)</div>"#
                + #"(?:(?!<div class="version").)*?"#
                + #"<ul[^>]*class="changes"[^>]*>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
