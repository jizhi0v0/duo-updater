import Foundation

enum com_goodsnooze_MacWhisper {
    static let set = AppRecipeSet(
        family: "com-goodsnooze-MacWhisper",
        changelogs: [
        // MacWhisper — its Sparkle appcast carries no `<description>` on any of
        // its 210 items, only a `sparkle:releaseNotesLink` pointing every release
        // at ONE shared page. So the source-supplied `changelogURL` renders the
        // whole history in a web view no matter which version you are on. That
        // page is plain, hand-written HTML and splits cleanly per version:
        //
        //   <h2>14.8</h2>
        //   <h3>New:</h3>
        //   <li>Dictation: You can now export …</li>
        //   <h3>Bugfixes:</h3>
        //   <li>Fixed: …</li>
        //
        // The `<li>`s are NOT wrapped in a `<ul>` — the vendor emits them bare —
        // so the body is everything up to the next `<h2>`. The `<h3>` group
        // headings are dropped; the items read fine without them. 121 entries
        // parse from the live page (2026-08-31), head 14.8.
        ChangelogRecipe(
            bundleID: "com.goodsnooze.macwhisper",
            source: URL(string: "https://macwhisper-site.vercel.app/release_notes.html")!,
            entryPattern: #"<h2>(?<version>[0-9][^<]*)</h2>(?<body>.*?)(?=<h2>|\z)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
