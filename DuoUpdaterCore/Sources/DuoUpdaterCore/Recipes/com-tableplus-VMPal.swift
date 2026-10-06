import Foundation

enum com_tableplus_VMPal {
    static let set = AppRecipeSet(
        family: "com-tableplus-VMPal",
        changelogs: [
        // History: docs/app-audits/com-tableplus-VMPal.md#历史与实测
        // VMPal — the TablePlus team's VM app. One `<li class="vp-release">` per
        // build on vmpal.com/changelog, newest first:
        //   <h2>VMPal 0.36</h2> <p>Build 36</p> <time datetime="2026-10-06">…
        //   <div class="vp-release-body"> <ul><li>…</li></ul> </div>
        //
        // Read from the page rather than left to the appcast's inline
        // `<description>`: that body is the same template as TablePlus's feed
        // (`<h2>Build 36 - <tagline></h2>`, `<h4>Release date…</h4>`, `<ol>`), and
        // `AppcastHTMLChangelogParser` folds the `<h2>` in as a change line, so
        // every release would open with a bullet repeating the build number and
        // the product tagline. The page states the marketing version and an ISO
        // date and nothing else in the body.
        //
        // The date group is optional so an entry the vendor publishes without a
        // `<time>` still renders; it may not reach past the release's own closing
        // `</li>`, or it would borrow the next release's date. The `<li>` items
        // are matched only inside `vp-release-body`, which is why the outer
        // `<li class="vp-release">` cannot be read as an item.
        ChangelogRecipe(
            bundleID: "com.tableplus.vmpal",
            source: URL(string: "https://vmpal.com/changelog")!,
            entryPattern:
                #"<li[^>]*class="vp-release"[^>]*>.*?"#
                + #"<h2[^>]*>\s*VMPal (?<version>\d+\.\d+(?:\.\d+)?)\s*</h2>"#
                + #"(?:(?:(?!</li>).)*?<time[^>]*datetime="(?<date>[^"]+)")?"#
                + #".*?<div[^>]*class="vp-release-body"[^>]*>(?<body>.*?)</div>"#,
            itemPatterns: [#"<li[^>]*>\s*(?<item>.*?)\s*</li>"#]),
        ],
        sparkleFeeds: [
        // VMPal — ships Sparkle with an `SUPublicEDKey` but no `SUFeedURL`: the
        // address is assembled in code from two strings in the main binary,
        // `https://vmpal.com` and `apps/version.xml`. One feed, no
        // `<sparkle:channel>` on its items and no beta header (the
        // `X-Tiny-Beta-Update` TablePlus answers to changes nothing here), so
        // there is no channel to bind. Items carry `sparkle:edSignature` and a
        // dmg enclosure on files.vmpal.com.
        //
        // The feed's `<minimumSystemVersion>` is UNPREFIXED and the document
        // never binds the Sparkle namespace on an ancestor of it (the root
        // carries a plain `sparkle="…"` attribute, not `xmlns:sparkle`), so
        // `SparkleAppcastParser` does not read it as Sparkle's floor. Today that
        // floor equals the app's own `LSMinimumSystemVersion` (26.0), which every
        // installed copy already satisfies.
        "com.tableplus.vmpal": URL(string: "https://vmpal.com/apps/version.xml")!,
        ])
}
