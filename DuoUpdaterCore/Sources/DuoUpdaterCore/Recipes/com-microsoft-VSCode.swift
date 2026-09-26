import Foundation

enum com_microsoft_VSCode {
    static let set = AppRecipeSet(
        family: "com-microsoft-VSCode",
        probes: [
        // History: docs/app-audits/com-microsoft-VSCode.md#历史与实测
        // VS Code — Microsoft's official update API. `name` is the version.
        VendorProbeRecipe(
            bundleID: "com.microsoft.VSCode",
            url: URL(string: "https://update.code.visualstudio.com/api/update/darwin-arm64/stable/latest")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://code.visualstudio.com/updates"),
            // `/latest/darwin-arm64/stable` 302-redirects to the official zip.
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://update.code.visualstudio.com/latest/darwin-arm64/stable")!),
                kind: .zip)),

        // VS Code Insiders — same update API on the `insider` track, its own
        // bundle id `com.microsoft.VSCodeInsiders` (display name "Code - Insiders",
        // so `ReleaseChannel.detect` reads the standalone "Insiders" word → .preview;
        // the bundle id has no `.insiders`/`-insiders` suffix to match on). CRUCIAL:
        // the installed `CFBundleShortVersionString` carries the `-insider` suffix
        // (e.g. "1.124.0-insider"), so the version pattern MUST keep it too — the stable
        // `\d+\.\d+\.\d+` would extract a bare "1.124.0" and read every install as
        // perpetually out-of-date. `name` only bumps on the ~monthly minor (the
        // daily builds differ by commit hash, which the Info.plist doesn't expose),
        // so detection is monthly-granular; Insiders self-updates daily anyway, and
        // comparing on the suffixed name can only ever say "up to date" or a real
        // minor bump — never a phantom update. One-click mirrors stable (zip swap).
        VendorProbeRecipe(
            bundleID: "com.microsoft.VSCodeInsiders",
            url: URL(string: "https://update.code.visualstudio.com/api/update/darwin-arm64/insider/latest")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+-insider)""#,
            changelogURL: URL(string: "https://code.visualstudio.com/updates"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://update.code.visualstudio.com/latest/darwin-arm64/insider")!),
                kind: .zip),
            channel: .preview),
        ],
        changelogs: [
        // VS Code — the official `/updates` page redirects to the latest stable
        // release page (e.g. /updates/v1_123). The page comes in two layouts, and
        // the pattern takes either, because only the newest page moved to the
        // second one (1.139; 1.138 and older still render the first), so a vendor
        // rollback must not break the recipe a second time.
        //
        // Layout 1 (1.138 and earlier):
        //   <h1>Visual Studio Code 1.123</h1>
        //   ...<hr><p><em>Release date: June 3, 2026</em></p>
        //   ...<ul><li><a …>…</a>: …</li>...</ul>
        //   [<blockquote><p>…event plug…</p></blockquote>]   ← optional, varies
        //   [<p><em>…generated using GitHub Copilot…</em></p>]  ← optional, varies
        //   <p>Happy Coding!</p>
        // Layout 2 (1.139 onward):
        //   <h1>Visual Studio Code 1.139</h1>
        //   <p class="release-metadata"><span>Released September 23, 2026</span>…
        //   …<details class="release-downloads">…<dl>…</dl></details>…
        //   <section class="release-highlights" …><h2>…</h2><p>…</p>
        //   <ul><li><p><a …>…</a>: …</p></li>…</ul>
        //   </section>
        //
        // In both, the highlights <ul> is the first list after the date (layout
        // 2's download links are a <dl>, not a list), and the close anchor pins
        // it: `</section>` in layout 2, "Happy Coding!" in layout 1. In layout 1,
        // between `</ul>` and the close anchor the page puts zero or more asides
        // — a <blockquote> (an event plug, e.g. "VS Code Live at Build") or a
        // plain <p> note (the Copilot disclaimer, #697) — matched as a run of
        // either, so one appearing, disappearing or swapping for the other
        // doesn't break the close anchor. A <p> aside may not contain a <ul>,
        // which keeps it a paragraph and not a way round the "first list"
        // anchor. We intentionally parse the latest release only; the page
        // itself is the vendor's stable "what changed now" surface.
        ChangelogRecipe(
            bundleID: "com.microsoft.VSCode",
            source: URL(string: "https://code.visualstudio.com/updates")!,
            entryPattern:
                #"<h1>Visual Studio Code (?<version>[0-9.]+)</h1>\s*"#
                + #".*?(?:<p class="release-metadata"><span>Released|<p><em>Release date:)"#
                + #"\s*(?<date>[^<]+)<"#
                + #".*?<ul>(?<body>.*?)</ul>\s*"#
                + #"(?:</section>"#
                + #"|(?:(?:<blockquote>.*?</blockquote>|<p>(?:(?!</p>|<ul>).)*</p>)\s*)*"#
                + #"<p>Happy Coding!</p>)"#,
            itemPatterns: [#"<li>\s*(?:<p>)?(?<item>.*?)(?:</p>)?\s*</li>"#],
            maxEntries: 1),
        ],
        channelProofs: [
        ChannelProofKey("com.microsoft.VSCodeInsiders", .preview): .artifact(#"/download/insider/"#),
        ])
}
