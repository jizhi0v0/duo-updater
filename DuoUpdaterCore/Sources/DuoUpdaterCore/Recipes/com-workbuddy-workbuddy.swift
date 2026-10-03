import Foundation

enum com_workbuddy_workbuddy {
    static let set = AppRecipeSet(
        family: "com-workbuddy-workbuddy",
        probes: [
        VendorProbeRegistry.workBuddyRecipe(
            bundleID: "com.workbuddy.workbuddy", host: "www.workbuddy.cn",
            assetHost: "download.codebuddy.cn", arch: .arm64,
            downloadURL: URL(string: "https://www.workbuddy.cn/")!,
            changelogURL: URL(string: "https://www.codebuddy.cn/docs/workbuddy/Changelog")!),
        VendorProbeRegistry.workBuddyRecipe(
            bundleID: "com.workbuddy.workbuddy", host: "www.workbuddy.cn",
            assetHost: "download.codebuddy.cn", arch: .x86_64,
            downloadURL: URL(string: "https://www.workbuddy.cn/")!,
            changelogURL: URL(string: "https://www.codebuddy.cn/docs/workbuddy/Changelog")!),
        ],
        changelogs: [
        // History: docs/app-audits/com-workbuddy-workbuddy.md#历史与实测
        // WorkBuddy — Tencent's two sites, two apps (see the VendorProbe registry
        // and docs/app-audits/com-workbuddy-workbuddy.md). Both docs sites are the
        // same VitePress build, so ONE set of patterns serves both and only
        // `bundleID` and `source` differ. Each recipe is pinned to its OWN site:
        // the trains are independent, and showing an international install the CN
        // notes (or the reverse) would be quietly wrong in a way nothing else here
        // could catch.
        //
        // Markup (server-rendered, so no JS is needed). The CN page:
        //   <h2 id="_5-3-14-…">5.3.14 版本发布 🚀（2026-08-17） <a class="header-anchor"…></a></h2>
        //   <ul><li>新增 …</li><li>优化 …</li></ul>
        // The intl page splits each release into labelled lists, and its newest
        // headings carry no date at all:
        //   <h2 id="_5-6-2">5.6.2 <a class="header-anchor"…></a></h2>
        //   <p>[New]</p><ul><li>…</li></ul><p>[Fixed]</p><ul><li>…</li></ul>
        // `workBuddyEntryPattern` takes either as the body, and
        // `workBuddyHeadingPattern` turns the bracketed labels into headings
        // (it finds none on the CN page, so sharing it costs that page nothing).
        //
        // TRAP: the date parentheses are FULLWIDTH（）on most CN headings but
        // ASCII `()` on others (5.1.0 back to 4.8.0 mix the two), and ASCII on
        // the intl page (it used fullwidth too until its rebuild; History). The
        // two render close enough that reading the page in a browser tells you
        // nothing. A pattern written for only one form drops dates on BOTH
        // sites, so both are accepted.
        //
        // The heading text between version and date varies by era — "版本发布 🚀",
        // "Lanched 🚀" (the vendor's own typo), or nothing at all — so the pattern
        // skips anything that is not a tag or a paren rather than trying to
        // enumerate the variants. The date group is optional for the same reason:
        // some of the CN page's older entries, and the intl page's newest, have
        // no date.
        //
        // Adjacency is deliberate: only lists and their `<p>[Label]</p>` may
        // follow `</h2>`. That is what keeps a heading whose notes are laid out
        // some other way from swallowing the NEXT release's list. It costs the
        // oldest CN entries (4.5.0–4.7.5, which use a different markup), and that
        // is free — `maxEntries` stops at 40 and far more than 40 of the newest
        // parse (History has the dated counts from both live pages).
        //
        // The intl page carries only a handful of releases, and has at times
        // stopped well behind its own train (History has the versions; the intl
        // recipe once carried an `acknowledgedStaleEntry` for it, issue #88, and
        // dropped it once the page caught up, issue #913). A future reader finding
        // only a few entries there has found the vendor's page, not a broken
        // recipe — the CN page, parsed by the identical pattern, returns dozens.
        ChangelogRecipe(
            bundleID: "com.workbuddy.workbuddy",
            source: URL(string: "https://www.workbuddy.cn/docs/workbuddy/Changelog")!,
            entryPattern: ChangelogRecipeRegistry.workBuddyEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            headingPattern: ChangelogRecipeRegistry.workBuddyHeadingPattern),
        ])
}
