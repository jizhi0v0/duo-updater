import Foundation

enum com_macpaw_CleanMyMac5 {
    static let set = AppRecipeSet(
        family: "com-macpaw-CleanMyMac5",
        probes: [
        // History: docs/app-audits/com-macpaw-CleanMyMac5.md#历史与实测
        // CleanMyMac 5 (MacPaw) — Sparkle 2 appcast served from the vendor's own
        // update host. The bundle carries `Sparkle.framework` but no `SUFeedURL`
        // (the address is built at runtime: the binary only holds
        // `updates.cleanmymac.com/`), so `feed-discover` found nothing and it
        // reaches us here. The channel is one XML with `<sparkle:version>` and
        // `<sparkle:shortVersionString>` ELEMENTS on each item, newest first.
        //
        // Do NOT use `updates.devmate.com/com.macpaw.CleanMyMac5.xml`: it answers
        // 200 with a well-formed feed, but it stopped at 5.3.1 in January 2026
        // while the app ships 5.7.3 (checked 2026-11-01) — a probe there would
        // report every current copy as up to date.
        //
        // Version scheme: `sparkle:shortVersionString` (5.7.3) and
        // `CFBundleShortVersionString` agree, and `sparkle:version`
        // (50703.0.2610281229) IS `CFBundleVersion`, so marketing comparison is
        // the correct one; no `versionIsBuild`.
        //
        // One-click: the first item's `releases/…zip` enclosure holds
        // `CleanMyMac_5.app`, bundle id com.macpaw.CleanMyMac5, Team S8EX82NJP6,
        // notarized Developer ID — the same Team as the installed copy. The
        // `<sparkle:deltas>` siblings sit under `/deltas/` and end `.delta`, so
        // the `releases/…zip` anchor cannot pick one.
        VendorProbeRecipe(
            bundleID: "com.macpaw.CleanMyMac5",
            url: URL(string: "https://updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9][0-9.]*)</sparkle:shortVersionString>"#,
            changelogURL: URL(string: "https://macpaw.com/cleanmymac/whats-new"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://updates\.cleanmymac\.com/com\.macpaw\.cleanmymac5/releases/[^"]+\.zip)""#),
                kind: .zip)),
        ],
        changelogs: [
        // CleanMyMac 5 — macpaw.com/cleanmymac/whats-new, server-rendered, newest
        // first. One block per release:
        //   <div class="versions-item …" data-versions-item …>
        //     <h2 class="version">Update 5.7.2</h2>
        //     <span class="date"><span class="pre-date">…/ </span>October 15, 2026</span>
        //     … description <p>, then per-topic summaries whose bullets are <li> …
        //
        // Anchored on the `h2.version` rather than on the `data-versions-item`
        // wrapper: the wrapper's attributes are spread over several lines and its
        // block boundary is easy to overrun, while every release has the heading.
        // A lazy body up to the next heading (or the end of the releases section)
        // is the block.
        //
        // Two item patterns, in order: bullets when the release has any (most
        // feature releases), else its paragraphs (bug-fix releases are one
        // sentence with no list). Without the fallback those releases would carry
        // no entries at all rather than a short one.
        ChangelogRecipe(
            bundleID: "com.macpaw.CleanMyMac5",
            source: URL(string: "https://macpaw.com/cleanmymac/whats-new")!,
            entryPattern:
                #"<h2 class="version">Update (?<version>[0-9.]+)</h2>\s*"#
                + #"<span class="date">(?:<span[^>]*>[^<]*</span>)?(?<date>[^<]*)</span>"#
                + #"(?<body>.*?)(?=<h2 class="version">|</section>)"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<p[^>]*>(?<item>.*?)</p>"#,
            ]),
        ])
}
