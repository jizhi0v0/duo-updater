import Foundation

enum com_proxyman_NSProxy {
    static let set = AppRecipeSet(
        family: "com-proxyman-NSProxy",
        changelogs: [
        // History: docs/app-audits/com-proxyman-NSProxy.md#历史与实测
        // Proxyman — GitHub releases, not the appcast's inline notes.
        //
        // The Sparkle feed (`proxyman.com/osx/version.xml`) has ONE item, and its
        // `<description>` is the whole cumulative changelog: every version back to
        // 1.x, each under its own `<h2>`, with `<li>` open and close tags that do
        // not pair. `AppcastHTMLChangelogParser` therefore refuses it as
        // unstructured and the pane shows the raw HTML; even a balanced copy would
        // land as one entry titled with the newest version. This recipe outranks
        // those inline notes in the pane's order, so it replaces them.
        //
        // `ProxymanApp/Proxyman` publishes one release per version, and each body
        // is Markdown under category headings (`Features` / `Improvements` /
        // `Bug Fixes`, spelled with variations over the years). The tag IS the
        // `CFBundleShortVersionString` (`26.0.1`, no `v` prefix), so no
        // `tagPattern`. The repo is the Mac app's alone. `.stable` keeps GitHub
        // prereleases out; the repo has one, `1.0`, with a bulleted body that
        // would otherwise parse.
        //
        // `skipSections` drops `Screenshots`, at `##` or `###` (the parser strips
        // the level). Its bullets are captions, each followed by an image or a
        // video link, e.g. "Split View": the images do not render here, so each
        // caption would read as a change of its own.
        //
        // `per_page=20` against `maxEntries: 15`: enough slack for a release the
        // decoder skips (an empty body) without fetching a page several times the
        // size of what the rail shows.
        ChangelogRecipe(
            bundleID: "com.proxyman.NSProxy",
            source: URL(
                string: "https://api.github.com/repos/ProxymanApp/Proxyman/releases?per_page=20")!,
            mode: .json,
            maxEntries: 15,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            skipSections: ["Screenshots"]),
        ])
}
