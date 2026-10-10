import Foundation

enum com_kagi_kagimacOS {
    static let set = AppRecipeSet(
        family: "com-kagi-kagimacOS",
        probes: [
        // Orion (Kagi) — official Sparkle appcast under the macOS-major flavor dir
        // (`26_0`, the same path the Homebrew cask download uses; the bare
        // /updates/appcast.xml is a STALE stub frozen at 1.0.0 — don't use it). The
        // feed lists releases ASCENDING, so selectHighest (not first match, which is
        // the oldest, e.g. 0.99) picks the current build. We extract
        // `sparkle:shortVersionString` (MARKETING version, e.g. 1.0.8) — NOT
        // `sparkle:version` (the build, e.g. 147/147.1). Without `versionIsBuild` a
        // vendor probe populates only `shortVersion` (`VendorProbeSource`), so
        // UpdateChecker compares against the installed
        // CFBundleShortVersionString (e.g. 1.0.8); feeding the build (e.g. "147.1") would compare
        // 147 > 1 and invent a permanent phantom update. Trade-off: blind to a
        // build-only rebuild at an unchanged marketing version — the conservative,
        // never-lie choice. One-click: the feed is ASCENDING, so the install takes
        // the LAST `<enclosure url=…zip>` (newest) — `.bodyPatternLast`, mirroring
        // `selectHighest` on the version side; first-match would grab the oldest.
        // (Orion self-updates via Sparkle; fallback behind the same-Team gate.)
        VendorProbeRecipe(
            bundleID: "com.kagi.kagimacOS",
            url: URL(string: "https://cdn.kagi.com/updates/26_0/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+(?:\.[0-9]+)+)</sparkle:shortVersionString>"#,
            downloadURL: URL(string: "https://browser.kagi.com/"),
            // The page the appcast's own `<sparkle:releaseNotesLink>` names. The
            // browser.kagi.com spelling 302s to a cdn.kagi.com copy that stopped
            // at 1.1.
            changelogURL: URL(string: "https://orionbrowser.com/updates/orion-release-notes.html"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .bodyPatternLast(#"url="(https://[^"]+\.zip)""#),
                kind: .zip)),
        ],
        changelogs: [
        // History: docs/app-audits/com-kagi-kagimacOS.md#历史与实测
        // Orion's macOS release notes at orionbrowser.com, the page every item of
        // the appcast links. One `<h2 id="macos-orion-…">` per release, newest
        // first. Since 1.0 the heading is `<b>Orion 1.1.3 (152)</b> ✴︎ Sep 28,
        // 2026` with `<h3>` sections over `<ul>`s; before it,
        // `Orion 0.99.138 - Nov 18, 2025` with `<h2>` sections (no id).
        //
        //   * Stable only: the version must follow "Orion " directly, so the
        //     "Orion RC …" and "Orion Beta …" blocks still on the page (RC notes
        //     now have a page of their own) are skipped.
        //   * The version is the marketing number the appcast's
        //     `shortVersionString` carries; the build in parentheses is dropped.
        //     A suffix inside the `<b>` ("- hotfix") becomes the entry's title,
        //     which keeps the 1.1.2 hotfix (151) and 1.1.2 (150) as two entries.
        //   * The major is one or two digits. A stretch of 2024 releases is titled
        //     "Orion 130.2", "Orion 128.2.1", "Orion 127.3" — the WebKit-style
        //     number, not the `0.99.x` marketing version those builds shipped as —
        //     and those must not be entries: `Changelog.carries(version:)` judges
        //     the page by its HIGHEST version-shaped entry, so a `130.2` would make
        //     the page look ahead of every future 1.x/2.x and keep a stale cached
        //     page from ever being re-read. Their blocks are skipped like the RC
        //     ones: the entry above still ends at their heading.
        //   * A body runs to the next release heading (an `<h2>` whose id starts
        //     `macos-orion-`), so the old layout's section `<h2>`s stay inside it
        //     and become headings along with the new layout's `<h3>`s.
        ChangelogRecipe(
            bundleID: "com.kagi.kagimacOS",
            source: URL(string: "https://orionbrowser.com/updates/orion-release-notes.html")!,
            entryPattern:
                #"<h2[^>]*\bid="macos-orion-[^"]*"[^>]*>\s*(?:<b>\s*)?Orion\s+(?<version>\d{1,2}(?:\.\d+)+)"#
                + #"(?:\s*\(\d+\))?(?:\s*-\s*(?<title>[^<]+?)(?=\s*</b>))?\s*(?:</b>)?"#
                + #"\s*(?:\x{2734}\x{FE0E}?|-)?\s*(?<date>[^<]*?)\s*</h2>"#
                + #"(?<body>.*?)(?=<h2[^>]*\bid="macos-orion-|</main>|</body>)"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<p[^>]*>(?<item>.*?)</p>"#,
            ],
            headingPattern: #"<h[23]\b(?![^>]*\bid="macos-orion-)[^>]*>(?<heading>.*?)</h[23]>"#),
        ])
}
