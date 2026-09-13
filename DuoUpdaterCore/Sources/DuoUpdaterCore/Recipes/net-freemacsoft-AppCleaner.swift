import Foundation

enum net_freemacsoft_AppCleaner {
    static let set = AppRecipeSet(
        family: "net-freemacsoft-AppCleaner",
        changelogs: [
        // AppCleaner — freemacsoft.net/appcleaner/releasenotes.html (referenced as
        // `releaseNotesLink` in the Sparkle feed). Each version is an <h2> with the
        // version number and date, followed by a <ul> of change items:
        //   <h2>AppCleaner 3.6.8 <span class="releasedate">- 4 July, 2023</span></h2>
        //   <ul><li>…</li>…</ul>
        ChangelogRecipe(
            bundleID: "net.freemacsoft.AppCleaner",
            source: URL(string: "https://freemacsoft.net/appcleaner/releasenotes.html")!,
            entryPattern:
                #"<h2>AppCleaner\s+(?<version>[^\s<]+)\s*"#
                + #"<span[^>]*releasedate[^>]*>\s*-\s*(?<date>[^<]+)</span>.*?</h2>\s*"#
                + #"<ul[^>]*>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
