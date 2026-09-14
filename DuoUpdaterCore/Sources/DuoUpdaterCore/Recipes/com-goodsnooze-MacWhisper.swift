import Foundation

enum com_goodsnooze_MacWhisper {
    static let set = AppRecipeSet(
        family: "com-goodsnooze-MacWhisper",
        changelogs: [
        // History: docs/app-audits/com-goodsnooze-MacWhisper.md#历史与实测
        // MacWhisper — when checked (History) its Sparkle appcast carried no
        // `<description>` on any of its items, only a `sparkle:releaseNotesLink`,
        // and most items shared ONE page (about one in seven pointed elsewhere
        // when checked; History has the counts). So the source-supplied
        // `changelogURL` renders the whole history in a web view whichever current
        // version you are on. That page is plain, hand-written HTML and splits
        // cleanly per version, e.g.:
        //
        //   <h2>14.8</h2>
        //   <h3>New:</h3>
        //   <li>Dictation: You can now export …</li>
        //   <h3>Bugfixes:</h3>
        //   <li>Fixed: …</li>
        //
        // The `<li>`s are NOT wrapped in a `<ul>` — the vendor emits them bare —
        // so the body is everything up to the next `<h2>`. The `<h3>` group
        // headings are dropped; the items read fine without them.
        ChangelogRecipe(
            bundleID: "com.goodsnooze.macwhisper",
            source: URL(string: "https://macwhisper-site.vercel.app/release_notes.html")!,
            entryPattern: #"<h2>(?<version>[0-9][^<]*)</h2>(?<body>.*?)(?=<h2>|\z)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
