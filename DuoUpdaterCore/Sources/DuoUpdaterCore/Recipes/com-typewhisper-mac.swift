import Foundation

enum com_typewhisper_mac {
    static let set = AppRecipeSet(
        family: "com-typewhisper-mac",
        changelogs: [
        // History: docs/app-audits/com-typewhisper-mac.md#历史与实测
        // TypeWhisper — no notes in the appcast either. The official changelog
        // page is the vendor's own, and it interleaves **macOS and Windows**
        // releases in one list, so the entry pattern is anchored on the card's
        // `id`, which carries both the platform and the version tag. Getting the
        // platform wrong shows Windows notes under a Mac version.
        //
        //   <details class="utility-entry" id="mac-v1.7.0" … data-platform="mac" …>
        //   <summary …><h3 …>…<span class="utility-entry__name">v1.7.0</span>…
        //   <time class="utility-entry__date" dateTime="…">October 2, 2026</time></h3></summary>
        //   <div class="utility-entry__body"><div class="site-prose utility-notes">
        //   <p>…</p><h4>Highlights</h4><ul><li>…</li></ul></div>…</div></details>
        //
        // The version comes from the `id`, not the visible title: a few titles
        // are free text ("TypeWhisper 1.0", "0.7.0 - Notch Indicator") while the
        // id is always `mac-v<tag>`. The gaps are TEMPERED lazy scans that stop at
        // `</details>`, not plain `.*?`: some old cards carry no notes block (just
        // "No detailed release notes."), and a plain lazy scan would run past
        // them into the NEXT card and file its notes under the wrong version.
        //
        // Only stable releases are in the served HTML. Dailies, release
        // candidates and plugin releases sit behind a "Show pre-releases" toggle
        // that loads `prereleases.json` client-side, so an rc or daily install
        // sees the stable notes, each entry labelled with its own version.
        ChangelogRecipe(
            bundleID: "com.typewhisper.mac",
            source: URL(string: "https://www.typewhisper.com/en/changelog/")!,
            entryPattern:
                #"<details[^>]*\bid="mac-v?(?<version>[^"]+)"[^>]*>"#
                + #"(?:(?!</details>).)*?<time[^>]*>(?<date>[^<]*)</time>"#
                + #"(?:(?!</details>).)*?<div class="site-prose[^"]*">(?<body>.*?)</div>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#, #"<p[^>]*>(?<item>.*?)</p>"#],
            maxEntries: 20),
        ])
}
