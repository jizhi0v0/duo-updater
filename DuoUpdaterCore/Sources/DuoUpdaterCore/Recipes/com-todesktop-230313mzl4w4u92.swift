import Foundation

enum com_todesktop_230313mzl4w4u92 {
    static let set = AppRecipeSet(
        family: "com-todesktop-230313mzl4w4u92",
        probes: [
        // Cursor — official update API; the first `version` field is the latest
        // build. Single channel (its "stable"/"latest" tracks resolve to the same
        // build). One-click: the same JSON carries `downloadUrl` → the arm64
        // `Cursor-darwin-arm64.dmg` on downloads.cursor.com. (Cursor self-updates via
        // ToDesktop; this is the fallback, guarded by the same-Team gate.)
        VendorProbeRecipe(
            bundleID: "com.todesktop.230313mzl4w4u92",
            url: URL(string: "https://api2.cursor.sh/updates/api/download/latest/darwin-arm64/cursor")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.cursor.com/downloads"),
            changelogURL: URL(string: "https://www.cursor.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""downloadUrl"\s*:\s*"(https://downloads\.cursor\.com/[^"]+\.dmg)""#),
                kind: .dmg)),
        ],
        changelogs: [
        // History: docs/app-audits/com-todesktop-230313mzl4w4u92.md#历史与实测
        // Cursor — the changelog is organised as dated POSTS, not versions: nothing
        // on the page carries a "3.16.17" anywhere, so the date takes the version
        // column and the post's headline becomes the entry title (same shape as
        // Codex, `Recipes/com-openai-codex.swift`). Structure per post:
        //   <a href="/changelog/08-13-26"><time dateTime="2026-08-13T…">Aug 13, 2026</time></a>
        //   … <h1 class="type-lg" id="…"><a href="/changelog/08-13-26">Title</a></h1>
        //   … <div class="prose prose--block"><p>…</p><ul><li>…</li></ul></div>
        //
        // Two things the real response teaches that the markup doesn't:
        //  • The document contains its whole `<main>` TWICE (it has two `</html>`
        //    tags — a Next.js streaming artifact), so every post matches twice.
        //    `ChangelogExtractor` de-duplicates on version+title; without that the
        //    pane listed each release two rows apart.
        //  • The last post has no following post to stop at, so `<footer` closes the
        //    body — otherwise it swallowed the page chrome as "items" (History has
        //    the size).
        // `www.cursor.com` 308s to the apex domain; followed once here rather than
        // on every fetch.
        ChangelogRecipe(
            bundleID: "com.todesktop.230313mzl4w4u92",
            source: URL(string: "https://cursor.com/changelog")!,
            entryPattern:
                #"href="/changelog/[^"]+"><time[^>]*>(?<version>[^<]+)</time>.*?"#
                + #"<h1[^>]*>\s*<a[^>]*href="/changelog/[^"]+"[^>]*>(?<title>.*?)</a>\s*</h1>.*?"#
                + #"<div class="prose[^"]*">(?<body>.*?)(?=<p class="text-theme-text-sec|<footer|\z)"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<p>(?<item>.*?)</p>"#
            ],
            maxEntries: 20),
        ])
}
