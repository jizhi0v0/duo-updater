import Foundation

enum ai_capy_desktop {
    static let set = AppRecipeSet(
        family: "ai-capy-desktop",
        changelogs: [
        // History: docs/app-audits/ai-capy-desktop.md#历史与实测
        // Capy — detection and install come from `ElectronManifestSource` (the
        // bundle's own `app-update.yml`); this recipe only supplies the notes the
        // manifest doesn't carry.
        //
        // capy.ai/changelog is server-rendered, newest first, one
        // `<article id="v0-4-3">` per release: a `<time>` with the display date,
        // an `<h2><a>Capy 0.4.3</a></h2>`, a one-line `<p>` subtitle (kept as the
        // title), then prose. The notes are `<p class="font-inter …">` paragraphs
        // under `<h3>` section headings, with screenshots between them; the
        // subtitle `<p>` has a different class, so the item pattern cannot take it
        // a second time.
        //
        // The version group requires digits. The page also carries a `Capy Beta`
        // article (`id="vbeta"`, the pre-desktop launch post) with no version,
        // and the `v[0-9]` id anchor plus the digit-only version skip it.
        //
        // Stable only. `ai.capy.desktop.nightly` is a separate bundle id with its
        // own manifest and gets no recipe: its `0.4.3-nightly.<date>.<n>` builds
        // run ahead of the page, which documents stable releases only.
        ChangelogRecipe(
            bundleID: "ai.capy.desktop",
            source: URL(string: "https://capy.ai/changelog")!,
            entryPattern:
                #"<article\b[^>]*\bid="v[0-9][0-9-]*"[^>]*>\s*"#
                + #"(?:<time\b[^>]*>(?<date>[^<]*)</time>\s*)?"#
                + #"<h2\b[^>]*>\s*<a\b[^>]*>\s*Capy\s+(?<version>[0-9]+(?:\.[0-9]+){1,3})\s*</a>\s*</h2>\s*"#
                + #"(?:<p\b[^>]*>(?<title>[^<]*)</p>)?"#
                + #"(?<body>.*?)</article>"#,
            itemPatterns: [
                #"<p\b[^>]*\bclass="font-inter[^"]*"[^>]*>(?<item>.*?)</p>"#,
                #"<li\b[^>]*>(?<item>.*?)</li>"#,
            ],
            maxEntries: 20,
            imagePattern: #"<img\b[^>]*\bsrc="(https://[^"]+)""#,
            headingPattern: #"<h3\b[^>]*>(?<heading>.*?)</h3>"#),
        ])
}
