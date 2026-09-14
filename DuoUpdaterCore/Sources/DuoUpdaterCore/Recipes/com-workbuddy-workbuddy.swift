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
        // Markup (server-rendered, so no JS is needed):
        //   <h2 id="_5-3-14-…">5.3.14 版本发布 🚀（2026-08-17） <a class="header-anchor"…></a></h2>
        //   <ul><li>新增 …</li><li>优化 …</li></ul>
        //
        // TRAP: those parentheses are FULLWIDTH（）in the bytes, on both the
        // Chinese and the English page — they render close enough to ASCII that
        // reading the page in a browser tells you nothing. A pattern written with
        // `\(` matches neither site. Both forms are accepted here so the recipe
        // survives the vendor normalising them either way.
        //
        // The heading text between version and date varies by era — "版本发布 🚀",
        // "Lanched 🚀" (the vendor's own typo), or nothing at all on the oldest
        // entries — so the pattern skips anything that is not a tag or a paren
        // rather than trying to enumerate the variants. The date group is optional
        // for the same reason: some of the CN page's older entries have no date.
        //
        // `</h2>\s*<ul>` adjacency is deliberate: it is what keeps a heading whose
        // notes are laid out some other way from swallowing the NEXT release's
        // list. It costs the oldest CN entries (4.5.0–4.7.5, which use a different
        // markup), and that is free — `maxEntries` stops at 40 and far more than 40
        // of the newest parse (History has the dated counts from both live pages).
        //
        // The intl page is short: it stops at 5.2.7 (2026-07-17), while its
        // own endpoint has shipped newer releases (when checked, 2026-08-27,
        // 2026-08-28 and 2026-09-14; History has the entry counts and versions). A
        // future reader finding only a couple of entries has found the vendor's
        // page, not a broken recipe — the CN page, parsed by the identical pattern,
        // returns dozens.
        //
        // That is also why the intl recipe carries `acknowledgedStaleEntry`
        // (issue #88). `duo verify` reads 5.2.7 against the newer detected version,
        // calls it a whole release behind, and files "recipe degraded" — a
        // complaint that can never clear, because there is nothing on our side to
        // fix. The acknowledgement names 5.2.7 rather than switching the check off,
        // so the day the pattern slips to an older section — or the vendor finally
        // publishes — the sweep speaks up again.
        ChangelogRecipe(
            bundleID: "com.workbuddy.workbuddy",
            source: URL(string: "https://www.workbuddy.cn/docs/workbuddy/Changelog")!,
            entryPattern: ChangelogRecipeRegistry.workBuddyEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
