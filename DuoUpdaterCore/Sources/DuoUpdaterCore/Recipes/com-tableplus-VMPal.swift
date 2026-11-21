import Foundation

enum com_tableplus_VMPal {
    static let set = AppRecipeSet(
        family: "com-tableplus-VMPal",
        changelogs: [
        // History: docs/app-audits/com-tableplus-VMPal.md#历史与实测
        // The macOS release notes use the TablePlus blog's heading layout:
        // h3 with marketing version and build, h4 with date, h5 with download,
        // then the change list. Match adjacent elements so a partial entry
        // cannot borrow the next release's metadata or list.
        //
        // Read from the page rather than left to the appcast's inline
        // `<description>`: that body is the same template as TablePlus's feed
        // (`<h2>Build 36 - <tagline></h2>`, `<h4>Release date…</h4>`, `<ol>`), and
        // `AppcastHTMLChangelogParser` folds the `<h2>` in as a change line, so
        // every release would open with a bullet repeating the build number and
        // the product tagline.
        ChangelogRecipe(
            bundleID: "com.tableplus.vmpal",
            source: URL(string: "https://vmpal.com/blog/changelogs")!,
            entryPattern:
                #"<h3\b[^>]*>\s*Version\s+(?<version>\d+\.\d+(?:\.\d+)?)\s*\(\d+\)\s*</h3>"#
                + #"(?:\s*<h4\b[^>]*>\s*Release date:\s*(?<date>[0-9]{1,2} [A-Za-z]+ [0-9]{4})\.?\s*</h4>)?"#
                + #"(?:\s*<h5\b[^>]*>\s*<a\b[^>]*>Download</a>\s*</h5>)?"#
                + #"\s*<ul\b[^>]*>(?<body>(?:(?!<h3\b).)*?)</ul>"#,
            itemPatterns: [#"<li\b[^>]*>\s*(?<item>.*?)\s*</li>"#]),
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
