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
            // One-click takes the commit-pinned zip the response names in `url` and
            // checks it against `sha256hash` (hex) from the same response. It used
            // to follow `/latest/darwin-arm64/stable`, which 302s to the same zip
            // today but is resolved only when Update is pressed, so after a new
            // build lands it would name a different file from the digest the check
            // read. Taking the url out of the same body keeps the two together.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://[^"]+/stable/[0-9a-f]{40}/VSCode-darwin-arm64\.zip)""#),
                kind: .zip,
                checksumPattern: #""sha256hash"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex)),

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
        // minor bump — never a phantom update. One-click mirrors stable (the zip
        // the body names, checked against its `sha256hash`). Reading the url from
        // the body matters most here: a daily build moves the `/latest/…/insider`
        // redirect within hours of a check.
        VendorProbeRecipe(
            bundleID: "com.microsoft.VSCodeInsiders",
            url: URL(string: "https://update.code.visualstudio.com/api/update/darwin-arm64/insider/latest")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+-insider)""#,
            changelogURL: URL(string: "https://code.visualstudio.com/updates"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://[^"]+/insider/[0-9a-f]{40}/VSCode-darwin-arm64\.zip)""#),
                kind: .zip,
                checksumPattern: #""sha256hash"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex),
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

        // History: docs/app-audits/com-microsoft-VSCode.md#历史与实测
        // VS Code Insiders — two-stage. `/updates` (which redirects to the newest
        // stable page) is the index: its side nav lists every notes page newest
        // first, and the first item is `<a href="/updates/v1_N" >Insiders</a>`,
        // the page for the minor the Insiders build is on. An Insiders version
        // `1.N.0-insider` belongs to `/updates/v1_N`. The link is picked by its
        // "Insiders" label, not its position, so a nav without an Insiders item
        // yields no link (and the pane embeds the page) rather than the stable one.
        //
        // The Insiders page: `<h1>Visual Studio Code 1.N (Insiders)</h1>`,
        // `<p><em>Last updated: <date></em></p>`, then one `<h2>` per day
        // (newest first), each over a `<ul>` of one-line changes, ending at the
        // first `<hr>`. All the days form one entry, with the dates as headings.
        // The entry's version is the page's `1.N`, as the stable recipe's is,
        // not the build's `1.N.0-insider`; the page names no build.
        //
        // Right after each stable release the nav's Insiders item moves to the
        // next minor, whose page has no `<h2>` day yet. The body must start at an
        // `<h2>` before `</main>`, so that page parses to nothing and the pane
        // falls back to embedding it, until the first day's notes land.
        // A change that names a setting carries the page's "Open in VS Code /
        // Open in VS Code Insiders" menu text inline after the setting id; tag
        // stripping cannot drop it, the stable page has the same.
        ChangelogRecipe(
            bundleID: "com.microsoft.VSCodeInsiders",
            source: URL(string: "https://code.visualstudio.com/updates")!,
            entryPattern:
                #"<h1>Visual Studio Code (?<version>[0-9]+\.[0-9]+) \(Insiders\)</h1>"#
                + #"(?:(?!</main>).)*?<p><em>Last updated:\s*(?<date>[^<]+)</em></p>"#
                + #"(?:(?!</main>).)*?(?<body><h2[^>]*>(?:(?!</main>).)*?)<hr>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            maxEntries: 1,
            indexLinkPattern: #"href="(?<link>/updates/v1_[0-9]+)"\s*>\s*Insiders\s*</a>"#,
            channel: .preview,
            headingPattern: #"<h2[^>]*>(?<heading>[^<]+)</h2>"#),
        ],
        channelProofs: [
        ChannelProofKey("com.microsoft.VSCodeInsiders", .preview): .artifact(#"/download/insider/"#),
        ])
}
