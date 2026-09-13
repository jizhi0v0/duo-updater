import Foundation

enum net_kovidgoyal_calibre {
    static let set = AppRecipeSet(
        family: "net-kovidgoyal-calibre",
        changelogs: [
        // Calibre — calibre-ebook.com/whats-new is one server-rendered page listing
        // every release newest-first (no hydration). Each release is a
        //   <h2 class="release-title">Release: 9.9 [28 May, 2026]</h2>
        //   <h3 class="category">New features</h3><ul class="entries">
        //     <li class="minor"><span class="title">…text…</span>…</li> …
        // Version and date are both in the <h2> title ("Release: <ver> [<date>]").
        // The body spans the whole release (several category sections), bounded by
        // the next release <h2> or the panes-closing triple </div>. itemPatterns
        // target ONLY <span class="title"> — the real changelog (New features + Bug
        // fixes); the bare <li> "news sources" lists carry no span and are dropped
        // as noise. Item text can contain entities (Preferences-&gt;Searching).
        ChangelogRecipe(
            bundleID: "net.kovidgoyal.calibre",
            source: URL(string: "https://calibre-ebook.com/whats-new")!,
            entryPattern:
                #"<h2 class="release-title">Release:\s*(?<version>[\d.]+)\s*\[(?<date>[^\]]*)\]</h2>"#
                + #"(?<body>.*?)(?=<h2 class="release-title">|</div>\s*</div>\s*</div>)"#,
            itemPatterns: [#"<span class="title">(?<item>.*?)</span>"#]),
        ])
}
